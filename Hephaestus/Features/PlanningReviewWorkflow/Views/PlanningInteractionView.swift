import AnvilTheme
import AnvilUI
import SwiftUI

struct PlanningInteractionView: View {
    enum PresentationStyle {
        case inline
        case editorPrimary
    }

    let state: PlanningInteractionState
    let presentationStyle: PresentationStyle
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    init(
        state: PlanningInteractionState,
        presentationStyle: PresentationStyle = .editorPrimary,
        action: @escaping (PlanningInteractionActionProcessor.Action) -> Void
    ) {
        self.state = state
        self.presentationStyle = presentationStyle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            PlanningInteractionHeader(state: state, action: action)
            PlanningInteractionContent(state: state, presentationStyle: presentationStyle, action: action)
            if let reviewHandoffSummary = state.reviewHandoffSummary {
                PlanningInteractionReviewSummary(summary: reviewHandoffSummary, action: action)
            }
            PlanningInteractionDecisionBar(state: state, action: action)
        }
        .padding(theme.spacing.comfortable)
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }
}

private struct PlanningInteractionHeader: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.cozy) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 30, height: 30)
                .background(theme.colors.selectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))

            VStack(alignment: .leading, spacing: theme.spacing.tiny) {
                Text(state.title)
                    .font(theme.typography.rowTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityIdentifier("planning.interaction")
                Text(statusText)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()

            busyIndicator

            VStack(alignment: .trailing, spacing: theme.spacing.tiny) {
                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: submitButtonTitle,
                        systemImage: submitButtonSystemImage,
                        style: .primary,
                        isDisabled: !state.canAttemptSubmit,
                        accessibilityIdentifier: "planning.submitPlan"
                    ),
                    action: { action(.tapAcceptDraftForReview) }
                )

                if state.submittedOutput == nil && !state.isBusy {
                    Text("Starts automated review.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var busyIndicator: some View {
        if state.isBusy {
            AnvilStatusIndicator(state: .running)
                .accessibilityIdentifier("planning.busyIndicator")
        }
    }

    private var statusText: String {
        switch state.phase {
        case .sending:
            return "Planner is responding."
        case .materializing:
            return "Accepting and validating the plan artifact."
        case .reviewing:
            return "Automated review cycles are running."
        case .completed:
            return "Automated review cycles finished. Review the plan before accepting it."
        case .accepted:
            return "Planning review workflow accepted."
        case .idle:
            break
        }
        if let submittedOutput = state.submittedOutput {
            return "Submitted plan artifact \(submittedOutput.id)."
        }
        switch state.gateState {
        case .awaitingUserReview:
            return "Review the draft plan, then accept it for automated review."
        case .needsOutput(let issue):
            return issue.message
        case .interacting, .accepted:
            break
        }
        return state.subtitle
    }

    private var submitButtonTitle: String {
        if state.isBusy {
            return "Working"
        }
        return state.submittedOutput == nil ? "Accept draft for review" : "Accepted"
    }

    private var submitButtonSystemImage: String {
        if state.isBusy {
            return "hourglass"
        }
        return state.submittedOutput == nil ? "checkmark.circle.fill" : "checkmark.circle.fill"
    }
}

private struct PlanningInteractionDecisionBar: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if state.canResolveCompletedOutput {
            HStack(spacing: theme.spacing.compact) {
                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: "Accept reviewed workflow",
                        systemImage: "checkmark.circle.fill",
                        style: .primary,
                        accessibilityIdentifier: "planning.acceptPlan"
                    ),
                    action: { action(.tapAcceptReviewedWorkflow) }
                )

                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: "Run another cycle",
                        systemImage: "arrow.triangle.2.circlepath",
                        accessibilityIdentifier: "planning.anotherCycle"
                    ),
                    action: { action(.tapRequestAnotherCycle) }
                )

                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: "Continue Planning",
                        systemImage: "square.and.pencil",
                        accessibilityIdentifier: "planning.continuePlanning"
                    ),
                    action: { action(.tapContinuePlanning) }
                )

                Spacer()
            }
            .padding(.top, theme.spacing.compact)
        }
    }
}
