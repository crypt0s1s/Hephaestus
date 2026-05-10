import Foundation

struct WorkflowInteractionState: Equatable {
  var workflowID: WorkflowDefinition.ID
  var stepID: String
  var sessionID: String
  var title: String
  var subtitle: String
  var inputPlaceholder: String
  var draftTitle: String
  var draft = ""
  var note = ""
  var entries: [WorkflowInteractionEntry]
  var submittedMessage: InteractiveStepMessage?
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
    !trimmedNote.isEmpty && submittedMessage == nil
  }

  var canSubmit: Bool {
    !trimmedDraft.isEmpty && submittedMessage == nil
  }
}

struct WorkflowInteractionEntry: Identifiable, Equatable {
  enum Source: Equatable {
    case system
    case user
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
