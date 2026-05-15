import AnvilTheme
import SwiftUI

struct WorkflowActivityPill: View {
    let title: String
    let systemImage: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.compact)
            .padding(.vertical, theme.spacing.tiny)
            .background(theme.colors.selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
            .accessibilityLabel(title)
    }
}
