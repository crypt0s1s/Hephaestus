import AnvilTheme
import SwiftUI

struct WorkflowInteractiveActivityHost: View {
    @ObservedObject var model: WorkflowRunnerModel
    let activity: WorkflowInteractiveActivity

    var body: some View {
        if activity.rendererID == PlanningInteractionActivityProjection.rendererID {
            PlanningInteractiveActivityRenderer(model: model, activity: activity)
        }
    }
}

private struct PlanningInteractiveActivityRenderer: View {
    @ObservedObject var model: WorkflowRunnerModel
    let activity: WorkflowInteractiveActivity
    @State private var presentationStyle: PlanningPresentationStyle = .editorPrimary
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if let state = model.planningInteractionState(sessionID: activity.sessionID) {
            VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                layoutPicker
                PlanningInteractionView(
                    state: state,
                    presentationStyle: presentationStyle.interactionStyle,
                    action: PlanningInteractionActionProcessor(model: model).handle
                )
            }
        }
    }

    private var layoutPicker: some View {
        Picker("Planning layout", selection: $presentationStyle) {
            ForEach(PlanningPresentationStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 340)
        .accessibilityIdentifier("planning.layoutPicker")
    }
}

private enum PlanningPresentationStyle: String, CaseIterable, Identifiable {
    case editorPrimary
    case inline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editorPrimary:
            return "Editor"
        case .inline:
            return "Split"
        }
    }

    var interactionStyle: PlanningInteractionView.PresentationStyle {
        switch self {
        case .editorPrimary:
            return .editorPrimary
        case .inline:
            return .inline
        }
    }
}
