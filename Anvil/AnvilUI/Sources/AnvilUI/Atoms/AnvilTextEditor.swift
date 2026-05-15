import AnvilTheme
import SwiftUI

public struct AnvilTextEditorConfiguration: Equatable {
    public var placeholder: String?
    public var accessibilityLabel: String
    public var accessibilityIdentifier: String?

    public init(
        placeholder: String? = nil,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil
    ) {
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct AnvilTextEditor: View {
    @Binding private var text: String
    private let configuration: AnvilTextEditorConfiguration

    @Environment(\.anvilTheme) private var theme

    public init(
        text: Binding<String>,
        configuration: AnvilTextEditorConfiguration
    ) {
        self._text = text
        self.configuration = configuration
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty, let placeholder = configuration.placeholder {
                Text(placeholder)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(theme.spacing.compact)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(theme.spacing.compact)
                .accessibilityLabel(configuration.accessibilityLabel)
                .modifier(AnvilAccessibilityIdentifier(identifier: configuration.accessibilityIdentifier))
        }
        .background(theme.colors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }
}
