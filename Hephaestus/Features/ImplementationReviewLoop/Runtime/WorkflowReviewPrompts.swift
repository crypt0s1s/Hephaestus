import Foundation

extension WorkflowExecutor {
    func makeInitialImplementerPrompt(project: WorkflowProject, plan: PlanDocument) -> String {
        """
        Implement the plan in \(plan.relativePath).

        You are the implementer agent for a deterministic Hephaestus implementation workflow.
        Project path: \(project.path)

        The plan is located at:
        \(plan.relativePath)

        Read the plan from that path before editing.

        Rules:
        - Implement only the scope described by the markdown plan.
        - You are not alone in the codebase: do not revert or overwrite unrelated edits.
        - Use Swift for new iOS/macOS project files.
        - Keep public interfaces stable while internal layout evolves.
        - Final response must summarize changed paths, validation you ran, blockers, and caveats.
        """
    }

    func makeFixPrompt(project: WorkflowProject, plan: PlanDocument, feedback: String) -> String {
        """
        Continue as the original implementer for the plan in \(plan.relativePath).

        Project path: \(project.path)

        The plan is located at:
        \(plan.relativePath)

        Re-read the plan from that path before editing.

        Feedback to fix:
        \(feedback)

        Rules:
        - Fix only the reported build or P1/P2 review issues.
        - Do not broaden scope.
        - Do not revert or overwrite unrelated edits.
        - Final response must summarize changed paths, resolutions, validation, blockers, and caveats.
        """
    }

    func makeReviewerPrompt(name: String, project: WorkflowProject, plan: PlanDocument) -> String {
        """
        You are \(name), a review-only agent.

        Review the current implementation against the plan located at:
        \(plan.relativePath)

        Project path: \(project.path)

        Rules:
        - Do not edit files.
        - Read the plan from the path above before reviewing.
        - Review only the current uncommitted implementation diff and directly referenced files.
        - Shell is allowed only for read-only inspection and comparison.
        - Allowed examples: `git diff`, `git status`, `rg`, `sed`, `nl`, or touched-file reads.
        - The workflow build step has already run.
        - Do not run or retry builds, tests, package resolution, scripts, simulators, or app launches.
        - Do not run validation commands such as `swift test`, `xcodebuild`, `npm test`, or `make`.
        - If validation output is needed, rely on the workflow's build result.
        - Report only issues visible from the diff/source review.
        - Use targeted reads of touched files only; do not do long repository-wide searches.
        - Focus on deviations from the plan, runtime risks, missing criteria/tests, and scope creep.
        - Return at most 5 findings with file/line references and severity labels P1, P2, or P3.
        - Return exactly "pass" if no concrete issues remain.
        - P1 blocks correctness, buildability, acceptance, or safe release.
        - P2 is meaningful behavior, architecture, test, or maintainability work to fix before completion.
        - P3 is minor or follow-up.
        - Do not include command output, raw JSON, transcripts, or a change summary.
        """
    }

    func makeReviewerFeedback(findings: [ReviewFinding]) -> String {
        findings.map { finding in
            """
            \(finding.reviewerName) reported blocking findings:
            \(finding.transcript)
            """
        }
        .joined(separator: "\n\n")
    }
}

struct ReviewerRun {
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

struct WorkflowReviewCycleInfo {
    let cycle: Int

    var isInitialImplementation: Bool { cycle == 0 }
    var label: String { isInitialImplementation ? "initial implementation" : "fix cycle \(cycle)" }
    var sortBase: Int { 100 + (cycle * 100) }

    var implementerStepID: String {
        isInitialImplementation ? "step-1-implementer-initial" : "step-1-implementer-fix-\(cycle)"
    }

    var buildStepID: String {
        isInitialImplementation ? "step-2-build-initial" : "step-2-build-fix-\(cycle)"
    }

    func implementerInvocation(project: WorkflowProject, prompt: String) -> CodexAgentInvocation {
        CodexAgentInvocation(
            name: isInitialImplementation ? "Implementer" : "Implementer Fix Cycle \(cycle)",
            project: project,
            prompt: prompt
        )
    }

    func buildInvocation(
        project: WorkflowProject,
        request: ImplementationReviewWorkflowRequest
    ) -> ShellValidationInvocation {
        ShellValidationInvocation(
            name: isInitialImplementation
                ? "Build After Implementation" : "Build After Fix Cycle \(cycle)",
            project: project,
            command: request.normalizedBuildCommand
        )
    }

    func buildFailureFeedback(output: String) -> String {
        """
        The build failed after \(isInitialImplementation ? "implementation" : "fix cycle \(cycle)").
        Fix the build failure and do not broaden scope.

        Build output:
        \(output)
        """
    }
}

enum WorkflowCycleContinuation {
    case continueLoop
    case finish(ProcessResult)
}

enum WorkflowPlanValidationResult {
    case validated(plan: PlanDocument, log: String)
    case failed(ProcessResult)
}

enum WorkflowBuildStepResult {
    case passed
    case needsFix
    case failed(ProcessResult)
}

enum WorkflowReviewerSlot {
    case a
    case b

    var name: String {
        switch self {
        case .a: return "Reviewer A"
        case .b: return "Reviewer B"
        }
    }

    var number: Int {
        switch self {
        case .a: return 1
        case .b: return 2
        }
    }

    var sortOffset: Int {
        switch self {
        case .a: return 30
        case .b: return 31
        }
    }

    func stepID(cycle: Int) -> String {
        switch self {
        case .a: return "step-3-reviewer-a-\(cycle)"
        case .b: return "step-3-reviewer-b-\(cycle)"
        }
    }

    func promptLogName(cycle: Int) -> String {
        switch self {
        case .a: return "step-3-reviewer-a-\(cycle)-prompt.md"
        case .b: return "step-3-reviewer-b-\(cycle)-prompt.md"
        }
    }

    func outputLogName(cycle: Int) -> String {
        switch self {
        case .a: return "step-3-reviewer-a-\(cycle)-output.log"
        case .b: return "step-3-reviewer-b-\(cycle)-output.log"
        }
    }

    func hierarchy(
        cycleInfo: WorkflowReviewCycleInfo,
        outcome: WorkflowStepRecordCycleOutcome?,
        runState: WorkflowRunState
    ) -> WorkflowStepRecordHierarchy {
        runState.cycleHierarchy(
            cycle: cycleInfo.cycle,
            parentID: "cycle-\(cycleInfo.cycle)-review",
            depth: 2,
            phaseOrder: sortOffset,
            outcome: outcome
        )
    }
}

struct ReviewerPromptPair {
    let a: String
    let b: String
}

struct ReviewerRunPair {
    let a: ReviewerRun
    let b: ReviewerRun

    var findings: [ReviewFinding] {
        [a.finding, b.finding]
    }

    var transcriptBlock: String {
        a.transcriptBlock + "\n" + b.transcriptBlock
    }
}
