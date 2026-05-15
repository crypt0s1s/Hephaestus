import AnvilTheme
import SwiftUI

struct PlanningInteractionReviewSummary: View {
    let state: PlanningInteractionState
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if shouldShowSummary {
            VStack(alignment: .leading, spacing: theme.spacing.compact) {
                Text(summaryTitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                if let latestOutput = state.latestResolvedOutput {
                    PlanningInteractionArtifactRow(
                        title: "Latest reviewed plan",
                        output: latestOutput,
                        identifier: "planning.latestReviewedPlan"
                    )
                }

                ForEach(relatedOutputs) { output in
                    PlanningInteractionArtifactRow(
                        title: output.artifact.title,
                        output: output,
                        identifier: "planning.reviewArtifact.\(output.id)"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.cozy)
            .background(theme.colors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
        }
    }

    private var shouldShowSummary: Bool {
        (state.canResolveCompletedOutput || state.phase == .accepted)
            && (state.latestResolvedOutput != nil || !relatedOutputs.isEmpty)
    }

    private var summaryTitle: String {
        state.phase == .accepted ? "Accepted handoff" : "Review handoff"
    }

    private var relatedOutputs: [InteractiveStepOutput] {
        state.relatedOutputs.filter { $0.id != state.latestResolvedOutput?.id }
    }
}

private struct PlanningInteractionArtifactRow: View {
    let title: String
    let output: InteractiveStepOutput
    let identifier: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Text(pathText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier(identifier)
    }

    private var pathText: String {
        output.artifact.projectRelativePath ?? output.summary ?? output.artifact.title
    }
}
