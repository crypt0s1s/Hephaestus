import Foundation

struct InteractiveStepMessage: Identifiable, Equatable {
  enum Kind: String, Equatable {
    case submittedArtifact
  }

  let id: String
  let kind: Kind
  let producerStepID: String
  let createdAt: Date
  let payload: InteractiveStepMessagePayload
  let summary: String?

  init(
    id: String = UUID().uuidString,
    kind: Kind,
    producerStepID: String,
    createdAt: Date = Date(),
    payload: InteractiveStepMessagePayload,
    summary: String?
  ) {
    self.id = id
    self.kind = kind
    self.producerStepID = producerStepID
    self.createdAt = createdAt
    self.payload = payload
    self.summary = summary
  }
}

enum InteractiveStepMessagePayload: Equatable {
  case artifact(InteractiveStepArtifact)
}

struct InteractiveStepArtifact: Equatable {
  var contentType: String
  var content: String
}
