import AnvilTheme
import SwiftUI

/// Experimental: inline feedback banner for short user-facing messages.
public struct AnvilBanner: View {
    private let message: String
    private let tone: AnvilStatusTone
    private let systemImage: String?

    @Environment(\.anvilTheme) private var theme

    public init(
        message: String,
        tone: AnvilStatusTone = .neutral,
        systemImage: String? = nil
    ) {
        self.message = message
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.medium) {
            icon
            Text(message)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.medium)
        .padding(.vertical, theme.spacing.small)
        .background(color.opacity(tone == .neutral ? 0.08 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .stroke(color.opacity(tone == .neutral ? 0.14 : 0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
    }

    private var color: Color {
        switch tone {
        case .neutral:
            theme.colors.border
        case .success:
            theme.colors.success
        case .warning:
            theme.colors.warning
        case .danger:
            theme.colors.danger
        }
    }
}
