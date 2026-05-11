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
    @State private var displayedRunKey = ""
    @State private var manuallyExpandedIDs: Set<String> = []
    @State private var manuallyCollapsedIDs: Set<String> = []
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        WorkflowRunOutputLayout {
            WorkflowRunSummaryColumn(
                rows: timelineDisplayRows,
                selectedStepID: selectedStepID,
                fullLog: fullLog,
                debugLogURL: debugLogURL,
                isShowingFullLog: $isShowingFullLog,
                performRowAction: performRowAction
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
        .animation(.easeInOut(duration: theme.motion.standard), value: manuallyExpandedIDs)
        .animation(.easeInOut(duration: theme.motion.standard), value: manuallyCollapsedIDs)
        .onAppear(perform: resetCollapseStateIfNeeded)
        .onChange(of: runKey) { _, _ in
            resetCollapseStateIfNeeded()
        }
    }

    private var timelineDisplayRows: [TimelineDisplayRow] {
        if let projection = timelineProjection {
            let collapsedIDs = WorkflowTimelineProjection.collapsedIDs(
                defaultExpandedIDs: projection.defaultExpandedIDs,
                manuallyExpandedIDs: manuallyExpandedIDs,
                manuallyCollapsedIDs: manuallyCollapsedIDs,
                in: projection.nodes
            )
            return projection.visibleNodes(collapsedIDs: collapsedIDs).map { node in
                TimelineDisplayRow(
                    id: node.id,
                    label: node.label,
                    detail: node.detail,
                    status: node.status,
                    sortOrder: 0,
                    record: node.record,
                    depth: node.depth,
                    isExpandable: node.isExpandable,
                    isExpanded: node.isExpandable && !collapsedIDs.contains(node.id)
                )
            }
        }
        return TimelineDisplayRowsBuilder(timeline: timeline, stepRecords: stepRecords).rows
    }

    private var timelineProjection: WorkflowTimelineProjection? {
        guard WorkflowTimelineProjection.hasHierarchyMetadata(stepRecords) else { return nil }
        return WorkflowTimelineProjection.make(records: stepRecords)
    }

    private var selectedRecord: WorkflowStepRecord? {
        guard let selectedStepID else { return nil }
        return stepRecords.first { $0.id == selectedStepID }
    }

    private var runKey: String {
        if let debugLogURL {
            return debugLogURL.path
        }
        let recordsKey = stepRecords.map {
            [
                $0.id,
                $0.hierarchy?.groupID ?? "",
                $0.hierarchy?.cycleIndex.map(String.init) ?? "",
                String($0.hierarchy?.sequenceOrder ?? -1),
            ].joined(separator: ":")
        }
        .joined(separator: "|")
        return "\(recordsKey)#timeline:\(timeline.count)#log:\(fullLog.count)"
    }

    private func resetCollapseStateIfNeeded() {
        guard displayedRunKey != runKey else { return }
        displayedRunKey = runKey
        manuallyExpandedIDs = []
        manuallyCollapsedIDs = []
        selectedStepID = nil
    }

    private func performRowAction(_ row: TimelineDisplayRow) {
        if row.isExpandable {
            toggleExpansion(for: row)
            return
        }
        selectedStepID = row.record?.id
    }

    private func toggleExpansion(for row: TimelineDisplayRow) {
        guard row.isExpandable else { return }
        if row.isExpanded {
            manuallyExpandedIDs.remove(row.id)
            manuallyCollapsedIDs.insert(row.id)
        } else {
            manuallyCollapsedIDs.remove(row.id)
            manuallyExpandedIDs.insert(row.id)
        }
    }
}

private struct WorkflowRunOutputLayout<Content: View, Drawer: View>: View {
    let content: Content
    let drawer: Drawer
    @Environment(\.anvilTheme) private var theme

    init(@ViewBuilder content: () -> Content, @ViewBuilder drawer: () -> Drawer) {
        self.content = content()
        self.drawer = drawer()
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.comfortable) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)

            drawer
                .frame(width: 420)
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
    let performRowAction: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            RunUpdatesSection(
                rows: rows,
                selectedStepID: selectedStepID,
                performRowAction: performRowAction
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
    let performRowAction: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            RunUpdatesHeader()
            TimelineList(rows: rows, selectedStepID: selectedStepID, performRowAction: performRowAction)
        }
    }
}

private struct RunUpdatesHeader: View {
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
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
    let performRowAction: (TimelineDisplayRow) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                TimelineListItem(
                    row: row,
                    isLast: row.id == rows.last?.id,
                    isSelected: selectedStepID == row.record?.id,
                    performRowAction: performRowAction
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
    let performRowAction: (TimelineDisplayRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                performRowAction(row)
            } label: {
                WorkflowTimelineRow(row: row, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .disabled(row.record == nil && !row.isExpandable)
            .accessibilityLabel(row.label)
            .accessibilityValue(row.detail ?? "")
            .accessibilityIdentifier("workflow.timeline.row.\(row.id)")

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
        HStack(spacing: theme.spacing.cozy) {
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
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text("Run logs")
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
                .padding(.top, theme.spacing.compact)
        } label: {
            Label("Show full logs", systemImage: "terminal")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.accent)
        }
        .workflowOutputSurface()
    }
}
