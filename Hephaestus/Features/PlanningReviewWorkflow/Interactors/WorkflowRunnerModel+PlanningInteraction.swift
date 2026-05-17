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
            if $0.draft != plan {
                $0.draftProvenance =
                    plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .empty
                    : .userEdited
            }
            $0.draft = plan
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
            $0.entries.append(WorkflowInteractionEntry(source: .user, text: note))
            $0.note = ""
            $0.phase = .sending
            $0.errorMessage = nil
        }

        do {
            let session = try await planningSession(for: interaction, project: project)
            updateInteraction { $0.backendSession = session }
            let assistantEntryID = appendStreamingPlannerEntry()
            let response = try await sendPlannerTurn(
                note: note,
                session: session,
                assistantEntryID: assistantEntryID
            )
            applyCompletedPlannerTurn(response)
        } catch {
            updateInteraction {
                $0.phase = .idle
                $0.errorMessage = "Planner turn failed: \(error.localizedDescription)"
            }
        }
    }

    func submitPlanningDraftPlan() async {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            interaction.phase == .idle
        else { return }
        let submittedPlan = interaction.trimmedDraft
        guard !submittedPlan.isEmpty else {
            updateInteraction { $0.errorMessage = "Add a draft plan before submitting." }
            return
        }
        guard interaction.draftProvenance == .userEdited else {
            updateInteraction {
                $0.errorMessage = "Edit the generated draft before submitting it for review."
            }
            return
        }
        guard interaction.submittedOutput == nil else { return }

        updateInteraction {
            $0.phase = .materializing
            $0.errorMessage = nil
            $0.entries.append(
                WorkflowInteractionEntry(
                    source: .system,
                    text: "Submitting the draft plan and preparing automated review cycles."
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

    func acceptPlanningReview() {
        guard let interaction = state.planningInteraction,
            interaction.canResolveCompletedOutput
        else { return }
        update {
            $0.isRunning = false
            $0.activeWorkflowID = nil
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = true
            $0.statusMessage = "Planning review workflow accepted."
            $0.planningInteraction?.phase = .accepted
            $0.planningInteraction?.runtimeRun.status = .completed
            $0.planningInteraction?.runtimeRun.activePause = nil
            $0.planningInteraction?.runtimeRun.updatedAt = Date()
            $0.planningInteraction?.entries.append(
                WorkflowInteractionEntry(
                    source: .system,
                    text: "Accepted the submitted plan and completed the workflow."
                )
            )
        }
    }

    func continuePlanningReview() {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            interaction.canResolveCompletedOutput
        else { return }
        let latestPlan = latestPlanningReviewPlanContent(for: interaction)
        let feedbackHistory = planningReviewFeedbackHistory(from: interaction.workflowMessages)
        let continuedRecords = planningReviewContinuationRecords(
            from: state.stepRecords,
            feedbackHistory: feedbackHistory
        )
        updateInteraction {
            reopenPlanningInteraction(
                &$0,
                latestPlan: latestPlan,
                feedbackHistory: feedbackHistory
            )
        }
        update {
            $0.isRunning = true
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = nil
            $0.stepRecords = continuedRecords
            $0.timelineOutput = """
                Planning Review Workflow reopened.
                Interactive planning phase resumed with the latest plan and feedback history.
                """
            $0.statusMessage = continuedPlanningStatusMessage(project: project)
        }
    }

    func requestAnotherPlanningReviewCycle() async {
        guard let project = state.selectedProject,
            let interaction = state.planningInteraction,
            let output = interaction.submittedOutput,
            interaction.phase == .completed
        else { return }
        let submittedPlanMessage = submittedPlanMessage(for: interaction, output: output)
        prepareAnotherPlanningReviewCycle()
        let runner = planningReviewServices.makeWorkflowRunner()
        var run = PlanningReviewPrototypeAutomationRun(
            timeline: state.timelineOutput.isEmpty
                ? planningReviewServices.automation.startedTimeline
                : state.timelineOutput,
            records: state.stepRecords.filter { $0.id != "planning-review-interactive-user-review" },
            planPath: output.artifact.projectRelativePath ?? "the submitted plan artifact",
            workflowMessages: interaction.workflowMessages
        )
        await runner.runPlanningReviewPrototypeAutomationCycle(
            cycle: nextPlanningReviewCycleNumber(),
            project: project,
            currentPlanMessage: latestPlanningReviewPlanMessage(
                for: interaction,
                fallback: submittedPlanMessage
            ),
            run: &run,
            persistMessages: { [weak self] messages in
                guard let self else { return }
                try await self.persistPlanningReviewMessagesForAutomation(messages)
            },
            progress: { [weak model = self] progress in
                await model?.applyPlanningReviewProgress(progress)
            }
        )
        applyPlanningReviewResult(runner.finishPlanningReviewPrototypeAutomationRun(run))
    }
}
