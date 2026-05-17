import AnvilTheme
import AnvilUI
import SwiftUI

struct PlanningInteractionReviewSummary: View {
    let summary: PlanningReviewHandoffSummary
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        AnvilList(
            configuration: AnvilListConfiguration(
                style: .panel,
                spacing: theme.spacing.cozy,
                contentPadding: theme.spacing.cozy,
                accessibilityIdentifier: "planning.reviewSummary"
            )
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                PlanningInteractionReviewSummaryHeader(
                    title: summary.title,
                    subtitle: summary.subtitle
                )

                PlanningInteractionReviewArtifactIndex(markers: summary.markers)

                if let latestArtifact = summary.latestArtifact {
                    PlanningInteractionArtifactRow(artifact: latestArtifact, action: action)
                }

                PlanningInteractionReviewCycleList(cycles: summary.cycles, action: action)
            }
        }
    }
}

private struct PlanningInteractionReviewSummaryHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Text(subtitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

private struct PlanningInteractionReviewCycleList: View {
    let cycles: [PlanningReviewHandoffCycle]
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if !cycles.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.compact) {
                Text("Cycle history")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)

                ForEach(cycles) { cycle in
                    PlanningInteractionReviewCycleSection(cycle: cycle, action: action)
                }
            }
        }
    }
}

private struct PlanningInteractionReviewArtifactIndex: View {
    let markers: [PlanningReviewHandoffMarker]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if !markers.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.tiny) {
                Text("Available artifacts")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)

                ForEach(markers) { marker in
                    Text(marker.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityIdentifier(marker.identifier)
                }
            }
        }
    }

}

private struct PlanningInteractionReviewCycleSection: View {
    let cycle: PlanningReviewHandoffCycle
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            Text("Cycle \(cycle.number)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            if let feedback = cycle.feedback {
                PlanningInteractionArtifactRow(artifact: feedback, action: action)
            }

            if let plan = cycle.plan {
                PlanningInteractionArtifactRow(artifact: plan, action: action)
            }
        }
        .padding(.leading, theme.spacing.compact)
    }
}

private struct PlanningInteractionArtifactRow: View {
    let artifact: PlanningReviewHandoffArtifact
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            HStack(spacing: theme.spacing.compact) {
                Text(artifact.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityIdentifier(artifact.accessibilityIdentifier)

                Text(artifact.badge)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, theme.spacing.compact)
                    .padding(.vertical, 2)
                    .background(theme.colors.selectionBackground)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))

                Spacer()

                if let path = artifact.copyPath {
                    AnvilActionButton(
                        configuration: AnvilActionButtonConfiguration(
                            title: "Copy path",
                            systemImage: "doc.on.doc",
                            style: .plain,
                            labelStyle: .iconOnly,
                            accessibilityLabel: "Copy \(artifact.title) path",
                            accessibilityIdentifier: "\(artifact.accessibilityIdentifier).copyPath",
                            help: "Copy artifact path"
                        ),
                        action: { action(.tapCopyArtifactPath(path)) }
                    )
                }
            }

            if let summary = artifact.output.summary {
                Text(summary)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Text(artifact.pathText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.compact)
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }
}
