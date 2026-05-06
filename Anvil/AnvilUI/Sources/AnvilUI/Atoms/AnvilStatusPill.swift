import AnvilTheme
import SwiftUI

/// Experimental: compact status indicator with a tone dot and label.
public struct AnvilStatusPill: View {
    private let text: String
    private let tone: AnvilStatusTone

    @Environment(\.anvilTheme) private var theme

    public init(_ text: String, tone: AnvilStatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: theme.spacing.compact) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            AnvilStatusText(text, tone: tone == .neutral ? .neutral : tone)
        }
        .padding(.horizontal, theme.spacing.cozy)
        .padding(.vertical, theme.spacing.compact)
        .background(theme.colors.border)
        .clipShape(Capsule())
    }

    private var color: Color {
        switch tone {
        case .neutral:
            theme.colors.textTertiary
        case .success:
            theme.colors.success
        case .warning:
            theme.colors.warning
        case .danger:
            theme.colors.danger
        }
    }
}
