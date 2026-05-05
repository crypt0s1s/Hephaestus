import AnvilTheme
import SwiftUI

/// Experimental: bordered monospaced output surface for logs and command output.
public struct AnvilLogSurface: View {
    private let text: String
    private let minHeight: CGFloat

    @Environment(\.anvilTheme) private var theme

    public init(_ text: String, minHeight: CGFloat = 160) {
        self.text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        ScrollView {
            Text(text)
                .font(theme.typography.code)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(theme.spacing.medium)
        }
        .frame(minHeight: minHeight)
        .background(theme.colors.logBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }
}
