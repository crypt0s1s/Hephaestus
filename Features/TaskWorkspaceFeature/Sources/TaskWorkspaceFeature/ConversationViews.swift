import AnvilTheme
import AnvilUI
import SwiftUI

struct EmptyTaskState: View {
    var body: some View {
        AnvilEmptyState(
            title: "Start a focused task",
            message: "Describe the task, then inspect the run as it moves through the workspace.",
            systemImage: "sparkles"
        )
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.emptyState)
    }
}

struct RunningStatus: View {
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.small) {
            ProgressView()
                .controlSize(.small)
            AnvilStatusText("Foundry is running")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, theme.spacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.runningStatus)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        AnvilBanner(
            message: message,
            tone: .danger,
            systemImage: "exclamationmark.triangle.fill"
        )
            .accessibilityLabel("Task error: \(message)")
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.errorBanner)
    }
}

struct MessageBubble: View {
    let message: ConversationMessageState
    @Environment(\.anvilTheme) private var theme

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom) {
            leadingSpacer
            bubble
            trailingSpacer
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var leadingSpacer: some View {
        if isUser {
            Spacer(minLength: 72)
        }
    }

    private var bubble: some View {
        AnvilSurface(
            fill: isUser ? .selection : .elevated,
            border: isUser ? .accent : .separator
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                bubbleHeader
                messageText
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(senderName): \(message.text)")
    }

    private var bubbleHeader: some View {
        HStack(spacing: theme.spacing.small) {
            Image(systemName: isUser ? "person.crop.circle.fill" : "hammer.circle.fill")
                .foregroundStyle(isUser ? theme.colors.accent : theme.colors.textSecondary)
                .accessibilityHidden(true)
            Text(senderName)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textSecondary)
            streamingStatus
        }
    }

    private var messageText: some View {
        Text(message.text + (message.isStreaming ? " ▌" : ""))
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var streamingStatus: some View {
        if message.isStreaming {
            AnvilStatusText("Streaming", tone: .warning)
        }
    }

    @ViewBuilder
    private var trailingSpacer: some View {
        if !isUser {
            Spacer(minLength: 72)
        }
    }

    private var senderName: String {
        isUser ? "You" : "Assistant"
    }

}
