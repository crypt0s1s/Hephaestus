import Foundation

struct WorkflowInteractionState: Equatable {
    enum Phase: Equatable {
        case idle
        case sending
        case materializing
        case reviewing
        case completed
        case accepted
    }

    enum DraftProvenance: Equatable {
        case empty
        case agentGenerated
        case userEdited
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
    var draftProvenance: DraftProvenance = .empty
    var draft = ""
    var note = ""
    var entries: [WorkflowInteractionEntry]
    var submittedOutput: InteractiveStepOutput?
    var errorMessage: String?

    init(
        workflowID: WorkflowDefinition.ID,
        stepID: String,
        sessionID: String = UUID().uuidString,
        title: String,
        subtitle: String,
        inputPlaceholder: String,
        draftTitle: String,
        initialEntries: [WorkflowInteractionEntry] = []
    ) {
        self.workflowID = workflowID
        self.stepID = stepID
        self.sessionID = sessionID
        self.title = title
        self.subtitle = subtitle
        self.inputPlaceholder = inputPlaceholder
        self.draftTitle = draftTitle
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
        !trimmedDraft.isEmpty && submittedOutput == nil && phase == .idle && draftProvenance == .userEdited
    }

    var canResolveCompletedOutput: Bool {
        submittedOutput != nil && phase == .completed
    }

    var draftRequiresUserEdit: Bool {
        !trimmedDraft.isEmpty && submittedOutput == nil && phase == .idle && draftProvenance == .agentGenerated
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

struct WorkflowInteractionEntry: Identifiable, Equatable {
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
