import AnvilTheme
import AppKit
import SwiftUI

struct WorkflowStepInspector: View {
    let record: WorkflowStepRecord
    let debugLogURL: URL?
    let close: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkflowStepInspectorHeader(record: record, close: close)
            Divider()
            WorkflowStepInspectorContent(record: record, debugLogURL: debugLogURL)
        }
        .frame(minHeight: 360, maxHeight: 600)
        .inspectorPanelStyle()
    }
}

private struct WorkflowStepInspectorHeader: View {
    let record: WorkflowStepRecord
    let close: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.compact) {
            TimelineStatusIcon(status: TimelineDisplayStatus(recordStatus: record.status))
            WorkflowStepInspectorTitle(record: record)
            Spacer()
            WorkflowStepInspectorCloseButton(close: close)
        }
        .padding(theme.spacing.cozy)
    }
}

private struct WorkflowStepInspectorTitle: View {
    let record: WorkflowStepRecord
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(record.title)
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text(statusLabel)
                .font(theme.typography.caption)
                .foregroundStyle(statusColor)
        }
    }

    private var statusLabel: String {
        switch record.status {
        case .pending:
            return "Pending"
        case .inProgress:
            return "In progress"
        case .succeeded:
            return "Completed"
        case .failed:
            return "Needs attention"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .pending:
            return theme.colors.textTertiary
        case .inProgress:
            return theme.colors.accent
        case .succeeded:
            return theme.colors.success
        case .failed:
            return theme.colors.danger
        }
    }
}

private struct WorkflowStepInspectorCloseButton: View {
    let close: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.textSecondary)
        .accessibilityLabel("Close step details")
    }
}

private struct WorkflowStepInspectorContent: View {
    let record: WorkflowStepRecord
    let debugLogURL: URL?
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                InspectorSection(title: "Summary", text: record.summary)
                InspectorOptionalSection(title: "Input", text: record.inputPreview)
                InspectorOptionalSection(title: "Output summary", text: WorkflowStepOutputSummary(record: record).text)
                InspectorOptionalSection(title: "Latest output", text: record.outputPreview)
                DebugLogRevealButton(debugLogURL: debugLogURL)
            }
            .padding(theme.spacing.cozy)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct InspectorOptionalSection: View {
    let title: String
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            InspectorSection(title: title, text: text)
        }
    }
}

private struct DebugLogRevealButton: View {
    let debugLogURL: URL?

    var body: some View {
        if let debugLogURL {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([debugLogURL])
            } label: {
                Label("Reveal full run log", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct WorkflowStepOutputSummary {
    let record: WorkflowStepRecord

    var text: String? {
        guard let source = record.outputPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
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

        for index in characters.indices.reversed() where characters[index] == "}" || characters[index] == "]" {
            if let range = balancedJSONRange(endingAt: index, in: characters),
               isValidJSON(String(characters[range])) {
                bestRange = range
                break
            }
        }

        guard let bestRange else { return nil }
        return prettyPrintedJSON(String(characters[bestRange]))
    }

    private static func balancedJSONRange(endingAt endIndex: Int, in characters: [Character]) -> ClosedRange<Int>? {
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
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return candidate
        }
        return pretty
    }

    private static func compactTailSummary(_ source: String) -> String {
        let nonEmptyLines = source
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tail = nonEmptyLines.suffix(8).joined(separator: "\n")
        guard !tail.isEmpty else { return source }
        return tail
    }
}

private struct InspectorSection: View {
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

private struct WorkflowStepInspectorPanelModifier: ViewModifier {
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

private extension View {
    func inspectorPanelStyle() -> some View {
        modifier(WorkflowStepInspectorPanelModifier())
    }
}
