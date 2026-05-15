import AnvilTheme
import SwiftUI

struct PlanningInteractionRecoveryActions: View {
    let issue: InteractiveRequiredOutputIssue
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.compact) {
            ForEach(issue.recoveryActions, id: \.self) { recoveryAction in
                Button(recoveryAction.title) {
                    action(.chooseRecovery(recoveryAction))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(recoveryAction.accessibilityIdentifier)
            }
        }
        .accessibilityIdentifier("planning.recoveryActions")
    }
}

private extension InteractiveStepRecoveryAction {
    var title: String {
        switch self {
        case .requestAgentRevision:
            return "Prepare fix request"
        case .editOutput:
            return "Edit draft"
        case .pasteOutput:
            return "Paste draft"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .requestAgentRevision:
            return "planning.recovery.requestAgentRevision"
        case .editOutput:
            return "planning.recovery.editOutput"
        case .pasteOutput:
            return "planning.recovery.pasteOutput"
        }
    }
}
