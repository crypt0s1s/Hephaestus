import AnvilTheme
import SwiftUI

public struct AnvilTextFieldConfiguration: Equatable {
    public var placeholder: String
    public var axis: Axis
    public var lineLimit: ClosedRange<Int>?
    public var accessibilityLabel: String?
    public var accessibilityIdentifier: String?

    public init(
        placeholder: String,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.placeholder = placeholder
        self.axis = axis
        self.lineLimit = lineLimit
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct AnvilTextField: View {
    @Binding private var text: String
    private let configuration: AnvilTextFieldConfiguration

    public init(
        text: Binding<String>,
        configuration: AnvilTextFieldConfiguration
    ) {
        self._text = text
        self.configuration = configuration
    }

    public init(
        _ placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            text: text,
            configuration: AnvilTextFieldConfiguration(
                placeholder: placeholder,
                axis: axis,
                lineLimit: lineLimit,
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }

    public var body: some View {
        field
            .accessibilityLabel(configuration.accessibilityLabel ?? configuration.placeholder)
            .modifier(AnvilAccessibilityIdentifier(identifier: configuration.accessibilityIdentifier))
    }

    @ViewBuilder
    private var field: some View {
        if let lineLimit = configuration.lineLimit {
            baseField.lineLimit(lineLimit)
        } else {
            baseField
        }
    }

    private var baseField: some View {
        TextField(configuration.placeholder, text: $text, axis: configuration.axis)
            .textFieldStyle(AnvilTextFieldStyle())
    }
}

/// Standard bordered text field treatment for compact workbench inputs.
public struct AnvilTextFieldStyle: TextFieldStyle {
    @Environment(\.anvilTheme) private var theme

    public init() {}

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(theme.colors.textPrimary)
            .font(theme.typography.body)
            .padding(.horizontal, theme.spacing.cozy)
            .padding(.vertical, theme.spacing.compact)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
    }
}
