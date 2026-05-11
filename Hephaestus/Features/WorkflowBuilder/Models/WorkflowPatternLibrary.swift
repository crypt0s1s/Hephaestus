import Foundation

nonisolated enum WorkflowPatternLibrary {
    static func emptyWorkflow(now: Date = Date()) -> WorkflowGraphDefinition {
        let actor = codexActor(id: "actor-codex-collaborator", name: "Codex collaborator")
        return WorkflowGraphDefinition(
            id: "workflow-\(UUID().uuidString.lowercased())",
            metadata: WorkflowGraphMetadata(
                title: "Untitled workflow",
                summary: "Custom Codex workflow",
                createdAt: now,
                updatedAt: now
            ),
            actors: [actor]
        )
    }

    static func planningLoop(now: Date = Date()) -> WorkflowGraphDefinition {
        let actor = codexActor(id: "actor-planner", name: "Planner")
        let reviewer = codexActor(id: "actor-reviewer", name: "Planning reviewer")
        return WorkflowGraphDefinition(
            id: "planning-loop-\(UUID().uuidString.lowercased())",
            metadata: metadata(
                title: "Planning Loop",
                summary: "Interactive planning with automated review and a user review gate.",
                now: now
            ),
            nodes: planningNodes(actorID: actor.id, reviewerID: reviewer.id),
            links: planningLinks(),
            loops: planningLoops(),
            actors: [actor, reviewer]
        )
    }

    static func reviewLoop(now: Date = Date()) -> WorkflowGraphDefinition {
        let reviewer = codexActor(id: "actor-reviewer", name: "Reviewer")
        return WorkflowGraphDefinition(
            id: "review-loop-\(UUID().uuidString.lowercased())",
            metadata: metadata(
                title: "Review Loop",
                summary: "Review an artifact, collect findings, and gate continuation.",
                now: now
            ),
            nodes: reviewNodes(reviewerID: reviewer.id),
            links: reviewLinks(),
            loops: reviewLoops(),
            actors: [reviewer]
        )
    }

    static func implementationLoop(now: Date = Date()) -> WorkflowGraphDefinition {
        let implementer = codexActor(id: "actor-implementer", name: "Implementer")
        let reviewer = codexActor(id: "actor-reviewer", name: "Reviewer")
        return WorkflowGraphDefinition(
            id: "implementation-loop-\(UUID().uuidString.lowercased())",
            metadata: metadata(
                title: "Implementation Loop",
                summary: "Implement, validate, review, and repeat fixes until review passes.",
                now: now
            ),
            nodes: implementationNodes(implementerID: implementer.id, reviewerID: reviewer.id),
            links: implementationLinks(),
            loops: implementationLoops(),
            actors: [implementer, reviewer]
        )
    }

    static func allPatterns(now: Date = Date()) -> [WorkflowGraphDefinition] {
        [planningLoop(now: now), reviewLoop(now: now), implementationLoop(now: now)]
    }

    private static func planningNodes(actorID: String, reviewerID: String) -> [WorkflowNode] {
        [
            interactivePlanningNode(actorID: actorID),
            automatedPlanningReviewNode(reviewerID: reviewerID),
            plannerResponseNode(actorID: actorID),
            userPlanningReviewNode(actorID: actorID),
        ]
    }

    private static func interactivePlanningNode(actorID: String) -> WorkflowNode {
        WorkflowNode(
            id: "interactive-planning",
            title: "Interactive planning",
            role: .interactiveCodex,
            executionMode: .interactivePause,
            actorID: actorID,
            instructions: "Collaborate with the user to draft a reviewable implementation plan.",
            outputs: [io("draft-plan", "Draft plan", .plan)],
            approvalPolicy: .beforeContinue,
            position: WorkflowCanvasPosition(x: 80, y: 120)
        )
    }

    private static func automatedPlanningReviewNode(reviewerID: String) -> WorkflowNode {
        WorkflowNode(
            id: "automated-review",
            title: "Automated plan review",
            role: .review,
            executionMode: .separateCodexInstance,
            actorID: reviewerID,
            instructions: "Review the submitted plan for scope, architecture, validation, and missing decisions.",
            inputs: [io("plan-input", "Plan", .plan)],
            outputs: [io("review-feedback", "Review feedback", .reviewFeedback)],
            position: WorkflowCanvasPosition(x: 360, y: 80)
        )
    }

    private static func plannerResponseNode(actorID: String) -> WorkflowNode {
        WorkflowNode(
            id: "planner-response",
            title: "Planner response",
            role: .planning,
            executionMode: .automatic,
            actorID: actorID,
            instructions: "Revise the plan using consolidated review feedback.",
            inputs: [io("feedback-input", "Feedback", .reviewFeedback)],
            outputs: [io("revised-plan", "Revised plan", .plan)],
            position: WorkflowCanvasPosition(x: 640, y: 120)
        )
    }

    private static func userPlanningReviewNode(actorID: String) -> WorkflowNode {
        WorkflowNode(
            id: "user-review",
            title: "User review gate",
            role: .review,
            executionMode: .approvalGate,
            actorID: actorID,
            instructions: "Pause for the user to accept the plan or request another review cycle.",
            inputs: [io("revised-plan-input", "Revised plan", .plan)],
            outputs: [io("approval", "Approval decision", .approvalResult)],
            approvalPolicy: .beforeContinue,
            position: WorkflowCanvasPosition(x: 920, y: 120)
        )
    }

    private static func planningLinks() -> [WorkflowLink] {
        [
            link("planning-to-review", "interactive-planning", "draft-plan", "automated-review", "plan-input", .data),
            link(
                "review-to-response",
                "automated-review",
                "review-feedback",
                "planner-response",
                "feedback-input",
                .data
            ),
            link(
                "response-to-user-review",
                "planner-response",
                "revised-plan",
                "user-review",
                "revised-plan-input",
                .data
            ),
        ]
    }

    private static func planningLoops() -> [WorkflowLoop] {
        [
            WorkflowLoop(
                id: "planning-review-loop",
                title: "Planning review loop",
                memberNodeIDs: ["automated-review", "planner-response", "user-review"],
                entryNodeIDs: ["automated-review"],
                exitNodeIDs: ["user-review"],
                stopCondition: .untilApproval(maxIterations: 3),
                userBreakpointNodeIDs: ["user-review"]
            )
        ]
    }

    private static func reviewNodes(reviewerID: String) -> [WorkflowNode] {
        [
            WorkflowNode(
                id: "review-input",
                title: "Review target",
                role: .automatedExecution,
                executionMode: .manualOnly,
                actorID: reviewerID,
                instructions: "Provide the implementation output or artifact that needs review.",
                outputs: [io("target", "Review target", .artifactReference)],
                position: WorkflowCanvasPosition(x: 80, y: 120)
            ),
            WorkflowNode(
                id: "parallel-review",
                title: "Parallel review",
                role: .review,
                executionMode: .separateCodexInstance,
                actorID: reviewerID,
                instructions: "Run focused review passes and report blocking findings.",
                inputs: [io("target-input", "Review target", .artifactReference)],
                outputs: [io("findings", "Findings", .reviewFeedback)],
                position: WorkflowCanvasPosition(x: 360, y: 120)
            ),
            WorkflowNode(
                id: "review-gate",
                title: "Review approval gate",
                role: .review,
                executionMode: .approvalGate,
                actorID: reviewerID,
                instructions: "Pause when review findings require user approval or fix routing.",
                inputs: [io("findings-input", "Findings", .reviewFeedback)],
                outputs: [io("decision", "Decision", .decision)],
                approvalPolicy: .beforeContinue,
                position: WorkflowCanvasPosition(x: 640, y: 120)
            ),
        ]
    }

    private static func reviewLinks() -> [WorkflowLink] {
        [
            link("target-to-review", "review-input", "target", "parallel-review", "target-input", .artifact),
            link("review-to-gate", "parallel-review", "findings", "review-gate", "findings-input", .decision),
        ]
    }

    private static func reviewLoops() -> [WorkflowLoop] {
        [
            WorkflowLoop(
                id: "review-fix-loop",
                title: "Review/fix loop",
                memberNodeIDs: ["parallel-review", "review-gate"],
                entryNodeIDs: ["parallel-review"],
                exitNodeIDs: ["review-gate"],
                stopCondition: .untilNoBlockingFindings(maxIterations: 3),
                userBreakpointNodeIDs: ["review-gate"]
            )
        ]
    }

    private static func implementationNodes(implementerID: String, reviewerID: String) -> [WorkflowNode] {
        [
            implementNode(implementerID: implementerID),
            buildTestNode(implementerID: implementerID),
            implementationReviewNode(reviewerID: reviewerID),
            feedbackRelayNode(implementerID: implementerID),
        ]
    }

    private static func implementNode(implementerID: String) -> WorkflowNode {
        WorkflowNode(
            id: "implement",
            title: "Implement",
            role: .implementation,
            executionMode: .separateCodexInstance,
            actorID: implementerID,
            instructions: "Implement the accepted plan in the selected project.",
            inputs: [io("plan-input", "Plan", .plan)],
            outputs: [io("patch", "Implementation patch", .artifactReference)],
            capabilityScope: .codexWorkspaceWrite,
            position: WorkflowCanvasPosition(x: 80, y: 120)
        )
    }

    private static func buildTestNode(implementerID: String) -> WorkflowNode {
        WorkflowNode(
            id: "build-test",
            title: "Build and test",
            role: .terminalAssisted,
            executionMode: .terminalAssisted,
            actorID: implementerID,
            instructions: "Run the configured validation command and capture the terminal transcript.",
            inputs: [io("patch-input", "Patch", .artifactReference)],
            outputs: [io("terminal-transcript", "Terminal transcript", .terminalTranscript)],
            position: WorkflowCanvasPosition(x: 360, y: 120)
        )
    }

    private static func implementationReviewNode(reviewerID: String) -> WorkflowNode {
        WorkflowNode(
            id: "review",
            title: "Implementation review",
            role: .review,
            executionMode: .separateCodexInstance,
            actorID: reviewerID,
            instructions: "Review the implementation diff and validation output for blocking findings.",
            inputs: [io("patch-review-input", "Patch", .artifactReference)],
            outputs: [io("review-feedback", "Review feedback", .reviewFeedback)],
            position: WorkflowCanvasPosition(x: 640, y: 80)
        )
    }

    private static func feedbackRelayNode(implementerID: String) -> WorkflowNode {
        WorkflowNode(
            id: "feedback-relay",
            title: "Feedback relay",
            role: .automatedExecution,
            executionMode: .automatic,
            actorID: implementerID,
            instructions: "Route blocking feedback to the implementer or finish when review passes.",
            inputs: [io("feedback-input", "Feedback", .reviewFeedback)],
            outputs: [io("decision", "Decision", .decision)],
            position: WorkflowCanvasPosition(x: 920, y: 120)
        )
    }

    private static func implementationLinks() -> [WorkflowLink] {
        [
            link("implement-to-build", "implement", "patch", "build-test", "patch-input", .artifact),
            link("implement-to-review", "implement", "patch", "review", "patch-review-input", .artifact),
            link("review-to-relay", "review", "review-feedback", "feedback-relay", "feedback-input", .decision),
        ]
    }

    private static func implementationLoops() -> [WorkflowLoop] {
        [
            WorkflowLoop(
                id: "implementation-review-loop",
                title: "Implementation review loop",
                memberNodeIDs: ["implement", "build-test", "review", "feedback-relay"],
                entryNodeIDs: ["implement"],
                exitNodeIDs: ["feedback-relay"],
                stopCondition: .untilReviewPasses(maxIterations: 3),
                userBreakpointNodeIDs: ["feedback-relay"]
            )
        ]
    }

    private static func metadata(title: String, summary: String, now: Date) -> WorkflowGraphMetadata {
        WorkflowGraphMetadata(title: title, summary: summary, createdAt: now, updatedAt: now)
    }

    private static func codexActor(id: String, name: String) -> WorkflowActorProfile {
        WorkflowActorProfile(
            id: id,
            displayName: name,
            backend: .codex,
            rolePrompt: "You are \(name) in a Hephaestus workflow.",
            instancePolicy: .newInstancePerStep,
            defaultCapabilityScope: .codexReadOnly
        )
    }

    private static func io(_ id: String, _ name: String, _ kind: WorkflowValueKind) -> WorkflowIODeclaration {
        WorkflowIODeclaration(id: id, name: name, valueKind: kind, required: true)
    }

    private static func link(
        _ id: String,
        _ fromNodeID: String,
        _ fromOutputID: String,
        _ toNodeID: String,
        _ toInputID: String,
        _ kind: WorkflowLinkKind
    ) -> WorkflowLink {
        WorkflowLink(
            id: id,
            fromNodeID: fromNodeID,
            fromOutputID: fromOutputID,
            toNodeID: toNodeID,
            toInputID: toInputID,
            kind: kind
        )
    }
}
