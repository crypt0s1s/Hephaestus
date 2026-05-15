import AnvilTheme
import SwiftUI

public struct AnvilFieldSection<Content: View>: View {
    private let title: String
    private let help: String?
    private let error: String?
    private let errorAccessibilityIdentifier: String?
    private let content: Content

    @Environment(\.anvilTheme) private var theme

    public init(
        title: String,
        help: String? = nil,
        error: String? = nil,
        errorAccessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.help = help
        self.error = error
        self.errorAccessibilityIdentifier = errorAccessibilityIdentifier
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            content

            if let error {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .modifier(AnvilAccessibilityIdentifier(identifier: errorAccessibilityIdentifier))
            } else if let help {
                Text(help)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }
}
