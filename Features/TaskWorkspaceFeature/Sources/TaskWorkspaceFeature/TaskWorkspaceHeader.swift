import AnvilTheme
import AnvilUI
import SwiftUI

struct TaskHeader: View {
    let isRunning: Bool
    let runID: UUID?
    let canInspect: Bool
    let canCancel: Bool
    let handle: (TaskWorkspaceAction) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            appIcon
            titleBlock
            Spacer()
            inspectorButton
            cancelButton
            settingsButton
            statusPill
        }
        .padding(.horizontal, theme.spacing.large)
        .padding(.vertical, theme.spacing.medium)
        .background(theme.colors.panelBackground)
    }

    private var appIcon: some View {
        AnvilIconTile(systemName: "hammer.fill")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
            Text("Task Workspace")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            Text(runSubtitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var inspectorButton: some View {
        AnvilIconButton(
            systemName: "list.bullet.rectangle",
            accessibilityLabel: "Inspect run"
        ) {
            handle(.tapInspector)
        }
        .disabled(!canInspect)
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorButton)
    }

    private var cancelButton: some View {
        AnvilIconButton(
            systemName: "stop.circle",
            accessibilityLabel: "Cancel response"
        ) {
            handle(.tapCancel)
        }
        .disabled(!canCancel)
    }

    private var settingsButton: some View {
        AnvilIconButton(
            systemName: "gearshape",
            accessibilityLabel: "Provider settings"
        ) {
            handle(.tapSettings)
        }
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.settingsButton)
    }

    private var statusPill: some View {
        AnvilStatusPill(isRunning ? "Responding" : "Ready", tone: isRunning ? .warning : .success)
            .accessibilityLabel(isRunning ? "Assistant responding" : "Assistant ready")
            .accessibilityIdentifier(isRunning ? TaskWorkspaceAccessibilityID.runningStatus : "task.readyStatus")
    }

    private var runSubtitle: String {
        guard let runID else {
            return "New local run"
        }
        return "Foundry task \(runID.uuidString.prefix(8))"
    }
}
