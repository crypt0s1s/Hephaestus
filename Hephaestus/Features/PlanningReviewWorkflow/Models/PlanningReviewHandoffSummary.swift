import Foundation

struct PlanningReviewHandoffSummary: Equatable {
    let title: String
    let subtitle: String
    let latestArtifact: PlanningReviewHandoffArtifact?
    let cycles: [PlanningReviewHandoffCycle]
    let markers: [PlanningReviewHandoffMarker]

    init?(state: PlanningInteractionState) {
        let cycleOutputs = Self.cycleOutputs(from: state)
        let latestOutput = Self.latestOutput(from: state, cycleOutputs: cycleOutputs)
        guard (state.canResolveCompletedOutput || state.phase == .accepted)
            && (latestOutput != nil || !cycleOutputs.isEmpty)
        else { return nil }

        let latestArtifact = latestOutput.map {
            PlanningReviewHandoffArtifact.latest(output: $0, phase: state.phase)
        }
        let cycles = PlanningReviewHandoffCycle.group(outputs: cycleOutputs)

        self.title = state.phase == .accepted ? "Accepted handoff" : "Review handoff"
        self.subtitle =
            state.phase == .accepted
            ? "The final reviewed plan has been accepted."
            : "Review the latest plan and cycle artifacts before choosing the next action."
        self.latestArtifact = latestArtifact
        self.cycles = cycles
        self.markers = Self.makeMarkers(latestArtifact: latestArtifact, cycles: cycles)
    }

    private static func cycleOutputs(from state: PlanningInteractionState) -> [InteractiveStepOutput] {
        (
            [state.submittedOutput].compactMap { $0 }
                + state.relatedOutputs
        )
        .uniquedByIDKeepingLast()
    }

    private static func latestOutput(
        from state: PlanningInteractionState,
        cycleOutputs: [InteractiveStepOutput]
    ) -> InteractiveStepOutput? {
        state.latestResolvedOutput
            ?? cycleOutputs.last { $0.reviewArtifactRole == .plan }
            ?? state.submittedOutput
            ?? cycleOutputs.last
    }

    private static func makeMarkers(
        latestArtifact: PlanningReviewHandoffArtifact?,
        cycles: [PlanningReviewHandoffCycle]
    ) -> [PlanningReviewHandoffMarker] {
        var markers: [PlanningReviewHandoffMarker] = []
        if latestArtifact != nil {
            markers.append(
                PlanningReviewHandoffMarker(
                    title: "Latest reviewed plan",
                    identifier: "planning.reviewArtifactIndex.latestReviewedPlan"
                )
            )
        }
        for cycle in cycles {
            if cycle.feedback != nil {
                markers.append(
                    PlanningReviewHandoffMarker(
                        title: "Cycle \(cycle.number) review feedback",
                        identifier: "planning.reviewArtifactIndex.cycle.\(cycle.number).feedback"
                    )
                )
            }
            if cycle.plan != nil {
                markers.append(
                    PlanningReviewHandoffMarker(
                        title: "Cycle \(cycle.number) planner response plan",
                        identifier: "planning.reviewArtifactIndex.cycle.\(cycle.number).plan"
                    )
                )
            }
        }
        return markers
    }
}

struct PlanningReviewHandoffArtifact: Identifiable, Equatable {
    let id: String
    let title: String
    let badge: String
    let output: InteractiveStepOutput
    let accessibilityIdentifier: String

    var pathText: String {
        output.artifact.projectRelativePath ?? output.summary ?? output.artifact.title
    }

    var copyPath: String? {
        output.artifact.projectRelativePath
    }

    static func latest(
        output: InteractiveStepOutput,
        phase: PlanningInteractionState.Phase
    ) -> PlanningReviewHandoffArtifact {
        PlanningReviewHandoffArtifact(
            title: phase == .accepted ? "Final accepted plan" : "Latest reviewed plan",
            badge: phase == .accepted ? "Final" : "Current",
            output: output,
            accessibilityIdentifier: "planning.latestReviewedPlan"
        )
    }

    static func feedback(output: InteractiveStepOutput, cycle: Int) -> PlanningReviewHandoffArtifact {
        PlanningReviewHandoffArtifact(
            title: "Review feedback",
            badge: "Feedback",
            output: output,
            accessibilityIdentifier: "planning.reviewCycle.\(cycle).feedback"
        )
    }

    static func plan(output: InteractiveStepOutput, cycle: Int) -> PlanningReviewHandoffArtifact {
        PlanningReviewHandoffArtifact(
            title: "Planner response plan",
            badge: "Plan",
            output: output,
            accessibilityIdentifier: "planning.reviewCycle.\(cycle).plan"
        )
    }

    private init(
        title: String,
        badge: String,
        output: InteractiveStepOutput,
        accessibilityIdentifier: String
    ) {
        self.id = accessibilityIdentifier
        self.title = title
        self.badge = badge
        self.output = output
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

struct PlanningReviewHandoffCycle: Identifiable, Equatable {
    let number: Int
    var feedback: PlanningReviewHandoffArtifact?
    var plan: PlanningReviewHandoffArtifact?

    var id: Int {
        number
    }

    static func group(outputs: [InteractiveStepOutput]) -> [PlanningReviewHandoffCycle] {
        var cycles: [Int: PlanningReviewHandoffCycle] = [:]
        for output in outputs {
            guard let cycleNumber = output.reviewCycleNumber else { continue }
            var cycle = cycles[cycleNumber] ?? PlanningReviewHandoffCycle(number: cycleNumber)
            switch output.reviewArtifactRole {
            case .feedback:
                cycle.feedback = .feedback(output: output, cycle: cycleNumber)
            case .plan:
                cycle.plan = .plan(output: output, cycle: cycleNumber)
            case .other:
                break
            }
            cycles[cycleNumber] = cycle
        }
        return cycles.values.sorted { $0.number < $1.number }
    }
}

struct PlanningReviewHandoffMarker: Identifiable, Equatable {
    let title: String
    let identifier: String

    var id: String {
        identifier
    }
}

extension PlanningInteractionState {
    var reviewHandoffSummary: PlanningReviewHandoffSummary? {
        PlanningReviewHandoffSummary(state: self)
    }
}

private enum PlanningReviewArtifactRole {
    case feedback
    case plan
    case other
}

private extension InteractiveStepOutput {
    var reviewCycleNumber: Int? {
        artifact.projectRelativePath?.reviewCycleNumber
    }

    var reviewArtifactRole: PlanningReviewArtifactRole {
        if artifact.contentType.contains("consolidated-review") {
            return .feedback
        }
        if producerStepID.hasPrefix("planner-response-cycle-") {
            return .plan
        }
        return .other
    }
}

private extension String {
    var reviewCycleNumber: Int? {
        let components = split(separator: "/")
        guard let cyclesIndex = components.firstIndex(of: "cycles") else { return nil }
        let numberIndex = components.index(after: cyclesIndex)
        guard components.indices.contains(numberIndex) else { return nil }
        return Int(components[numberIndex])
    }
}

private extension Array where Element == InteractiveStepOutput {
    func uniquedByIDKeepingLast() -> [InteractiveStepOutput] {
        var orderedIDs: [InteractiveStepOutput.ID] = []
        var outputsByID: [InteractiveStepOutput.ID: InteractiveStepOutput] = [:]
        for output in self {
            if outputsByID[output.id] == nil {
                orderedIDs.append(output.id)
            }
            outputsByID[output.id] = output
        }
        return orderedIDs.compactMap { outputsByID[$0] }
    }
}
