import AnvilTheme
import AnvilUI
import SwiftUI

struct StartupErrorView: View {
    let error: Error
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
            HStack(spacing: theme.spacing.cozy) {
                AnvilIconTile(systemName: "exclamationmark.triangle.fill", tone: .danger)

                Text("Hephaestus could not start")
                    .font(theme.typography.rowTitle)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            AnvilBanner(
                message: String(describing: error),
                tone: .danger,
                systemImage: "xmark.octagon.fill"
            )
        }
        .padding(theme.spacing.roomy)
        .frame(minWidth: 520, minHeight: 320)
        .background(theme.colors.windowBackground)
    }
}

struct RouteErrorView: View {
    let error: Error
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
            AnvilPanelSection(title: "Screen could not be opened") {
                AnvilSurface(tone: .danger) {
                    Text(String(describing: error))
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(theme.spacing.roomy)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.windowBackground)
    }
}
