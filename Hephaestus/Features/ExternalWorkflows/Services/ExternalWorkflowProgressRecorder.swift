import Foundation

actor ExternalWorkflowProgressRecorder {
    private(set) var timeline = ""
    private(set) var stepRecords: [WorkflowStepRecord] = []
    private var recordedEventKeys: Set<String> = []
    let debugLogURL: URL?

    init(debugLogURL: URL?) {
        self.debugLogURL = debugLogURL
    }

    var progress: WorkflowRunProgress {
        WorkflowRunProgress(timeline: timeline, debugLogURL: debugLogURL, stepRecords: stepRecords)
    }

    func record(_ event: ExternalWorkflowEvent) {
        let key = [
            event.type.rawValue,
            event.stepID ?? "",
            event.title ?? "",
            event.status?.rawValue ?? "",
            event.summary ?? "",
        ].joined(separator: "|")
        guard recordedEventKeys.insert(key).inserted else { return }

        timeline.append(timelineLine(for: event))
        timeline.append("\n")

        guard let stepID = event.stepID else { return }
        let status = WorkflowStepRecordStatus(eventStatus: event.status)
        let title = event.title ?? stepID
        let summary = event.summary ?? status.rawValue

        if let index = stepRecords.firstIndex(where: { $0.id == stepID }) {
            stepRecords[index].title = title
            stepRecords[index].status = status
            stepRecords[index].summary = summary
            if let inputPreview = event.inputPreview {
                stepRecords[index].inputPreview = inputPreview
            }
            stepRecords[index].outputPreview = event.outputPreview ?? event.summary
        } else {
            stepRecords.append(
                WorkflowStepRecord(
                    id: stepID,
                    title: title,
                    status: status,
                    summary: summary,
                    inputPreview: event.inputPreview,
                    outputPreview: event.outputPreview ?? event.summary,
                    sortOrder: stepRecords.count
                ))
        }
    }

    private func timelineLine(for event: ExternalWorkflowEvent) -> String {
        let title = event.title ?? event.stepID ?? "External workflow"
        let summary = event.summary.map { " - \($0)" } ?? ""
        switch event.type {
        case .workflowStarted:
            return "External workflow started: \(title)\(summary)"
        case .workflowFinished:
            return "External workflow finished: \(title)\(summary)"
        case .stepStarted:
            return "\(title) started\(summary)"
        case .stepFinished:
            return "\(title) finished\(summary)"
        case .logChunk:
            return summary.isEmpty ? title : summary
        }
    }
}

extension WorkflowStepRecordStatus {
    fileprivate nonisolated init(eventStatus: ExternalWorkflowEventStatus?) {
        switch eventStatus {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case nil:
            self = .pending
        }
    }
}

nonisolated struct PipeDrain {
    var chunks: [String] = []
    var completedLines: [String] = []

    mutating func append(_ drain: PipeDrain) {
        chunks.append(contentsOf: drain.chunks)
        completedLines.append(contentsOf: drain.completedLines)
    }
}
