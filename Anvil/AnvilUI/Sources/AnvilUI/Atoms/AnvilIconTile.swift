import AnvilTheme
import SwiftUI

/// Experimental: compact rounded icon tile for headers and empty states.
public struct AnvilIconTile: View {
    private let systemName: String
    private let size: CGFloat
    private let iconSize: CGFloat
    private let tone: AnvilStatusTone

    @Environment(\.anvilTheme) private var theme

    public init(
        systemName: String,
        size: CGFloat = 34,
        iconSize: CGFloat = 18,
        tone: AnvilStatusTone = .neutral
    ) {
        self.systemName = systemName
        self.size = size
        self.iconSize = iconSize
        self.tone = tone
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            theme.colors.accentForeground
        case .success, .warning, .danger:
            toneColor
        }
    }

    private var background: Color {
        switch tone {
        case .neutral:
            theme.colors.accent
        case .success, .warning, .danger:
            toneColor.opacity(0.14)
        }
    }

    private var toneColor: Color {
        switch tone {
        case .neutral:
            theme.colors.accent
        case .success:
            theme.colors.success
        case .warning:
            theme.colors.warning
        case .danger:
            theme.colors.danger
        }
    }
}
