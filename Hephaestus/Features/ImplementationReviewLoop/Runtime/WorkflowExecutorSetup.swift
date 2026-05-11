import Foundation

extension WorkflowExecutor {
    func validatePlanAndPrepareRun(
        project: WorkflowProject,
        request: ImplementationReviewWorkflowRequest,
        runState: WorkflowRunState,
        debugLog: WorkflowDebugLog
    ) async -> WorkflowPlanValidationResult {
        await runState.emit("Step 0 - Validating plan path.")
        await runState.upsertStep(
            id: "step-0-plan-validation",
            title: "Step 0 - Plan validation",
            status: .inProgress,
            summary: "Checking that the selected markdown plan exists inside the project.",
            inputPreview: request.planRelativePath,
            sortOrder: 0,
            hierarchy: runState.setupHierarchy(phaseOrder: 0)
        )

        do {
            let plan = try planValidator.loadPlan(project: project, relativePath: request.planRelativePath)
            let log = await prepareValidatedPlanRun(
                project: project, request: request, plan: plan, runState: runState, debugLog: debugLog)
            return .validated(plan: plan, log: log)
        } catch {
            let output = "Plan validation failed: \(error.localizedDescription)"
            await debugLog.append(output + "\n")
            await runState.emit("Step 0 - Plan validation failed.")
            await runState.upsertStep(
                id: "step-0-plan-validation",
                title: "Step 0 - Plan validation",
                status: .failed,
                summary: "Plan validation failed.",
                inputPreview: request.planRelativePath,
                outputPreview: output,
                sortOrder: 0,
                hierarchy: runState.setupHierarchy(phaseOrder: 0)
            )
            return .failed(await runState.result(exitCode: 2, output: output))
        }
    }

    func prepareValidatedPlanRun(
        project: WorkflowProject,
        request: ImplementationReviewWorkflowRequest,
        plan: PlanDocument,
        runState: WorkflowRunState,
        debugLog: WorkflowDebugLog
    ) async -> String {
        let log = """
            == Implementation Review Loop ==
            Project: \(project.path)
            Plan: \(plan.relativePath)
            Build command: \(request.normalizedBuildCommand)

            """
        await debugLog.append(log)
        await runState.emit("Step 0 - Plan validation passed: \(plan.relativePath).")
        await runState.upsertStep(
            id: "step-0-plan-validation",
            title: "Step 0 - Plan validation",
            status: .succeeded,
            summary: "Plan file loaded successfully.",
            inputPreview: plan.relativePath,
            outputPreview: plan.contents,
            sortOrder: 0,
            hierarchy: runState.setupHierarchy(phaseOrder: 0)
        )
        await runState.emit("Step 0 - Build command resolved: \(request.normalizedBuildCommand).")
        await runState.upsertStep(
            id: "step-0-build-command",
            title: "Step 0 - Build command",
            status: .succeeded,
            summary: "Build command resolved for this run.",
            inputPreview: request.buildCommand,
            outputPreview: request.normalizedBuildCommand,
            sortOrder: 1,
            hierarchy: runState.setupHierarchy(phaseOrder: 1)
        )
        return log
    }
}
