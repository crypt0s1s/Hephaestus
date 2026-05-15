import Foundation

@MainActor
extension WorkflowRunnerModel {
    func updatePlanningDraftMessage(_ message: String) {
        updateInteraction {
            $0.note = message
            $0.errorMessage = nil
        }
    }

    func updatePlanningDraftPlan(_ plan: String) {
        updateInteraction {
            $0.updatePlanningDraftCandidate(content: plan, source: .user)
            $0.errorMessage = nil
        }
    }

    func sendPlanningMessage() async {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            !interaction.trimmedNote.isEmpty,
            interaction.phase == .idle
        else { return }
        let note = interaction.trimmedNote
        updateInteraction {
            $0.entries.append(PlanningInteractionEntry(source: .user, text: note))
            $0.note = ""
            $0.phase = .sending
            $0.errorMessage = nil
        }

        var assistantEntryID: PlanningInteractionEntry.ID?
        do {
            let session = try await planningSession(for: interaction, project: project)
            updateInteraction { $0.backendSession = session }
            let streamingEntryID = appendStreamingPlannerEntry()
            assistantEntryID = streamingEntryID
            let response = try await sendPlannerTurn(
                note: note,
                session: session,
                assistantEntryID: streamingEntryID
            )
            let loadedDraft = try materializePlannerDraft(
                response: response,
                project: project,
                interaction: interaction
            )
            applyCompletedPlannerTurn(draftArtifact: loadedDraft.artifact)
        } catch {
            handlePlannerTurnFailure(error, assistantEntryID: assistantEntryID)
        }
    }

    private func handlePlannerTurnFailure(
        _ error: Error,
        assistantEntryID: PlanningInteractionEntry.ID?
    ) {
        let message = "Planner turn failed: \(error.localizedDescription)"
        if let assistantEntryID {
            failStreamingPlannerEntry(id: assistantEntryID, message: message)
        }
        updateInteraction {
            $0.phase = .idle
            $0.errorMessage = message
        }
    }

    func submitPlanningDraftPlan() async {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            interaction.phase == .idle
        else { return }
        let submittedPlan = interaction.trimmedDraft
        guard !submittedPlan.isEmpty else {
            updateInteraction {
                $0.gateState = PlanningInteractionGateEvaluator.evaluate(candidate: $0.outputCandidate)
                $0.errorMessage = Self.planningDraftGateErrorMessage(for: $0.gateState)
            }
            return
        }
        guard interaction.canSubmit else {
            updateInteraction {
                $0.errorMessage = Self.planningDraftGateErrorMessage(for: interaction.gateState)
            }
            return
        }
        guard interaction.submittedOutput == nil else { return }

        updateInteraction {
            $0.phase = .materializing
            $0.errorMessage = nil
            $0.entries.append(
                PlanningInteractionEntry(
                    source: .system,
                    text: "Accepting the draft plan and preparing automated review cycles."
                )
            )
        }

        do {
            try await submitValidatedPlan(
                project: project,
                interaction: interaction,
                submittedPlan: submittedPlan
            )
        } catch {
            handlePlanningSubmissionFailure(error)
        }
    }

    func continuePlanningReview() {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            interaction.canResolveCompletedOutput
        else { return }
        let latestPlanOutput = interaction.latestResolvedOutput ?? interaction.submittedOutput
        updateInteraction {
            $0.sessionID = UUID().uuidString
            $0.submittedOutput = nil
            $0.gateState = .interacting
            if let latestPlanOutput {
                $0.updatePlanningDraftCandidate(content: latestPlanOutput.artifact.content, source: .user)
            } else {
                $0.updatePlanningDraftCandidate(content: $0.draft, source: .user)
            }
            $0.phase = .idle
            $0.errorMessage = nil
            $0.entries.append(
                PlanningInteractionEntry(
                    source: .system,
                    text: "Reopened planning with the latest reviewed plan and feedback history preserved."
                )
            )
        }
        update {
            $0.isRunning = false
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.activeWorkflowActivity = .waitingForInteraction
            $0.lastRunSucceeded = nil
            $0.stepRecords =
                planningReviewServices.makeWorkflowRunner()
                .startInteractivePlanning(project: project).stepRecords
            $0.timelineOutput = """
                Planning Review Workflow reopened.
                Interactive planning phase is waiting for updated input.
                """
            $0.statusMessage = "Planning reopened. Submit another draft to restart review cycles."
        }
    }

    func requestAnotherPlanningReviewCycle() async {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            let submittedOutput = interaction.submittedOutput,
            interaction.phase == .completed
        else { return }
        let currentPlanOutput = interaction.latestResolvedOutput ?? submittedOutput
        markPlanningReviewCycleRequested()
        let runner = planningReviewServices.makeWorkflowRunner()
        var run = runner.makeAdditionalAutomationRun(
            interaction: interaction,
            submittedOutput: submittedOutput,
            currentPlanOutput: currentPlanOutput,
            timeline: state.timelineOutput,
            records: state.stepRecords
        )
        await runner.runPlanningReviewAutomationCycle(
            cycle: runner.nextAutomationCycleNumber(from: state.stepRecords),
            project: project,
            run: &run,
            progress: { [weak model = self] progress in
                await model?.applyPlanningReviewProgress(progress)
            }
        )
        applyPlanningReviewResult(runner.finishPlanningReviewAutomationRun(run), run: run)
    }

    private func markPlanningReviewCycleRequested() {
        updateInteraction {
            $0.phase = .reviewing
            $0.errorMessage = nil
            $0.entries.append(
                PlanningInteractionEntry(
                    source: .system,
                    text: "Requested another automated review cycle for the latest reviewed plan."
                )
            )
        }
        update {
            $0.isRunning = true
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.activeWorkflowActivity = .running
            $0.lastRunSucceeded = nil
            $0.statusMessage = "Automated planning review cycles are running."
        }
    }

    private func submitValidatedPlan(
        project: WorkflowProject,
        interaction: PlanningInteractionState,
        submittedPlan: String
    ) async throws {
        let acceptance = try planningReviewServices.planArtifactMaterializer.acceptDraftForReview(
            project: project,
            sessionID: interaction.sessionID,
            producerStepID: interaction.stepID,
            request: PlanningDraftAcceptanceRequest(
                candidate: interaction.outputCandidate,
                expectedRevision: interaction.outputCandidate.revision,
                idempotencyKey: Self.acceptanceIdempotencyKey(for: interaction)
            )
        )
        let output = acceptance.output
        guard acceptance.isNewAcceptance else {
            applyAlreadyAcceptedPlan(interaction: interaction, output: output)
            return
        }
        let submittedInteraction = makeSubmittedPlanningInteraction(
            from: interaction,
            acceptance: acceptance
        )
        let runner = planningReviewServices.makeWorkflowRunner()
        let progress = runner.submitPlan(project: project, output: output)
        applySubmittedPlan(
            interaction: submittedInteraction,
            output: output,
            plan: submittedPlan,
            progress: progress
        )
        let result = await runner.runAutomatedReviewCycles(
            project: project,
            submittedOutput: output,
            sessionID: interaction.sessionID,
            progress: { [weak model = self] progress in
                await model?.applyPlanningReviewProgress(progress)
            }
        )
        applyPlanningReviewResult(result.processResult, run: result.run)
    }

    private func makeSubmittedPlanningInteraction(
        from interaction: PlanningInteractionState,
        acceptance: PlanningDraftAcceptance
    ) -> PlanningInteractionState {
        var submittedInteraction = interaction
        submittedInteraction.submittedOutput = acceptance.output
        submittedInteraction.relatedOutputs = [acceptance.output]
        submittedInteraction.latestResolvedOutput = acceptance.output
        submittedInteraction.phase = .reviewing
        submittedInteraction.acceptPlanningDraftCandidate(acceptance.record)
        let artifactPath = acceptance.output.artifact.projectRelativePath ?? "the project"
        submittedInteraction.entries.append(
            PlanningInteractionEntry(
                source: .system,
                text: "Accepted plan artifact was written to \(artifactPath). Automated review cycles are running."
            )
        )
        return submittedInteraction
    }

    private func materializePlannerDraft(
        response: String,
        project: WorkflowProject,
        interaction: PlanningInteractionState
    ) throws -> PlanningLoadedDraftArtifact {
        guard let plan = PlanningPlanExtractor.extractMarkdownPlan(from: response) else {
            throw PlanningPlanArtifactMaterializationError.missingRequiredSections(
                PlanningPlanArtifactPolicy.missingRequiredSections(in: response)
            )
        }
        return try planningReviewServices.planArtifactMaterializer.materializeDraftArtifact(
            project: project,
            sessionID: interaction.sessionID,
            content: plan
        )
    }

    private func handlePlanningSubmissionFailure(_ error: Error) {
        updateInteraction {
            $0.phase = .idle
            $0.errorMessage = "Plan submission failed: \(error.localizedDescription)"
        }
    }

    static func acceptanceIdempotencyKey(for interaction: PlanningInteractionState) -> String {
        "\(interaction.sessionID)-\(interaction.outputCandidate.outputID)-\(interaction.outputCandidate.revision)"
    }

    func updateInteraction(_ mutate: (inout PlanningInteractionState) -> Void) {
        update {
            guard var interaction = $0.planningInteraction else { return }
            mutate(&interaction)
            $0.planningInteraction = interaction
        }
    }

    private func applySubmittedPlan(
        interaction: PlanningInteractionState,
        output: InteractiveStepOutput,
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
                Path: \(output.artifact.projectRelativePath ?? "not exported")

                \(plan)
                """
            $0.isRunning = true
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.activeWorkflowActivity = .running
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = nil
            $0.statusMessage = "Submitted plan is validated and ready for automated review cycles."
        }
    }

    private func applyPlanningReviewProgress(_ progress: WorkflowRunProgress) {
        update {
            $0.stepRecords = progress.stepRecords
            $0.timelineOutput = progress.timeline
            $0.debugLogURL = progress.debugLogURL
            $0.isRunning = true
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.activeWorkflowActivity = .running
            $0.statusMessage = "Automated planning review cycles are running."
        }
    }

    private func applyPlanningReviewResult(
        _ result: ProcessResult,
        run: PlanningReviewAutomationRun? = nil
    ) {
        update {
            $0.output = result.output
            $0.timelineOutput = result.timeline.isEmpty ? result.output : result.timeline
            $0.stepRecords = result.stepRecords
            $0.debugLogURL = result.debugLogURL
            $0.isRunning = false
            $0.activeWorkflowID = result.exitCode == 0 ? PlanningReviewWorkflowRunner.id : nil
            $0.activeWorkflowActivity = result.exitCode == 0 ? .waitingForUserReview : nil
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = result.exitCode == 0 ? nil : false
            $0.statusMessage =
                result.exitCode == 0
                ? "Automated review cycles finished. Review the plan before accepting it."
                : "Automated review cycles failed. Inspect the run updates before retrying."
            $0.planningInteraction?.phase = result.exitCode == 0 ? .completed : .idle
            if let run {
                $0.planningInteraction?.relatedOutputs = run.relatedOutputs
                $0.planningInteraction?.latestResolvedOutput = run.currentPlanOutput
                if result.exitCode == 0, let latestPlan = run.currentPlanOutput {
                    $0.planningInteraction?.draft = latestPlan.artifact.content
                }
            }
            if result.exitCode != 0 {
                $0.planningInteraction?.sessionID = UUID().uuidString
                $0.planningInteraction?.submittedOutput = nil
                $0.planningInteraction?.gateState = .interacting
                if let draft = run?.currentPlanOutput?.artifact.content ?? $0.planningInteraction?.draft {
                    $0.planningInteraction?.updatePlanningDraftCandidate(content: draft, source: .user)
                }
                $0.planningInteraction?.errorMessage =
                    "Automated review failed. Update the draft or submit it again after inspecting the run."
            }
        }
    }

}
