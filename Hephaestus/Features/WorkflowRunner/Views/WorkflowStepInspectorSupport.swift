import AnvilTheme
import SwiftUI

extension WorkflowStepTiming {
    func elapsedLabel(status: WorkflowStepRecordStatus) -> String? {
        guard let elapsed = elapsedSeconds(status: status) else { return nil }
        return Self.formatDuration(elapsed)
    }

    var timeoutLabel: String? {
        timeoutSeconds.map(Self.formatDuration)
    }

    func compactRuntimeLabel(status: WorkflowStepRecordStatus?) -> String? {
        guard let status else { return nil }
        let elapsed = elapsedLabel(status: status)
        switch (elapsed, timeoutLabel, status) {
        case (.some(let elapsed), .some(let timeout), .inProgress):
            return "\(elapsed) / \(timeout)"
        case (.some(let elapsed), _, _):
            return elapsed
        case (nil, .some(let timeout), .pending):
            return "timeout \(timeout)"
        default:
            return nil
        }
    }

    private func elapsedSeconds(status: WorkflowStepRecordStatus) -> TimeInterval? {
        guard let startedAt else { return nil }
        let endDate = status == .inProgress ? Date() : (finishedAt ?? Date())
        return max(0, endDate.timeIntervalSince(startedAt))
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}

struct WorkflowStepOutputSummary {
    let record: WorkflowStepRecord

    var text: String? {
        guard let source = record.outputPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !source.isEmpty
        else {
            return nil
        }
        if isReviewerStep, let reviewSummary = ReviewFindingSummary.extract(from: source) {
            return reviewSummary
        }
        if let finalJSON = Self.finalJSONObject(in: source) {
            return finalJSON
        }
        return Self.compactTailSummary(source)
    }

    private var isReviewerStep: Bool {
        record.id.contains("reviewer") || record.title.localizedCaseInsensitiveContains("reviewer")
    }

    private static func finalJSONObject(in source: String) -> String? {
        let characters = Array(source)
        var bestRange: ClosedRange<Int>?

        for index in characters.indices.reversed()
        where characters[index] == "}" || characters[index] == "]" {
            if let range = balancedJSONRange(endingAt: index, in: characters),
                isValidJSON(String(characters[range])) {
                bestRange = range
                break
            }
        }

        guard let bestRange else { return nil }
        return prettyPrintedJSON(String(characters[bestRange]))
    }

    private static func balancedJSONRange(endingAt endIndex: Int, in characters: [Character])
        -> ClosedRange<Int>? {
        let closing = characters[endIndex]
        let opening: Character = closing == "}" ? "{" : "["
        var depth = 0
        var isEscaped = false
        var isInsideString = false

        for index in stride(from: endIndex, through: 0, by: -1) {
            let character = characters[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == closing {
                depth += 1
            } else if character == opening {
                depth -= 1
                if depth == 0 {
                    return index...endIndex
                }
            }
        }

        return nil
    }

    private static func isValidJSON(_ candidate: String) -> Bool {
        guard let data = candidate.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func prettyPrintedJSON(_ candidate: String) -> String {
        guard let data = candidate.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return candidate
        }
        return pretty
    }

    private static func compactTailSummary(_ source: String) -> String {
        let nonEmptyLines =
            source
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tail = nonEmptyLines.suffix(8).joined(separator: "\n")
        guard !tail.isEmpty else { return source }
        return tail
    }
}

struct InspectorSection: View {
    let title: String
    let text: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            Text(previewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.compact)
                .background(theme.colors.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                        .stroke(theme.colors.border, lineWidth: 1)
                }
        }
    }

    private var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 4_000
        guard trimmed.count > maxLength else { return trimmed }
        let suffix = trimmed.suffix(maxLength)
        return "... trimmed to latest \(maxLength) characters ...\n\(suffix)"
    }
}

struct TimelineStatusIcon: View {
    let status: TimelineDisplayStatus
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Group {
            switch status {
            case .inProgress:
                ProgressView()
                    .controlSize(.small)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.success)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.danger)
            case .needsFix:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.warning)
            case .pending:
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(width: 18)
    }
}

struct WorkflowStepInspectorPanelModifier: ViewModifier {
    @Environment(\.anvilTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
    }
}

extension View {
    func inspectorPanelStyle() -> some View {
        modifier(WorkflowStepInspectorPanelModifier())
    }
}
