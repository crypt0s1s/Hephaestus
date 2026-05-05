import AnvilTheme
import SwiftUI

public enum AnvilSurfaceFill: Sendable {
    case elevated
    case panel
    case selection
    case tone(AnvilStatusTone)
}

public enum AnvilSurfaceBorder: Sendable {
    case none
    case separator
    case accent
    case tone(AnvilStatusTone)
}

/// Experimental: rounded elevated surface for reusable rows, cards, and compact panels.
public struct AnvilSurface<Content: View>: View {
    private let fill: AnvilSurfaceFill
    private let border: AnvilSurfaceBorder
    private let content: Content

    @Environment(\.anvilTheme) private var theme

    public init(
        fill: AnvilSurfaceFill = .elevated,
        border: AnvilSurfaceBorder = .none,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.border = border
        self.content = content()
    }

    public init(tone: AnvilStatusTone, @ViewBuilder content: () -> Content) {
        self.init(fill: .tone(tone), content: content)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.medium)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                if let borderColor {
                    RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
    }

    private var background: Color {
        switch fill {
        case .elevated:
            theme.colors.elevatedPanelBackground
        case .panel:
            theme.colors.panelBackground
        case .selection:
            theme.colors.selectionBackground
        case .tone(let tone):
            switch tone {
            case .neutral:
                theme.colors.elevatedPanelBackground
            case .success:
                theme.colors.success.opacity(0.10)
            case .warning:
                theme.colors.warning.opacity(0.10)
            case .danger:
                theme.colors.danger.opacity(0.10)
            }
        }
    }

    private var borderColor: Color? {
        switch border {
        case .none:
            nil
        case .separator:
            theme.colors.separator
        case .accent:
            theme.colors.accent.opacity(0.18)
        case .tone(let tone):
            switch tone {
            case .neutral:
                theme.colors.border
            case .success:
                theme.colors.success.opacity(0.22)
            case .warning:
                theme.colors.warning.opacity(0.22)
            case .danger:
                theme.colors.danger.opacity(0.22)
            }
        }
    }
}
