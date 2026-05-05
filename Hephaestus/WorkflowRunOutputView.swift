import AnvilTheme
import AnvilUI
import AppKit
import SwiftUI

struct WorkflowRunOutput: View {
    let timeline: String
    let stepRecords: [WorkflowStepRecord]
    let fullLog: String
    let debugLogURL: URL?
    @State private var isShowingFullLog = false
    @State private var selectedStepID: WorkflowStepRecord.ID?
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        WorkflowRunOutputLayout {
            WorkflowRunSummaryColumn(
                rows: timelineDisplayRows,
                selectedStepID: selectedStepID,
                fullLog: fullLog,
                debugLogURL: debugLogURL,
                isShowingFullLog: $isShowingFullLog,
                selectStep: selectStep
            )
        } drawer: {
            if let selectedRecord {
                WorkflowStepInspector(
                    record: selectedRecord,
                    debugLogURL: debugLogURL,
                    close: { selectedStepID = nil }
                )
            }
        }
        .animation(.easeInOut(duration: theme.motion.standard), value: selectedStepID)
    }

    private var timelineDisplayRows: [TimelineDisplayRow] {
        TimelineDisplayRowsBuilder(timeline: timeline, stepRecords: stepRecords).rows
    }

    private var selectedRecord: WorkflowStepRecord? {
        guard let selectedStepID else { return nil }
        return stepRecords.first { $0.id == selectedStepID }
    }

    private func selectStep(_ row: TimelineDisplayRow) {
        selectedStepID = row.record?.id
    }
}

private struct WorkflowRunOutputLayout<Content: View, Drawer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let drawer: Drawer
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        ZStack(alignment: .trailing) {
            content
            drawer
                .frame(width: 430)
                .padding(.vertical, theme.spacing.medium)
                .padding(.trailing, theme.spacing.medium)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

private struct WorkflowRunSummaryColumn: View {
    let rows: [TimelineDisplayRow]
    let selectedStepID: WorkflowStepRecord.ID?
    let fullLog: String
    let debugLogURL: URL?
    @Binding var isShowingFullLog: Bool
    let selectStep: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            RunUpdatesSection(
                rows: rows,
                selectedStepID: selectedStepID,
                selectStep: selectStep
            )

            if let debugLogURL {
                DebugLogLink(debugLogURL: debugLogURL)
            }

            if !fullLog.isEmpty {
                FullLogDisclosure(
                    fullLog: fullLog,
                    isExpanded: $isShowingFullLog
                )
            }
        }
    }
}

private struct RunUpdatesSection: View {
    let rows: [TimelineDisplayRow]
    let selectedStepID: WorkflowStepRecord.ID?
    let selectStep: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            RunUpdatesHeader()
            TimelineList(rows: rows, selectedStepID: selectedStepID, selectStep: selectStep)
        }
    }
}

private struct RunUpdatesHeader: View {
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
            Text("Run updates")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text("Click a step to inspect its prompt, feedback, and latest output.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

private struct TimelineList: View {
    let rows: [TimelineDisplayRow]
    let selectedStepID: WorkflowStepRecord.ID?
    let selectStep: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                TimelineListItem(
                    row: row,
                    isLast: row.id == rows.last?.id,
                    isSelected: selectedStepID == row.record?.id,
                    selectStep: selectStep
                )
            }
        }
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }
}

private struct TimelineListItem: View {
    let row: TimelineDisplayRow
    let isLast: Bool
    let isSelected: Bool
    let selectStep: (TimelineDisplayRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                selectStep(row)
            } label: {
                WorkflowTimelineRow(row: row, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .disabled(row.record == nil)

            TimelineDivider(isVisible: !isLast)
        }
    }
}

private struct TimelineDivider: View {
    let isVisible: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Divider()
            .padding(.leading, 46)
            .opacity(isVisible ? 1 : 0)
    }
}

private struct DebugLogLink: View {
    let debugLogURL: URL
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            DebugLogIcon()
            DebugLogPath(debugLogURL: debugLogURL)
            Spacer()
            revealButton
        }
        .workflowOutputSurface()
    }

    private var revealButton: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([debugLogURL])
        } label: {
            Label("Reveal", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.bordered)
    }
}

private struct DebugLogIcon: View {
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.accent)
            .frame(width: 28, height: 28)
            .background(theme.colors.selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    }
}

private struct DebugLogPath: View {
    let debugLogURL: URL
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
            Text("Debug log")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
            Text(debugLogURL.path)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct FullLogDisclosure: View {
    let fullLog: String
    @Binding var isExpanded: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            AnvilLogSurface(fullLog, minHeight: 220)
                .padding(.top, theme.spacing.small)
        } label: {
            Label("Show full logs", systemImage: "terminal")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.accent)
        }
        .workflowOutputSurface()
    }
}

private struct WorkflowTimelineRow: View {
    let row: TimelineDisplayRow
    let isSelected: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.small) {
            TimelineStatusIcon(status: row.status)
            TimelineText(row: row)
            Spacer(minLength: theme.spacing.small)
            TimelineChevron(isVisible: row.record != nil)
        }
        .padding(.horizontal, theme.spacing.medium)
        .padding(.vertical, theme.spacing.small)
        .background(isSelected ? theme.colors.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineText: View {
    let row: TimelineDisplayRow
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
            Text(row.label)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)

            if let detail = row.detail {
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct TimelineChevron: View {
    let isVisible: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.colors.textTertiary)
            .opacity(isVisible ? 1 : 0)
    }
}

enum TimelineDisplayStatus {
    case pending
    case inProgress
    case succeeded
    case failed

    init(recordStatus: WorkflowStepRecordStatus) {
        switch recordStatus {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        }
    }
}

private struct TimelineDisplayRow: Identifiable {
    let id: String
    var label: String
    var detail: String?
    var status: TimelineDisplayStatus
    var sortOrder: Int
    var record: WorkflowStepRecord?
}

private struct ParsedTimelineEvent {
    let key: String
    let label: String
    let status: TimelineDisplayStatus
    let sortOrder: Int
}

private struct TimelineDisplayRowsBuilder {
    let timeline: String
    let stepRecords: [WorkflowStepRecord]

    var rows: [TimelineDisplayRow] {
        if !stepRecords.isEmpty {
            return stepRecordRows
        }
        return parsedTimelineRows
    }

    private var stepRecordRows: [TimelineDisplayRow] {
        stepRecords.sorted { $0.sortOrder < $1.sortOrder }.map { record in
            TimelineDisplayRow(
                id: record.id,
                label: record.title,
                detail: record.summary,
                status: TimelineDisplayStatus(recordStatus: record.status),
                sortOrder: record.sortOrder,
                record: record
            )
        }
    }

    private var parsedTimelineRows: [TimelineDisplayRow] {
        var rows: [TimelineDisplayRow] = []
        var activeRowIndexByKey: [String: Int] = [:]

        for event in timelineEvents {
            merge(parse(event), into: &rows, activeRowIndexByKey: &activeRowIndexByKey)
        }

        return rows.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var timelineEvents: [String] {
        let events = timeline
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return events.isEmpty ? ["No orchestration updates were produced. Open full logs for details."] : events
    }

    private func merge(
        _ parsed: ParsedTimelineEvent,
        into rows: inout [TimelineDisplayRow],
        activeRowIndexByKey: inout [String: Int]
    ) {
        if let rowIndex = activeRowIndexByKey[parsed.key] {
            rows[rowIndex].label = parsed.label
            rows[rowIndex].status = parsed.status
            rows[rowIndex].sortOrder = parsed.sortOrder
            return
        }

        activeRowIndexByKey[parsed.key] = rows.count
        rows.append(TimelineDisplayRow(
            id: "\(parsed.key)-\(rows.count)",
            label: parsed.label,
            detail: nil,
            status: parsed.status,
            sortOrder: parsed.sortOrder,
            record: nil
        ))
    }

    private func parse(_ event: String) -> ParsedTimelineEvent {
        let trimmed = event.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let lowercased = trimmed.lowercased()
        let status = timelineStatus(for: lowercased)

        if lowercased.contains("validating plan path")
            || lowercased.contains("plan validation passed")
            || lowercased.contains("plan validation failed") {
            return ParsedTimelineEvent(key: "step-0-plan-validation", label: "Step 0 - Plan validation", status: status, sortOrder: 0)
        }
        if lowercased.contains("build command resolved") {
            return ParsedTimelineEvent(key: "step-0-build-command", label: "Step 0 - Build command", status: status, sortOrder: 1)
        }
        if lowercased.contains("implementer") {
            return phaseEvent(step: 1, name: "Implementer", lowercased: lowercased, status: status, baseSortOrder: 10)
        }
        if lowercased.contains("build ") {
            return phaseEvent(step: 2, name: "Build", lowercased: lowercased, status: status, baseSortOrder: 20)
        }
        if lowercased.contains("reviewer a") {
            return ParsedTimelineEvent(key: "step-3-reviewer-a", label: "Step 3.1 - Reviewer A", status: status, sortOrder: 30)
        }
        if lowercased.contains("reviewer b") {
            return ParsedTimelineEvent(key: "step-3-reviewer-b", label: "Step 3.2 - Reviewer B", status: status, sortOrder: 31)
        }
        return ParsedTimelineEvent(key: trimmed, label: trimmed, status: status, sortOrder: 1000)
    }

    private func phaseEvent(
        step: Int,
        name: String,
        lowercased: String,
        status: TimelineDisplayStatus,
        baseSortOrder: Int
    ) -> ParsedTimelineEvent {
        let cycleLabel = phaseQualifier(from: lowercased)
        return ParsedTimelineEvent(
            key: "step-\(step)-\(name.lowercased())-\(cycleLabel.key)",
            label: "Step \(step) - \(name)\(cycleLabel.display)",
            status: status,
            sortOrder: baseSortOrder + cycleLabel.sortOffset
        )
    }

    private func timelineStatus(for lowercasedEvent: String) -> TimelineDisplayStatus {
        if lowercasedEvent.contains("failed")
            || lowercasedEvent.contains("stopped")
            || lowercasedEvent.contains("blocking findings") {
            return .failed
        }
        if lowercasedEvent.contains("started")
            || lowercasedEvent.contains("validating")
            || lowercasedEvent.contains("preparing") {
            return .inProgress
        }
        if lowercasedEvent.contains("passed")
            || lowercasedEvent.contains("resolved")
            || lowercasedEvent.contains("finished")
            || lowercasedEvent.contains("completed")
            || lowercasedEvent.contains("returned") {
            return .succeeded
        }
        return .pending
    }

    private func phaseQualifier(from lowercasedEvent: String) -> (key: String, display: String, sortOffset: Int) {
        if lowercasedEvent.contains("initial implementation") {
            return ("initial", " (initial implementation)", 0)
        }
        if let range = lowercasedEvent.range(of: #"fix cycle \d+"#, options: .regularExpression) {
            let value = String(lowercasedEvent[range])
            let cycleNumber = Int(value.components(separatedBy: " ").last ?? "") ?? 0
            return (value.replacingOccurrences(of: " ", with: "-"), " (\(value))", cycleNumber)
        }
        return ("current", "", 0)
    }
}

private struct WorkflowOutputSurfaceModifier: ViewModifier {
    @Environment(\.anvilTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.medium)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
    }
}

private extension View {
    func workflowOutputSurface() -> some View {
        modifier(WorkflowOutputSurfaceModifier())
    }
}
