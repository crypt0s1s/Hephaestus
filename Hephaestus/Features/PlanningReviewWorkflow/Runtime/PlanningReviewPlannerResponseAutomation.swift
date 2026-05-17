import Foundation

extension PlanningReviewPrototypeAutomation {
    func runPlannerResponse(
        cycle: Int,
        project: WorkflowProject,
        sessionID: String,
        currentPlanOutput: InteractiveStepOutput,
        consolidatedFeedbackOutput: InteractiveStepOutput
    ) async -> PlanningPlannerResponseRun {
        let prompt = plannerResponsePrompt(
            project: project,
            currentPlanOutput: currentPlanOutput,
            consolidatedFeedbackOutput: consolidatedFeedbackOutput
        )
        let result = await runPlannerAgent(cycle: cycle, project: project, prompt: prompt)
        let materialized = materializePlannerResponse(
            result: result,
            project: project,
            sessionID: sessionID,
            cycle: cycle
        )
        return plannerResponseRecord(
            cycle: cycle,
            prompt: prompt,
            result: result,
            materialized: materialized
        )
    }

    private func runPlannerAgent(
        cycle: Int,
        project: WorkflowProject,
        prompt: String
    ) async -> ProcessResult {
        await agent.run(
            PlanningAgentInvocation(
                name: "Planner Response Cycle \(cycle)",
                project: project,
                prompt: prompt,
                timeoutSeconds: 180,
                sandboxMode: "read-only"
            ))
    }

    private func materializePlannerResponse(
        result: ProcessResult,
        project: WorkflowProject,
        sessionID: String,
        cycle: Int
    ) -> PlanningPlannerResponseMaterialization {
        guard result.exitCode == 0 else {
            return PlanningPlannerResponseMaterialization(output: nil, error: nil)
        }
        guard let revisedPlan = PlanningPlanExtractor.extractMarkdownPlan(from: result.output) else {
            return PlanningPlannerResponseMaterialization(
                output: nil,
                error: PlanningPlannerResponseError.missingRevisedPlan
            )
        }
        do {
            let output = try artifactStore.materializePlannerResponsePlan(
                project: project,
                sessionID: sessionID,
                cycle: cycle,
                content: revisedPlan
            )
            return PlanningPlannerResponseMaterialization(output: output, error: nil)
        } catch {
            return PlanningPlannerResponseMaterialization(output: nil, error: error)
        }
    }

    private func plannerResponseRecord(
        cycle: Int,
        prompt: String,
        result: ProcessResult,
        materialized: PlanningPlannerResponseMaterialization
    ) -> PlanningPlannerResponseRun {
        WorkflowStepRecord(
            id: "planning-review-planner-response-\(cycle)",
            title: "Planner response cycle \(cycle)",
            status: plannerResponseStatus(result: result, materialized: materialized),
            summary: plannerResponseSummary(cycle: cycle, result: result, materialized: materialized),
            inputPreview: prompt,
            outputPreview: result.output,
            sortOrder: 130 + (cycle * 100)
        )
        .plannerResponseRun(revisedPlanOutput: materialized.output)
    }

    private func plannerResponseStatus(
        result: ProcessResult,
        materialized: PlanningPlannerResponseMaterialization
    ) -> WorkflowStepRecordStatus {
        result.exitCode == 0 && materialized.error == nil ? .succeeded : .failed
    }

    private func plannerResponseSummary(
        cycle: Int,
        result: ProcessResult,
        materialized: PlanningPlannerResponseMaterialization
    ) -> String {
        if materialized.output != nil {
            return "Planner responded to review feedback cycle \(cycle)."
        }
        if let error = materialized.error {
            return "Planner response plan could not be persisted: \(error.localizedDescription)"
        }
        return "Planner response failed in cycle \(cycle)."
    }
}

private struct PlanningPlannerResponseMaterialization {
    let output: InteractiveStepOutput?
    let error: Error?
}

private enum PlanningPlannerResponseError: LocalizedError {
    case missingRevisedPlan

    var errorDescription: String? {
        "Planner response did not include a valid revised plan artifact."
    }
}
