import AnvilTheme
import SwiftUI

/// Experimental: ordered row with a small numbered badge.
public struct AnvilNumberedRow: View {
    private let number: Int
    private let title: String
    private let subtitle: String?

    @Environment(\.anvilTheme) private var theme

    public init(number: Int, title: String, subtitle: String? = nil) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.cozy) {
            Text("\(number)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: badgeSize, height: badgeSize)
                .background(theme.colors.selectionBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: theme.spacing.squishy) {
                Text(title)
                    .font(theme.typography.body.weight(.medium))
                    .foregroundStyle(theme.colors.textPrimary)
                subtitleText
            }

            Spacer()
        }
        .padding(.vertical, theme.spacing.tiny)
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle {
            Text(subtitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var badgeSize: CGFloat { 20 }
}
