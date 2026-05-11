import Foundation

struct InteractiveStepOutput: Identifiable, Equatable {
  let id: String
  let producerStepID: String
  let createdAt: Date
  let artifact: InteractiveStepArtifact
  let summary: String?

  init(
    id: String = UUID().uuidString,
    producerStepID: String,
    createdAt: Date = Date(),
    artifact: InteractiveStepArtifact,
    summary: String?
  ) {
    self.id = id
    self.producerStepID = producerStepID
    self.createdAt = createdAt
    self.artifact = artifact
    self.summary = summary
  }
}

struct InteractiveStepArtifact: Equatable {
  var title: String
  var contentType: String
  var content: String
  var projectRelativePath: String?

  init(
    title: String,
    contentType: String,
    content: String,
    projectRelativePath: String? = nil
  ) {
    self.title = title
    self.contentType = contentType
    self.content = content
    self.projectRelativePath = projectRelativePath
  }
}
