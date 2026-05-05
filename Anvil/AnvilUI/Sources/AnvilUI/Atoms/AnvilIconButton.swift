import AnvilTheme
import SwiftUI

/// Experimental: icon-only button primitive for compact macOS workbench controls.
public struct AnvilIconButton: View {
    private let systemName: String
    private let accessibilityLabel: String
    private let help: String?
    private let size: CGFloat
    private let action: () -> Void

    @Environment(\.anvilTheme) private var theme

    public init(
        systemName: String,
        accessibilityLabel: String,
        help: String? = nil,
        size: CGFloat = 30,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .help(help ?? accessibilityLabel)
    }
}
