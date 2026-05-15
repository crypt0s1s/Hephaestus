import AnvilTheme
import SwiftUI

public enum AnvilActionButtonStyle: Sendable {
    case primary
    case secondary
    case plain
}

public enum AnvilActionButtonLabelStyle: Sendable {
    case titleAndIcon
    case iconOnly
}

public struct AnvilActionButtonConfiguration: Sendable {
    public var title: String
    public var systemImage: String?
    public var style: AnvilActionButtonStyle
    public var labelStyle: AnvilActionButtonLabelStyle
    public var isDisabled: Bool
    public var accessibilityLabel: String?
    public var accessibilityIdentifier: String?
    public var help: String?

    public init(
        title: String,
        systemImage: String? = nil,
        style: AnvilActionButtonStyle = .secondary,
        labelStyle: AnvilActionButtonLabelStyle = .titleAndIcon,
        isDisabled: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil,
        help: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.labelStyle = labelStyle
        self.isDisabled = isDisabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.help = help
    }
}

public struct AnvilActionButton: View {
    private let configuration: AnvilActionButtonConfiguration
    private let action: () -> Void

    @Environment(\.anvilTheme) private var theme

    public init(
        configuration: AnvilActionButtonConfiguration,
        action: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.action = action
    }

    public var body: some View {
        styledButton
            .disabled(configuration.isDisabled)
            .accessibilityLabel(configuration.accessibilityLabel ?? configuration.title)
            .modifier(AnvilAccessibilityIdentifier(identifier: configuration.accessibilityIdentifier))
            .help(configuration.help ?? configuration.accessibilityLabel ?? configuration.title)
    }

    @ViewBuilder
    private var styledButton: some View {
        switch configuration.style {
        case .primary:
            baseButton
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
        case .secondary:
            baseButton
                .buttonStyle(.bordered)
        case .plain:
            baseButton
                .buttonStyle(.plain)
        }
    }

    private var baseButton: some View {
        Button(action: action) {
            if let systemImage = configuration.systemImage {
                switch configuration.labelStyle {
                case .titleAndIcon:
                    Label(configuration.title, systemImage: systemImage)
                case .iconOnly:
                    Label(configuration.title, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                }
            } else {
                Text(configuration.title)
            }
        }
    }
}
