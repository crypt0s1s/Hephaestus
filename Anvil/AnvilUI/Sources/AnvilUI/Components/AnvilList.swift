import AnvilTheme
import SwiftUI

public enum AnvilListStyle: Sendable {
    case plain
    case panel
    case elevated
}

public struct AnvilListConfiguration: Sendable {
    public var style: AnvilListStyle
    public var spacing: CGFloat
    public var contentPadding: CGFloat
    public var accessibilityIdentifier: String?

    public init(
        style: AnvilListStyle = .panel,
        spacing: CGFloat = 0,
        contentPadding: CGFloat = 0,
        accessibilityIdentifier: String? = nil
    ) {
        self.style = style
        self.spacing = spacing
        self.contentPadding = contentPadding
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct AnvilList<Content: View, EmptyState: View>: View {
    private let configuration: AnvilListConfiguration
    private let isEmpty: Bool
    private let content: Content
    private let emptyState: EmptyState

    @Environment(\.anvilTheme) private var theme

    public init(
        configuration: AnvilListConfiguration = AnvilListConfiguration(),
        isEmpty: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder emptyState: () -> EmptyState
    ) {
        self.configuration = configuration
        self.isEmpty = isEmpty
        self.content = content()
        self.emptyState = emptyState()
    }

    public var body: some View {
        VStack(spacing: configuration.spacing) {
            if isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(configuration.contentPadding)
        .modifier(AnvilListSurface(style: configuration.style))
        .modifier(AnvilAccessibilityIdentifier(identifier: configuration.accessibilityIdentifier))
    }
}

public extension AnvilList where EmptyState == EmptyView {
    init(
        configuration: AnvilListConfiguration = AnvilListConfiguration(),
        isEmpty: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            configuration: configuration,
            isEmpty: isEmpty,
            content: content,
            emptyState: { EmptyView() }
        )
    }
}

private struct AnvilListSurface: ViewModifier {
    let style: AnvilListStyle
    @Environment(\.anvilTheme) private var theme

    func body(content: Content) -> some View {
        switch style {
        case .plain:
            content
        case .panel, .elevated:
            content
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                        .stroke(theme.colors.border, lineWidth: 1)
                }
        }
    }

    private var background: Color {
        switch style {
        case .plain:
            Color.clear
        case .panel:
            theme.colors.panelBackground
        case .elevated:
            theme.colors.elevatedPanelBackground
        }
    }
}
