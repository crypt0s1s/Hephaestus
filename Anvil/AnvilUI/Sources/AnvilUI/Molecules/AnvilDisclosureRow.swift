import AnvilTheme
import SwiftUI

/// Experimental: generic disclosure row for expandable workbench content.
public struct AnvilDisclosureRow<Accessory: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let isExpanded: Bool
    private let onToggle: () -> Void
    private let accessory: Accessory
    private let content: Content

    @Environment(\.anvilTheme) private var theme

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            rowHeader
            expandedContent
        }
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: theme.spacing.cozy) {
            toggleButton
            accessory
        }
    }

    private var toggleButton: some View {
        Button(action: toggleExpansion) {
            HStack(alignment: .center, spacing: theme.spacing.cozy) {
                disclosureIcon
                leadingIcon
                titleBlock
                Spacer(minLength: theme.spacing.compact)
            }
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }

    private var disclosureIcon: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(theme.colors.accentForeground)
                .frame(width: 42, height: 42)
                .background(theme.colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text(title)
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isExpanded {
            content
                .padding(.leading, systemImage == nil ? 36 : 46)
                .clipped()
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: theme.motion.standard)) {
            onToggle()
        }
    }
}

extension AnvilDisclosureRow where Accessory == EmptyView {
    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            isExpanded: isExpanded,
            onToggle: onToggle,
            accessory: { EmptyView() },
            content: content
        )
    }
}
