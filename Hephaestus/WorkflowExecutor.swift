import Foundation

struct WorkflowExecutor {
    private let codexStep: CodexAgentStep
    private let shellStep: ShellValidationStep
    private let planValidator: PlanFileValidator

    init(
        codexStep: CodexAgentStep,
        shellStep: ShellValidationStep,
        planValidator: PlanFileValidator = PlanFileValidator()
    ) {
        self.codexStep = codexStep
        self.shellStep = shellStep
        self.planValidator = planValidator
    }

    func runCodexStep(_ invocation: CodexAgentInvocation) async -> ProcessResult {
        await codexStep.run(invocation)
    }

    func runImplementationReviewLoop(
        project: WorkflowProject,
        request: ImplementationReviewWorkflowRequest,
        progress: WorkflowProgressHandler? = nil
    ) async -> ProcessResult {
        let debugLog = WorkflowDebugLog(projectName: project.name)
        let debugLogURL = await debugLog.fileURL
        await debugLog.append("""
        == Implementation Review Loop Debug Log ==
        Project: \(project.path)
        Requested plan: \(request.planRelativePath)
        Build command: \(request.normalizedBuildCommand)

        """)

        var timeline: [String] = []
        var stepRecords: [WorkflowStepRecord] = []
        func emit(_ line: String) async {
            timeline.append(line)
            await debugLog.append("[timeline] \(line)\n")
            await progress?(WorkflowRunProgress(
                timeline: timeline.joined(separator: "\n"),
                debugLogURL: debugLogURL,
                stepRecords: stepRecords.sorted { $0.sortOrder < $1.sortOrder }
            ))
        }
        func upsertStep(
            id: String,
            title: String,
            status: WorkflowStepRecordStatus,
            summary: String,
            inputPreview: String? = nil,
            outputPreview: String? = nil,
            sortOrder: Int
        ) async {
            if let index = stepRecords.firstIndex(where: { $0.id == id }) {
                stepRecords[index].title = title
                stepRecords[index].status = status
                stepRecords[index].summary = summary
                if let inputPreview {
                    stepRecords[index].inputPreview = inputPreview
                }
                if let outputPreview {
                    stepRecords[index].outputPreview = outputPreview
                }
                stepRecords[index].sortOrder = sortOrder
            } else {
                stepRecords.append(WorkflowStepRecord(
                    id: id,
                    title: title,
                    status: status,
                    summary: summary,
                    inputPreview: inputPreview,
                    outputPreview: outputPreview,
                    sortOrder: sortOrder
                ))
            }
            await progress?(WorkflowRunProgress(
                timeline: timeline.joined(separator: "\n"),
                debugLogURL: debugLogURL,
                stepRecords: stepRecords.sorted { $0.sortOrder < $1.sortOrder }
            ))
        }
        func result(
            exitCode: Int32,
            output: String,
            timedOut: Bool = false
        ) -> ProcessResult {
            ProcessResult(
                exitCode: exitCode,
                output: output,
                timeline: timeline.joined(separator: "\n"),
                debugLogURL: debugLogURL,
                timedOut: timedOut,
                stepRecords: stepRecords.sorted { $0.sortOrder < $1.sortOrder }
            )
        }

        await emit("Step 0 - Validating plan path.")
        await upsertStep(
            id: "step-0-plan-validation",
            title: "Step 0 - Plan validation",
            status: .inProgress,
            summary: "Checking that the selected markdown plan exists inside the project.",
            inputPreview: request.planRelativePath,
            sortOrder: 0
        )
        let plan: PlanDocument
        do {
            plan = try planValidator.loadPlan(project: project, relativePath: request.planRelativePath)
        } catch {
            let output = "Plan validation failed: \(error.localizedDescription)"
            await debugLog.append(output + "\n")
            await emit("Step 0 - Plan validation failed.")
            await upsertStep(
                id: "step-0-plan-validation",
                title: "Step 0 - Plan validation",
                status: .failed,
                summary: "Plan validation failed.",
                inputPreview: request.planRelativePath,
                outputPreview: output,
                sortOrder: 0
            )
            return result(
                exitCode: 2,
                output: output
            )
        }

        var log = """
        == Implementation Review Loop ==
        Project: \(project.path)
        Plan: \(plan.relativePath)
        Build command: \(request.normalizedBuildCommand)

        """
        await debugLog.append(log)
        await emit("Step 0 - Plan validation passed: \(plan.relativePath).")
        await upsertStep(
            id: "step-0-plan-validation",
            title: "Step 0 - Plan validation",
            status: .succeeded,
            summary: "Plan file loaded successfully.",
            inputPreview: plan.relativePath,
            outputPreview: plan.contents,
            sortOrder: 0
        )
        await emit("Step 0 - Build command resolved: \(request.normalizedBuildCommand).")
        await upsertStep(
            id: "step-0-build-command",
            title: "Step 0 - Build command",
            status: .succeeded,
            summary: "Build command resolved for this run.",
            inputPreview: request.buildCommand,
            outputPreview: request.normalizedBuildCommand,
            sortOrder: 1
        )
        var latestFeedback = ""

        for cycle in 0...request.maxReviewCycles {
            let isInitialImplementation = cycle == 0
            let cycleLabel = isInitialImplementation ? "initial implementation" : "fix cycle \(cycle)"
            let cycleSortOffset = isInitialImplementation ? 0 : cycle
            let implementerStepID = isInitialImplementation ? "step-1-implementer-initial" : "step-1-implementer-fix-\(cycle)"
            await emit("Step 1 - Implementer started \(cycleLabel).")
            let implementerPrompt = isInitialImplementation
                ? makeInitialImplementerPrompt(project: project, plan: plan)
                : makeFixPrompt(project: project, plan: plan, feedback: latestFeedback)
            await debugLog.append("""
            == Message to Implementer: \(cycleLabel) ==
            \(implementerPrompt)

            """)
            await upsertStep(
                id: implementerStepID,
                title: "Step 1 - Implementer",
                status: .inProgress,
                summary: "Implementer is running \(cycleLabel).",
                inputPreview: implementerPrompt,
                sortOrder: 10 + cycleSortOffset
            )
            let implementerResult = await codexStep.run(CodexAgentInvocation(
                name: isInitialImplementation ? "Implementer" : "Implementer Fix Cycle \(cycle)",
                project: project,
                prompt: implementerPrompt
            ))
            log += implementerResult.output + "\n"
            await debugLog.append(implementerResult.output + "\n")
            guard implementerResult.exitCode == 0 else {
                await emit("Step 1 - Implementer failed with exit code \(implementerResult.exitCode).")
                await upsertStep(
                    id: implementerStepID,
                    title: "Step 1 - Implementer",
                    status: .failed,
                    summary: "Implementer failed with exit code \(implementerResult.exitCode).",
                    inputPreview: implementerPrompt,
                    outputPreview: implementerResult.output,
                    sortOrder: 10 + cycleSortOffset
                )
                return result(
                    exitCode: implementerResult.exitCode,
                    output: log
                )
            }
            await emit("Step 1 - Implementer finished \(cycleLabel).")
            await upsertStep(
                id: implementerStepID,
                title: "Step 1 - Implementer",
                status: .succeeded,
                summary: "Implementer finished \(cycleLabel).",
                inputPreview: implementerPrompt,
                outputPreview: implementerResult.output,
                sortOrder: 10 + cycleSortOffset
            )

            await emit("Step 2 - Build started after \(cycleLabel).")
            let buildStepID = isInitialImplementation ? "step-2-build-initial" : "step-2-build-fix-\(cycle)"
            await upsertStep(
                id: buildStepID,
                title: "Step 2 - Build",
                status: .inProgress,
                summary: "Running build after \(cycleLabel).",
                inputPreview: request.normalizedBuildCommand,
                sortOrder: 20 + cycleSortOffset
            )
            let buildResult = await shellStep.run(ShellValidationInvocation(
                name: isInitialImplementation ? "Build After Implementation" : "Build After Fix Cycle \(cycle)",
                project: project,
                command: request.normalizedBuildCommand
            ))
            log += buildResult.output + "\n"
            await debugLog.append(buildResult.output + "\n")
            if buildResult.exitCode != 0 {
                await emit("Step 2 - Build failed with exit code \(buildResult.exitCode); feedback returned to implementer.")
                await upsertStep(
                    id: buildStepID,
                    title: "Step 2 - Build",
                    status: .failed,
                    summary: "Build failed with exit code \(buildResult.exitCode).",
                    inputPreview: request.normalizedBuildCommand,
                    outputPreview: buildResult.output,
                    sortOrder: 20 + cycleSortOffset
                )
                latestFeedback = """
                The build failed after \(isInitialImplementation ? "implementation" : "fix cycle \(cycle)").
                Fix the build failure and do not broaden scope.

                Build output:
                \(buildResult.output)
                """
                await upsertStep(
                    id: "step-4-feedback-\(cycle)",
                    title: "Step 4 - Feedback relay",
                    status: .succeeded,
                    summary: "Build failure feedback was prepared for the implementer.",
                    inputPreview: buildResult.output,
                    outputPreview: latestFeedback,
                    sortOrder: 40 + cycleSortOffset
                )
                if cycle == request.maxReviewCycles {
                    await emit("Step 4 - Loop stopped: max review cycles reached after build failure.")
                    return result(
                        exitCode: buildResult.exitCode,
                        output: log + "\nMax review cycles reached after build failure.\n"
                    )
                }
                continue
            }
            await emit("Step 2 - Build passed after \(cycleLabel).")
            await upsertStep(
                id: buildStepID,
                title: "Step 2 - Build",
                status: .succeeded,
                summary: "Build passed after \(cycleLabel).",
                inputPreview: request.normalizedBuildCommand,
                outputPreview: buildResult.output,
                sortOrder: 20 + cycleSortOffset
            )

            let reviewerAPrompt = makeReviewerPrompt(name: "Reviewer A", project: project, plan: plan)
            let reviewerBPrompt = makeReviewerPrompt(name: "Reviewer B", project: project, plan: plan)
            await emit("Step 3.1 - Reviewer A started.")
            await debugLog.append("""
            == Message to Reviewer A ==
            \(reviewerAPrompt)

            """)
            await upsertStep(
                id: "step-3-reviewer-a-\(cycle)",
                title: "Step 3.1 - Reviewer A",
                status: .inProgress,
                summary: "Reviewer A is checking the implementation.",
                inputPreview: reviewerAPrompt,
                sortOrder: 30 + cycleSortOffset
            )
            async let reviewerARun = runReviewer(name: "Reviewer A", project: project, prompt: reviewerAPrompt)
            await emit("Step 3.2 - Reviewer B started.")
            await debugLog.append("""
            == Message to Reviewer B ==
            \(reviewerBPrompt)

            """)
            await upsertStep(
                id: "step-3-reviewer-b-\(cycle)",
                title: "Step 3.2 - Reviewer B",
                status: .inProgress,
                summary: "Reviewer B is checking the implementation.",
                inputPreview: reviewerBPrompt,
                sortOrder: 31 + cycleSortOffset
            )
            async let reviewerBRun = runReviewer(name: "Reviewer B", project: project, prompt: reviewerBPrompt)
            let (reviewerA, reviewerB) = await (reviewerARun, reviewerBRun)
            await emit(reviewerA.finding.hasBlockingIssue
                ? "Step 3.1 - Reviewer A finished with blocking findings."
                : "Step 3.1 - Reviewer A passed.")
            await emit(reviewerB.finding.hasBlockingIssue
                ? "Step 3.2 - Reviewer B finished with blocking findings."
                : "Step 3.2 - Reviewer B passed.")
            log += reviewerA.transcriptBlock + "\n" + reviewerB.transcriptBlock + "\n"
            await debugLog.append(reviewerA.transcriptBlock + "\n" + reviewerB.transcriptBlock + "\n")
            await upsertStep(
                id: "step-3-reviewer-a-\(cycle)",
                title: "Step 3.1 - Reviewer A",
                status: reviewerA.finding.hasBlockingIssue ? .failed : .succeeded,
                summary: reviewerA.finding.hasBlockingIssue ? "Reviewer A reported blocking findings." : "Reviewer A passed.",
                inputPreview: reviewerAPrompt,
                outputPreview: reviewerA.finding.transcript,
                sortOrder: 30 + cycleSortOffset
            )
            await upsertStep(
                id: "step-3-reviewer-b-\(cycle)",
                title: "Step 3.2 - Reviewer B",
                status: reviewerB.finding.hasBlockingIssue ? .failed : .succeeded,
                summary: reviewerB.finding.hasBlockingIssue ? "Reviewer B reported blocking findings." : "Reviewer B passed.",
                inputPreview: reviewerBPrompt,
                outputPreview: reviewerB.finding.transcript,
                sortOrder: 31 + cycleSortOffset
            )

            let findings = [reviewerA.finding, reviewerB.finding]
            let blockingFindings = findings.filter(\.hasBlockingIssue)
            if blockingFindings.isEmpty {
                await emit("Step 4 - Workflow completed: build passed and both reviewers passed.")
                return result(
                    exitCode: 0,
                    output: log + "\nWorkflow passed: build succeeded and both reviewers passed or had no P1/P2 findings.\n"
                )
            }

            latestFeedback = makeReviewerFeedback(findings: blockingFindings)
            await debugLog.append("""
            == Message to Implementer: reviewer feedback for next cycle ==
            \(latestFeedback)

            """)
            await emit("Step 4 - Blocking review feedback returned to implementer.")
            await upsertStep(
                id: "step-4-feedback-\(cycle)",
                title: "Step 4 - Feedback relay",
                status: .succeeded,
                summary: "Blocking reviewer feedback was prepared for the implementer.",
                inputPreview: blockingFindings.map(\.transcript).joined(separator: "\n\n"),
                outputPreview: latestFeedback,
                sortOrder: 40 + cycleSortOffset
            )
            if cycle == request.maxReviewCycles {
                await emit("Step 4 - Loop stopped: max review cycles reached with unresolved findings.")
                return result(
                    exitCode: 1,
                    output: log + "\nMax review cycles reached with unresolved P1/P2 findings.\n"
                )
            }
        }

        await emit("Step 4 - Workflow ended before reviewers passed.")
        return result(
            exitCode: 1,
            output: log + "\nWorkflow ended before reviewers passed.\n"
        )
    }

    private func runReviewer(name: String, project: WorkflowProject, prompt: String) async -> ReviewerRun {
        let result = await codexStep.run(CodexAgentInvocation(
            name: name,
            project: project,
            prompt: prompt
        ))
        let transcript = result.exitCode == 0
            ? result.output
            : "P1: \(name) failed to run with exit code \(result.exitCode).\n\(result.output)"
        return ReviewerRun(
            name: name,
            finding: ReviewFinding(reviewerName: name, transcript: transcript),
            result: result
        )
    }

    private func makeInitialImplementerPrompt(project: WorkflowProject, plan: PlanDocument) -> String {
        """
        Implement the plan in \(plan.relativePath).

        You are the implementer agent for a deterministic Hephaestus implementation workflow.
        Project path: \(project.path)

        Source of truth plan:
        \(plan.contents)

        Rules:
        - Implement only the scope described by the markdown plan.
        - You are not alone in the codebase: do not revert or overwrite unrelated edits.
        - Use Swift for new iOS/macOS project files.
        - Keep public interfaces stable while internal layout evolves.
        - Final response must summarize changed paths, validation you ran, blockers, and caveats.
        """
    }

    private func makeFixPrompt(project: WorkflowProject, plan: PlanDocument, feedback: String) -> String {
        """
        Continue as the original implementer for the plan in \(plan.relativePath).

        Project path: \(project.path)

        Source of truth plan:
        \(plan.contents)

        Feedback to fix:
        \(feedback)

        Rules:
        - Fix only the reported build or P1/P2 review issues.
        - Do not broaden scope.
        - Do not revert or overwrite unrelated edits.
        - Final response must summarize changed paths, how each issue was resolved, validation you ran, blockers, and caveats.
        """
    }

    private func makeReviewerPrompt(name: String, project: WorkflowProject, plan: PlanDocument) -> String {
        """
        You are \(name), a review-only agent.

        Review the current implementation against this plan:
        \(plan.relativePath)

        Project path: \(project.path)

        Plan contents:
        \(plan.contents)

        Rules:
        - Do not edit files.
        - Focus on concrete deviations from the plan, build/runtime risks, missing acceptance criteria, missing tests, and scope creep.
        - Return findings with file/line references and severity labels P1, P2, or P3.
        - Return exactly "pass" if no concrete issues remain.
        - P1 blocks correctness, buildability, acceptance, or safe release.
        - P2 is meaningful behavior, architecture, test, or maintainability work that should be fixed before completion.
        - P3 is minor or follow-up.
        """
    }

    private func makeReviewerFeedback(findings: [ReviewFinding]) -> String {
        findings.map { finding in
            """
            \(finding.reviewerName) reported blocking findings:
            \(finding.transcript)
            """
        }
        .joined(separator: "\n\n")
    }
}

private struct ReviewerRun {
    let name: String
    let finding: ReviewFinding
    let result: ProcessResult

    var transcriptBlock: String {
        """
        == \(name) Review Result ==
        Exit code: \(result.exitCode)
        \(result.output)
        """
    }
}
