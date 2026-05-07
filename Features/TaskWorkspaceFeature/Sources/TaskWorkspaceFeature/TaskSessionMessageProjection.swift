import Foundation
import HephaestusDomain
import TaskWorkspaceContracts

func appendAssistantDelta(_ text: String, to messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].text += text
    } else {
        messages.append(ConversationMessageState(role: .assistant, text: text, isStreaming: true))
    }
}

func completeAssistantMessage(messageID: UUID, text: String, in messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].id = messageID
        messages[index].text = text
        messages[index].isStreaming = false
    } else {
        messages.append(ConversationMessageState(id: messageID, role: .assistant, text: text))
    }
}

func markStreamingAssistantComplete(in messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].isStreaming = false
    }
}

extension String {
    var firstLineTitle: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Task" : String(trimmed.prefix(80))
    }
}

extension TaskSessionSnapshot {
    var taskStatus: TaskStatus {
        switch turnState {
        case .loading:
            return .running
        case .loaded(let progress):
            if progress.isRunning {
                return .running
            }
            return messages.isEmpty ? .draft : .completed
        case .error:
            return .failed
        }
    }
}
