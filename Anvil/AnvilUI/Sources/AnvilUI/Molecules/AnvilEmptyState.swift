import AnvilTheme
import SwiftUI

/// Experimental: centered empty state with icon, title, and optional message.
public struct AnvilEmptyState: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let maxMessageWidth: CGFloat

    @Environment(\.anvilTheme) private var theme

    public init(
        title: String,
        message: String? = nil,
        systemImage: String,
        maxMessageWidth: CGFloat = 420
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.maxMessageWidth = maxMessageWidth
    }

    public var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: theme.spacing.xSmall) {
                Text(title)
                    .font(theme.typography.rowTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                messageText
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var messageText: some View {
        if let message {
            Text(message)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxMessageWidth)
        }
    }
}
