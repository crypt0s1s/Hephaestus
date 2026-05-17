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
    func submitValidatedPlan(
        project: WorkflowProject,
        interaction: WorkflowInteractionState,
        submittedPlan: String
    ) async throws {
        let artifact = try planningReviewServices.planArtifactMaterializer.materializePlanArtifact(
            project: project,
            sessionID: interaction.sessionID,
            content: submittedPlan
        )
        let output = makeSubmittedPlanOutput(from: interaction, artifact: artifact)
        let message = PlanningReviewWorkflowRunner.makeSubmittedPlanMessage(
            runID: interaction.runtimeRun.id,
            output: output
        )
        try persistPlanningReviewMessagesOrThrow([message])
        let submittedInteraction = makeSubmittedInteraction(
            from: interaction,
            output: output,
            message: message,
            artifactPath: artifact.projectRelativePath
        )
        let runner = planningReviewServices.makeWorkflowRunner()
        let progress = runner.submitPlan(project: project, output: output)
        applySubmittedPlan(
            interaction: submittedInteraction,
            output: output,
            submittedMessage: message,
            plan: submittedPlan,
            progress: progress
        )
        let result = await runner.runAutomatedReviewCycles(
            project: project,
            submittedOutput: output,
            submittedPlanMessage: message,
            persistMessages: { [weak self] messages in
                guard let self else { return }
                try await self.persistPlanningReviewMessagesForAutomation(messages)
            },
            progress: { [weak model = self] progress in
                await model?.applyPlanningReviewProgress(progress)
            }
        )
        applyPlanningReviewResult(result)
    }

    func handlePlanningSubmissionFailure(_ error: Error) {
        updateInteraction {
            $0.phase = .idle
            $0.errorMessage = "Plan submission failed: \(error.localizedDescription)"
        }
    }

    func planningSession(
        for interaction: WorkflowInteractionState,
        project: WorkflowProject
    ) async throws -> BackendSession {
        if let session = interaction.backendSession {
            return try await planningReviewServices.backendAdapter.resumeSession(
                ResumeSessionRequest(session: session))
        }
        return try await planningReviewServices.backendAdapter.startSession(
            StartSessionRequest(project: project, title: "Planning Review")
        )
    }

    func sendPlannerTurn(
        note: String,
        session: BackendSession,
        assistantEntryID: WorkflowInteractionEntry.ID
    ) async throws -> String {
        let stream = try await planningReviewServices.backendAdapter.startTurn(
            StartTurnRequest(
                session: session,
                prompt: PlanningInteractionPrototypePrompts.plannerPrompt(for: note),
                timeoutSeconds: 180,
                sandboxMode: "read-only"
            )
        )
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

    func appendStreamingPlannerEntry() -> WorkflowInteractionEntry.ID {
        let entry = WorkflowInteractionEntry(source: .assistant, text: "Thinking...")
        updateInteraction {
            $0.entries.append(entry)
        }
        return entry.id
    }

    func updateStreamingPlannerEntry(id: WorkflowInteractionEntry.ID, text: String) {
        updateInteraction {
            guard let index = $0.entries.firstIndex(where: { $0.id == id }) else { return }
            $0.entries[index].text = text.isEmpty ? "Thinking..." : text
        }
    }

    func updateInteraction(_ mutate: (inout WorkflowInteractionState) -> Void) {
        update {
            guard var interaction = $0.planningInteraction else { return }
            mutate(&interaction)
            $0.planningInteraction = interaction
        }
    }

    func makeSubmittedPlanOutput(
        from interaction: WorkflowInteractionState,
        artifact: InteractiveStepArtifact
    ) -> InteractiveStepOutput {
        InteractiveStepOutput(
            producerStepID: interaction.stepID,
            artifact: artifact,
            summary: PlanningInteractionPrototypePrompts.submittedPlanSummary(from: artifact.content)
        )
    }

    func makeSubmittedInteraction(
        from interaction: WorkflowInteractionState,
        output: InteractiveStepOutput,
        message: WorkflowMessage,
        artifactPath: String?
    ) -> WorkflowInteractionState {
        var submittedInteraction = interaction
        submittedInteraction.submittedOutput = output
        submittedInteraction.workflowMessages.append(message)
        submittedInteraction.runtimeRun.status = .running
        submittedInteraction.runtimeRun.activePause = nil
        submittedInteraction.runtimeRun.messageIDs.append(message.id)
        submittedInteraction.runtimeRun.updatedAt = Date()
        submittedInteraction.phase = .reviewing
        let path = artifactPath ?? "the project"
        submittedInteraction.entries.append(
            WorkflowInteractionEntry(
                source: .system,
                text: "Plan artifact was written to \(path). Automated review cycles are running."
            )
        )
        return submittedInteraction
    }

    func applySubmittedPlan(
        interaction: WorkflowInteractionState,
        output: InteractiveStepOutput,
        submittedMessage: WorkflowMessage,
        plan: String,
        progress: WorkflowRunProgress
    ) {
        update {
            $0.planningInteraction = interaction
            $0.stepRecords = progress.stepRecords
            $0.timelineOutput = progress.timeline
            $0.output = """
                == Planning Review Workflow ==
                Submitted plan artifact: \(output.id)
                Submitted plan message: \(submittedMessage.id)
                Path: \(output.artifact.projectRelativePath ?? "not exported")

                \(plan)
                """
            $0.isRunning = true
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = nil
            $0.statusMessage = "Submitted plan is validated and ready for automated review cycles."
        }
    }

    func applyPlanningReviewProgress(_ progress: WorkflowRunProgress) {
        update {
            mergePlanningReviewMessages(progress.workflowMessages, into: &$0)
            $0.stepRecords = progress.stepRecords
            $0.timelineOutput = progress.timeline
            $0.debugLogURL = progress.debugLogURL
            $0.statusMessage = "Automated planning review cycles are running."
        }
    }

    func applyPlanningReviewResult(_ result: ProcessResult) {
        update {
            mergePlanningReviewMessages(result.workflowMessages, into: &$0)
            $0.output = result.output
            $0.timelineOutput = result.timeline.isEmpty ? result.output : result.timeline
            $0.stepRecords = result.stepRecords
            $0.debugLogURL = result.debugLogURL
            $0.isRunning = result.exitCode == 0
            $0.activeWorkflowID = result.exitCode == 0 ? PlanningReviewWorkflowRunner.id : nil
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = result.exitCode == 0 ? nil : false
            $0.statusMessage =
                result.exitCode == 0
                ? "Automated review cycles finished. Review the plan before accepting it."
                : "Automated review cycles failed. Inspect the run updates before retrying."
            $0.planningInteraction?.phase = result.exitCode == 0 ? .completed : .idle
            $0.planningInteraction?.runtimeRun.status = result.exitCode == 0 ? .paused : .failed
            if result.exitCode == 0,
                let runID = $0.planningInteraction?.runtimeRun.id {
                $0.planningInteraction?.runtimeRun.activePause = Self.makeUserReviewPause(runID: runID)
            } else {
                $0.planningInteraction?.runtimeRun.activePause = nil
            }
            $0.planningInteraction?.runtimeRun.updatedAt = Date()
            if result.exitCode != 0 {
                $0.planningInteraction?.submittedOutput = nil
                $0.planningInteraction?.errorMessage =
                    "Automated review failed. Update the draft or submit it again after inspecting the run."
            }
        }
    }

    func nextPlanningReviewCycleNumber() -> Int {
        let existingCycles = state.stepRecords.compactMap { record -> Int? in
            guard record.id.hasPrefix("planning-review-reviewer-") else { return nil }
            let parts = record.id.split(separator: "-")
            return parts.dropFirst(3).first.flatMap { Int($0) }
        }
        return (existingCycles.max() ?? 0) + 1
    }

    func submittedPlanMessage(
        for interaction: WorkflowInteractionState,
        output: InteractiveStepOutput
    ) -> WorkflowMessage {
        interaction.workflowMessages.first { $0.id == output.id }
            ?? PlanningReviewWorkflowRunner.makeSubmittedPlanMessage(
                runID: interaction.runtimeRun.id,
                output: output
            )
    }

    func latestPlanningReviewPlanMessage(
        for interaction: WorkflowInteractionState,
        fallback: WorkflowMessage
    ) -> WorkflowMessage {
        interaction.workflowMessages.last { $0.kind == .currentPlan } ?? fallback
    }

    func prepareAnotherPlanningReviewCycle() {
        updateInteraction {
            $0.phase = .reviewing
            $0.runtimeRun.status = .running
            $0.runtimeRun.activePause = nil
            $0.runtimeRun.updatedAt = Date()
            $0.errorMessage = nil
            $0.entries.append(
                WorkflowInteractionEntry(
                    source: .system,
                    text: "Requested another automated review cycle for the submitted plan."
                )
            )
        }
    }

    func persistPlanningReviewMessagesOrThrow(_ messages: [WorkflowMessage]) throws {
        guard !messages.isEmpty,
            let project = state.selectedProject,
            let interaction = state.planningInteraction
        else { return }
        _ = try planningReviewServices.messageStore.persistMessages(
            messages,
            project: project,
            sessionID: interaction.sessionID
        )
    }

    func persistPlanningReviewMessagesForAutomation(_ messages: [WorkflowMessage]) async throws {
        try persistPlanningReviewMessagesOrThrow(messages)
    }

    func mergePlanningReviewMessages(
        _ messages: [WorkflowMessage],
        into state: inout WorkflowRunnerState
    ) {
        guard var interaction = state.planningInteraction, !messages.isEmpty else { return }
        let existingIDs = Set(interaction.workflowMessages.map(\.id))
        let newMessages = messages.filter { !existingIDs.contains($0.id) }
        interaction.workflowMessages.append(contentsOf: newMessages)
        interaction.runtimeRun.messageIDs = interaction.workflowMessages.map(\.id)
        interaction.runtimeRun.updatedAt = Date()
        state.planningInteraction = interaction
    }

    static func makeInteractiveInputPause(
        runID: WorkflowRun.ID,
        stepID: String
    ) -> WorkflowPause {
        makePause(
            runID: runID,
            stepID: stepID,
            reason: .interactiveInput,
            commands: [
                (.submitInteractiveOutput, "Submit plan"),
            ]
        )
    }

    static func makeUserReviewPause(runID: WorkflowRun.ID) -> WorkflowPause {
        makePause(
            runID: runID,
            stepID: "interactive-user-review",
            reason: .userReview,
            commands: [
                (.acceptReviewedOutput, "Accept plan"),
                (.continueInteraction, "Continue planning"),
                (.requestAutomatedCycle, "Run another review cycle"),
            ]
        )
    }

    static func makePause(
        runID: WorkflowRun.ID,
        stepID: String,
        reason: WorkflowPauseReason,
        commands: [(WorkflowResumeCommandKind, String)]
    ) -> WorkflowPause {
        let pauseID = UUID().uuidString
        return WorkflowPause(
            id: pauseID,
            runID: runID,
            stepID: stepID,
            reason: reason,
            resumeCommands: commands.map { kind, label in
                WorkflowResumeCommand(runID: runID, pauseID: pauseID, kind: kind, label: label)
            }
        )
    }
}
