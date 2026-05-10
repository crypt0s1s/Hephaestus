import Foundation

struct BackendSession: Equatable, Identifiable {
  let id: String
  let backendName: String
  let project: WorkflowProject
  let nativeSessionID: String? = nil
}

struct StartSessionRequest: Equatable {
  let project: WorkflowProject
  let title: String
}

struct ResumeSessionRequest: Equatable {
  let session: BackendSession
}

struct StartTurnRequest: Equatable {
  let session: BackendSession
  let prompt: String
  let timeoutSeconds: TimeInterval?

  init(session: BackendSession, prompt: String, timeoutSeconds: TimeInterval? = nil) {
    self.session = session
    self.prompt = prompt
    self.timeoutSeconds = timeoutSeconds
  }
}

struct ApprovalResponse: Equatable {
  let sessionID: String
  let approved: Bool
}

struct CancelTurnRequest: Equatable {
  let sessionID: String
}

enum BackendEvent: Equatable {
  case sessionStarted(BackendSession)
  case turnStarted(sessionID: String)
  case outputChunk(String)
  case approvalRequested(String)
  case turnCompleted(ProcessResult)
  case turnFailed(ProcessResult)
  case turnCancelled(sessionID: String)
}

protocol HarnessBackendAdapter {
  func startSession(_ request: StartSessionRequest) async throws -> BackendSession
  func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession
  func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error>
  func respondToApproval(_ response: ApprovalResponse) async throws
  func cancelTurn(_ request: CancelTurnRequest) async throws
}
