import AnvilTheme
import SwiftUI

/// Experimental: selectable sidebar row shell for product-neutral navigation lists.
public struct AnvilSidebarRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void
    private let trailing: Trailing

    @Environment(\.anvilTheme) private var theme

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.medium) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
                    Text(title)
                        .font(theme.typography.sectionTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(theme.typography.body)
                            .foregroundStyle(subtitle.isEmpty ? theme.colors.textTertiary : theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: theme.spacing.small)
                trailing
            }
            .padding(.horizontal, theme.spacing.medium)
            .padding(.vertical, theme.spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.colors.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public extension AnvilSidebarRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            isSelected: isSelected,
            action: action,
            trailing: { EmptyView() }
        )
    }
}
