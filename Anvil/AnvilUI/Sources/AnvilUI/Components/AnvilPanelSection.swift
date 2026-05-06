import AnvilTheme
import SwiftUI

/// Experimental: titled vertical content group for inspector and settings panels.
public struct AnvilPanelSection<Content: View>: View {
    private let title: String
    private let content: Content

    @Environment(\.anvilTheme) private var theme

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            Text(title)
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
