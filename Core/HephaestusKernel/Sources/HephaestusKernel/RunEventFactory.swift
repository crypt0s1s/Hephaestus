import Foundation

extension Run {
    enum PendingRunEvent {
        case userMessageAccepted(RunMessage)
        case contextPrepared(ContextAssemblyTrace)
        case providerRequestPrepared(ProviderRequest)
        case providerChunkReceived(UUID, String)
        case assistantMessageCompleted(RunMessage)
        case turnCancelled
        case turnFailed(String)
    }

    func nextEvent(_ event: PendingRunEvent, turnID: UUID) -> RunEvent {
        sequence += 1
        let header = EventHeader(runID: id, turnID: turnID, sequence: sequence)
        switch event {
        case .userMessageAccepted(let message):
            return .userMessageAccepted(header, message)
        case .contextPrepared(let trace):
            return .contextPrepared(header, trace)
        case .providerRequestPrepared(let request):
            return .providerRequestPrepared(header, request)
        case .providerChunkReceived(let requestID, let text):
            return .providerChunkReceived(header, requestID, text)
        case .assistantMessageCompleted(let message):
            return .assistantMessageCompleted(header, message)
        case .turnCancelled:
            return .turnCancelled(header)
        case .turnFailed(let reason):
            return .turnFailed(header, reason)
        }
    }
}

public enum RunFailure: Error, Equatable {
    case alreadyRunning
}
