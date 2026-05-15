import Foundation

extension PlanningReviewPrototypeAutomation {
    func reviewerPrompt(
        name: String,
        project: WorkflowProject,
        planOutput: InteractiveStepOutput,
        planPath: String
    ) -> String {
        """
        You are \(name), a review-only planning agent.

        Review the submitted implementation plan. Do not edit files.

        Project path: \(project.path)
        Plan artifact path: \(planPath)

        Plan content:
        \(planOutput.artifact.content)

        Return at most 5 findings with severity P1, P2, or P3. Return exactly "pass" if the plan is
        clear, scoped, and testable.
        """
    }

    func plannerResponsePrompt(
        project: WorkflowProject,
        currentPlanOutput: InteractiveStepOutput,
        consolidatedFeedbackOutput: InteractiveStepOutput
    ) -> String {
        """
        You are the planner agent responding to automated review feedback.

        Do not edit files. Explain how the plan should change, then provide a revised markdown plan.
        The final answer must include the complete revised markdown plan with the required sections.

        Project path: \(project.path)

        Current plan:
        \(currentPlanOutput.artifact.content)

        Consolidated review feedback message:
        \(consolidatedFeedbackOutput.artifact.content)
        """
    }
}
