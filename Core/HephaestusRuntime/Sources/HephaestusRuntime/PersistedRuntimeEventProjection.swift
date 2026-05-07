import Foundation
import HephaestusKernel

extension PersistedRuntimeEvent {
  public init(_ event: RuntimeEvent) {
    switch event {
    case .runCreated(let header, let runID):
      self.init(header: header, kind: .runCreated, summary: "Run created", messageID: runID)
    case .userMessageAccepted(let header, let messageID, let text):
      self.init(
        header: header, kind: .userMessageAccepted, summary: "User message accepted: \(text)",
        messageID: messageID)
    case .contextPrepared(let header, let includedMessageCount):
      self.init(
        header: header, kind: .contextPrepared,
        summary: "Context prepared with \(includedMessageCount) messages")
    case .providerRequestPrepared(let header, let requestID, let model, let messageCount):
      self.init(
        header: header,
        kind: .providerRequestPrepared,
        summary: "Provider request prepared for \(model) with \(messageCount) messages",
        providerRequestID: requestID
      )
    case .assistantTextDelta(let header, let text):
      self.init(header: header, kind: .assistantTextDelta, summary: "Assistant delta: \(text)")
    case .assistantMessageCompleted(let header, let messageID, let text):
      self.init(
        header: header, kind: .assistantMessageCompleted,
        summary: "Assistant message completed: \(text)", messageID: messageID)
    case .turnCancelled(let header):
      self.init(header: header, kind: .turnCancelled, summary: "Turn cancelled")
    case .turnFailed(let header, let reason):
      self.init(header: header, kind: .turnFailed, summary: "Turn failed: \(reason)", error: reason)
    }
  }

  private init(
    header: RuntimeEventHeader,
    kind: Kind,
    summary: String,
    messageID: UUID? = nil,
    providerRequestID: UUID? = nil,
    error: String? = nil
  ) {
    self.init(
      id: header.id,
      runID: header.runID,
      turnID: header.turnID,
      sequence: header.sequence,
      createdAt: header.createdAt,
      kind: kind,
      summary: summary,
      messageID: messageID,
      providerRequestID: providerRequestID,
      error: error
    )
  }
}

extension PersistedProviderRequestSummary {
  public init(request: ProviderRequest, createdAt: Date) {
    self.init(
      id: request.id,
      runID: request.runID,
      turnID: request.turnID,
      model: request.model,
      messageCount: request.messages.count,
      systemPromptIncluded: request.messages.contains(where: { $0.role == .system }),
      stream: request.stream,
      createdAt: createdAt
    )
  }
}

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var firstLineTitle: String {
    let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
    let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "New Chat" : String(trimmed.prefix(80))
  }
}
