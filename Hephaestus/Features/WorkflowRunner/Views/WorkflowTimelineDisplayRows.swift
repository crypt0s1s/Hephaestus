import AnvilTheme
import SwiftUI

struct ParsedTimelineEvent {
    let key: String
    let label: String
    let status: TimelineDisplayStatus
    let sortOrder: Int
}

struct TimelineDisplayRowsBuilder {
    let timeline: String
    let stepRecords: [WorkflowStepRecord]

    var rows: [TimelineDisplayRow] {
        if !stepRecords.isEmpty {
            return stepRecordRows + timelineSupplementRows
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

    private var timelineSupplementRows: [TimelineDisplayRow] {
        guard !timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let recordTitles = stepRecords.map { $0.title.lowercased() }
        let maxStepSortOrder = stepRecords.map(\.sortOrder).max() ?? 0
        return parsedTimelineRows
            .filter { shouldIncludeSupplementalTimelineRow($0, recordTitles: recordTitles) }
            .enumerated()
            .map { index, row in
                TimelineDisplayRow(
                    id: row.id,
                    label: row.label,
                    detail: row.detail,
                    status: row.status,
                    sortOrder: maxStepSortOrder + index + 1,
                    record: row.record
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
        let events =
            timeline
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return events.isEmpty
            ? ["No orchestration updates were produced. Open full logs for details."] : events
    }

    private func shouldIncludeSupplementalTimelineRow(
        _ row: TimelineDisplayRow,
        recordTitles: [String]
    ) -> Bool {
        let label = row.label.lowercased()
        return !recordTitles.contains { title in
            label == title || label.contains(" - \(title)") || label.hasPrefix("\(title) ")
        }
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
        rows.append(
            TimelineDisplayRow(
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
            return ParsedTimelineEvent(
                key: "step-0-plan-validation", label: "Step 0 - Plan validation", status: status,
                sortOrder: 0)
        }
        if lowercased.contains("build command resolved") {
            return ParsedTimelineEvent(
                key: "step-0-build-command", label: "Step 0 - Build command", status: status, sortOrder: 1)
        }
        if lowercased.contains("implementer") {
            return phaseEvent(
                step: 1, name: "Implementer", lowercased: lowercased, status: status, baseSortOrder: 10)
        }
        if lowercased.contains("build ") {
            return phaseEvent(
                step: 2, name: "Build", lowercased: lowercased, status: status, baseSortOrder: 20)
        }
        if lowercased.contains("reviewer a") {
            return ParsedTimelineEvent(
                key: "step-3-reviewer-a", label: "Step 3.1 - Reviewer A", status: status, sortOrder: 30)
        }
        if lowercased.contains("reviewer b") {
            return ParsedTimelineEvent(
                key: "step-3-reviewer-b", label: "Step 3.2 - Reviewer B", status: status, sortOrder: 31)
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

    private func phaseQualifier(from lowercasedEvent: String) -> (
        key: String, display: String, sortOffset: Int
    ) {
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

struct WorkflowOutputSurfaceModifier: ViewModifier {
    @Environment(\.anvilTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.cozy)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
    }
}

extension View {
    func workflowOutputSurface() -> some View {
        modifier(WorkflowOutputSurfaceModifier())
    }
}
