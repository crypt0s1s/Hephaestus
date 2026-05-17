import Foundation

nonisolated struct ExternalWorkflowEventLineInterpreter {
    func event(from line: String) -> ExternalWorkflowEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("{") else {
            return ExternalWorkflowEvent.processOutput(trimmed)
        }
        guard let data = trimmed.data(using: .utf8),
            let event = try? JSONDecoder().decode(ExternalWorkflowEvent.self, from: data)
        else {
            return ExternalWorkflowEvent.malformedLine(trimmed)
        }
        return event
    }
}

extension ExternalWorkflowEvent {
    nonisolated static func processOutput(_ line: String) -> ExternalWorkflowEvent {
        ExternalWorkflowEvent(
            type: .logChunk,
            stepID: nil,
            title: "External workflow output",
            status: nil,
            summary: line,
            inputPreview: nil,
            outputPreview: nil
        )
    }

    nonisolated static func malformedLine(_ line: String) -> ExternalWorkflowEvent {
        ExternalWorkflowEvent(
            type: .logChunk,
            stepID: nil,
            title: "Malformed external workflow event",
            status: nil,
            summary: "Ignored malformed external workflow event: \(preview(line))",
            inputPreview: nil,
            outputPreview: nil
        )
    }

    nonisolated static func processExitFailure(exitCode: Int32) -> ExternalWorkflowEvent {
        ExternalWorkflowEvent(
            type: .workflowFinished,
            stepID: nil,
            title: "External Swift workflow",
            status: .failed,
            summary: "External workflow process exited with code \(exitCode).",
            inputPreview: nil,
            outputPreview: nil
        )
    }

    nonisolated static func processTimeout(seconds: Int) -> ExternalWorkflowEvent {
        ExternalWorkflowEvent(
            type: .workflowFinished,
            stepID: nil,
            title: "External Swift workflow",
            status: .failed,
            summary: timeoutSummary(seconds: seconds),
            inputPreview: nil,
            outputPreview: nil
        )
    }

    nonisolated static func timeoutSummary(seconds: Int) -> String {
        let unit = seconds == 1 ? "second" : "seconds"
        return "External workflow timed out after \(seconds) \(unit)."
    }

    private nonisolated static func preview(_ line: String) -> String {
        let limit = 160
        guard line.count > limit else { return line }
        return "\(line.prefix(limit))..."
    }
}
