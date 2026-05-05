import AnvilTheme
import SwiftUI

struct StartupErrorView: View {
    let error: Error
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            Text("Hephaestus could not start")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            Text(String(describing: error))
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.xLarge)
        .frame(minWidth: 520, minHeight: 320)
        .background(theme.colors.windowBackground)
    }
}

struct RouteErrorView: View {
    let error: Error
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            Text("Screen could not be opened")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            Text(String(describing: error))
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.windowBackground)
    }
}
