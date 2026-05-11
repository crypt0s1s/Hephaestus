import AnvilTheme
import AnvilUI
import SwiftUI

struct ChatEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        AnvilEmptyState(
            title: title,
            message: message,
            systemImage: "sparkles"
        )
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.emptyState)
    }
}

struct RunningStatus: View {
    let text: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.compact) {
            ProgressView()
                .controlSize(.small)
            AnvilStatusText(text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.compact)
        .padding(.vertical, theme.spacing.squishy)
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
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            bubbleHeader
            messageText
        }
        .padding(.horizontal, theme.spacing.comfortable)
        .padding(.vertical, theme.spacing.cozy)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: isUser ? 18 : 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isUser ? 18 : 10, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        }
        .frame(maxWidth: isUser ? 520 : 680, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(senderName): \(message.text)")
    }

    private var bubbleHeader: some View {
        HStack(spacing: theme.spacing.compact) {
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

    private var bubbleBackground: Color {
        isUser ? theme.colors.elevatedPanelBackground : theme.colors.panelBackground
    }

    private var bubbleBorder: Color {
        isUser ? theme.colors.separator : theme.colors.border
    }

}
