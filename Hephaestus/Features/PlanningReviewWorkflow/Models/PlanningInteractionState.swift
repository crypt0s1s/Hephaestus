import Foundation

struct PlanningInteractionState: Equatable {
    enum Phase: Equatable {
        case idle
        case sending
        case materializing
        case reviewing
        case completed
        case accepted
    }

    var workflowID: WorkflowDefinition.ID
    var stepID: String
    var sessionID: String
    var backendSession: BackendSession?
    var title: String
    var subtitle: String
    var inputPlaceholder: String
    var draftTitle: String
    var phase: Phase = .idle
    var outputCandidate: InteractiveStepOutputCandidate
    var gateState: InteractiveStepGateState = .interacting
    var draft = ""
    var note = ""
    var entries: [PlanningInteractionEntry]
    var submittedOutput: InteractiveStepOutput?
    var relatedOutputs: [InteractiveStepOutput] = []
    var latestResolvedOutput: InteractiveStepOutput?
    var errorMessage: String?

    init(
        workflowID: WorkflowDefinition.ID,
        stepID: String,
        sessionID: String = UUID().uuidString,
        title: String,
        subtitle: String,
        inputPlaceholder: String,
        draftTitle: String,
        outputCandidate: InteractiveStepOutputCandidate,
        initialEntries: [PlanningInteractionEntry] = []
    ) {
        self.workflowID = workflowID
        self.stepID = stepID
        self.sessionID = sessionID
        self.title = title
        self.subtitle = subtitle
        self.inputPlaceholder = inputPlaceholder
        self.draftTitle = draftTitle
        self.outputCandidate = outputCandidate
        self.entries = initialEntries
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canAddNote: Bool {
        !trimmedNote.isEmpty && submittedOutput == nil && phase == .idle
    }

    var canSubmit: Bool {
        submittedOutput == nil && phase == .idle && gateState.canAcceptOutputForReview
    }

    var canAttemptSubmit: Bool {
        submittedOutput == nil && phase == .idle
    }

    var canResolveCompletedOutput: Bool {
        submittedOutput != nil && phase == .completed
    }

    var isBusy: Bool {
        switch phase {
        case .sending, .materializing, .reviewing:
            return true
        case .idle, .completed, .accepted:
            return false
        }
    }
}

struct PlanningInteractionEntry: Identifiable, Equatable {
    enum Source: Equatable {
        case system
        case user
        case assistant
    }

    let id: String
    var source: Source
    var text: String

    init(id: String = UUID().uuidString, source: Source, text: String) {
        self.id = id
        self.source = source
        self.text = text
    }
}
