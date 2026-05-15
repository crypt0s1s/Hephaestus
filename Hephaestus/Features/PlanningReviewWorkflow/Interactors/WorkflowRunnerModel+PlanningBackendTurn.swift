import Foundation

private enum PlanningInteractionError: LocalizedError {
    case plannerFailed(String)

    var errorDescription: String? {
        switch self {
        case .plannerFailed(let output):
            return output.isEmpty ? "Planner backend failed." : output
        }
    }
}

@MainActor
extension WorkflowRunnerModel {
    func planningSession(
        for interaction: PlanningInteractionState,
        project: WorkflowProject
    ) async throws -> BackendSession {
        try await planningReviewServices.interactionBackend.session(for: interaction, project: project)
    }

    func sendPlannerTurn(
        note: String,
        session: BackendSession,
        assistantEntryID: PlanningInteractionEntry.ID
    ) async throws -> String {
        let stream = try await planningReviewServices.interactionBackend.startPlannerTurn(
            note: note,
            session: session
        )
        return try await consumePlannerTurnStream(stream, assistantEntryID: assistantEntryID)
    }

    func appendStreamingPlannerEntry() -> PlanningInteractionEntry.ID {
        let entry = PlanningInteractionEntry(source: .assistant, text: "Thinking...")
        updateInteraction {
            $0.entries.append(entry)
        }
        return entry.id
    }

    private func consumePlannerTurnStream(
        _ stream: AsyncThrowingStream<BackendEvent, Error>,
        assistantEntryID: PlanningInteractionEntry.ID
    ) async throws -> String {
        var response = ""
        for try await event in stream {
            switch event {
            case .outputChunk(let chunk):
                response += chunk
                updateStreamingPlannerEntry(id: assistantEntryID, text: response)
            case .turnCompleted(let result):
                let completedResponse = response.isEmpty ? result.output : response
                updateStreamingPlannerEntry(id: assistantEntryID, text: completedResponse)
                return completedResponse
            case .turnFailed(let result):
                throw PlanningInteractionError.plannerFailed(result.output)
            case .sessionStarted,
                .turnStarted,
                .approvalRequested,
                .turnCancelled:
                continue
            }
        }
        return response
    }

    private func updateStreamingPlannerEntry(id: PlanningInteractionEntry.ID, text: String) {
        updateInteraction {
            guard let index = $0.entries.firstIndex(where: { $0.id == id }) else { return }
            $0.entries[index].text = text.isEmpty ? "Thinking..." : text
        }
    }

    func failStreamingPlannerEntry(id: PlanningInteractionEntry.ID, message: String) {
        updateStreamingPlannerEntry(id: id, text: message)
    }
}
