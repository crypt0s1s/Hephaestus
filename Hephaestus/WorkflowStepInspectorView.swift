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
        HStack(alignment: .center, spacing: theme.spacing.small) {
            TimelineStatusIcon(status: TimelineDisplayStatus(recordStatus: record.status))
            WorkflowStepInspectorTitle(record: record)
            Spacer()
            WorkflowStepInspectorCloseButton(close: close)
        }
        .padding(theme.spacing.medium)
    }
}

private struct WorkflowStepInspectorTitle: View {
    let record: WorkflowStepRecord
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
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
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                InspectorSection(title: "Summary", text: record.summary)
                InspectorOptionalSection(title: "Input", text: record.inputPreview)
                InspectorOptionalSection(title: "Latest output", text: record.outputPreview)
                DebugLogRevealButton(debugLogURL: debugLogURL)
            }
            .padding(theme.spacing.medium)
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
                Label("Reveal debug log", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct InspectorSection: View {
    let title: String
    let text: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            Text(previewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.small)
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
