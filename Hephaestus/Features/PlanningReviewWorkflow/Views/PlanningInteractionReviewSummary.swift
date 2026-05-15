import AnvilTheme
import AnvilUI
import SwiftUI

struct PlanningInteractionReviewSummary: View {
    let state: PlanningInteractionState
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if shouldShowSummary {
            AnvilList(
                configuration: AnvilListConfiguration(
                    style: .panel,
                    spacing: theme.spacing.cozy,
                    contentPadding: theme.spacing.cozy,
                    accessibilityIdentifier: "planning.reviewSummary"
                )
            ) {
                VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                    PlanningInteractionReviewSummaryHeader(
                        title: summaryTitle,
                        subtitle: summarySubtitle
                    )

                    PlanningInteractionReviewArtifactIndex(
                        latestOutput: latestReviewedOutput,
                        cycles: cycles
                    )

                    if let latestOutput = latestReviewedOutput {
                        PlanningInteractionArtifactRow(
                            title: latestTitle,
                            badge: latestBadge,
                            output: latestOutput,
                            identifier: "planning.latestReviewedPlan"
                        )
                    }

                    PlanningInteractionReviewCycleList(cycles: cycles)
                }
            }
        }
    }

    private var shouldShowSummary: Bool {
        (state.canResolveCompletedOutput || state.phase == .accepted) && !outputs.isEmpty
    }

    private var summaryTitle: String {
        state.phase == .accepted ? "Accepted handoff" : "Review handoff"
    }

    private var summarySubtitle: String {
        state.phase == .accepted
            ? "The final reviewed plan has been accepted."
            : "Review the latest plan and cycle artifacts before choosing the next action."
    }

    private var latestTitle: String {
        state.phase == .accepted ? "Final accepted plan" : "Latest reviewed plan"
    }

    private var latestBadge: String {
        state.phase == .accepted ? "Final" : "Current"
    }

    private var outputs: [InteractiveStepOutput] {
        (
            [state.submittedOutput, state.latestResolvedOutput].compactMap { $0 }
                + state.relatedOutputs
        )
        .uniquedByID()
    }

    private var latestReviewedOutput: InteractiveStepOutput? {
        outputs.last { $0.reviewArtifactRole == .plan }
            ?? state.latestResolvedOutput
            ?? state.submittedOutput
            ?? outputs.last
    }

    private var cycles: [PlanningInteractionReviewCycleArtifacts] {
        PlanningInteractionReviewCycleArtifacts.group(outputs: outputs)
    }
}

private struct PlanningInteractionReviewSummaryHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Text(subtitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}

private struct PlanningInteractionReviewCycleList: View {
    let cycles: [PlanningInteractionReviewCycleArtifacts]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if !cycles.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.compact) {
                Text("Cycle history")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)

                ForEach(cycles) { cycle in
                    PlanningInteractionReviewCycleSection(cycle: cycle)
                }
            }
        }
    }
}

private struct PlanningInteractionReviewArtifactIndex: View {
    let latestOutput: InteractiveStepOutput?
    let cycles: [PlanningInteractionReviewCycleArtifacts]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if !markers.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.tiny) {
                Text("Available artifacts")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)

                ForEach(markers) { marker in
                    Text(marker.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityIdentifier(marker.identifier)
                }
            }
        }
    }

    private var markers: [PlanningInteractionReviewArtifactMarker] {
        var markers: [PlanningInteractionReviewArtifactMarker] = []
        if latestOutput != nil {
            markers.append(
                PlanningInteractionReviewArtifactMarker(
                    title: "Latest reviewed plan",
                    identifier: "planning.latestReviewedPlan"
                )
            )
        }
        for cycle in cycles {
            if cycle.feedback != nil {
                markers.append(
                    PlanningInteractionReviewArtifactMarker(
                        title: "Cycle \(cycle.number) review feedback",
                        identifier: "planning.reviewCycle.\(cycle.number).feedback"
                    )
                )
            }
            if cycle.plan != nil {
                markers.append(
                    PlanningInteractionReviewArtifactMarker(
                        title: "Cycle \(cycle.number) planner response plan",
                        identifier: "planning.reviewCycle.\(cycle.number).plan"
                    )
                )
            }
        }
        return markers
    }
}

private struct PlanningInteractionReviewArtifactMarker: Identifiable {
    let title: String
    let identifier: String

    var id: String {
        identifier
    }
}

private struct PlanningInteractionReviewCycleSection: View {
    let cycle: PlanningInteractionReviewCycleArtifacts
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            Text("Cycle \(cycle.number)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            if let feedback = cycle.feedback {
                PlanningInteractionArtifactRow(
                    title: "Review feedback",
                    badge: "Feedback",
                    output: feedback,
                    identifier: "planning.reviewCycle.\(cycle.number).feedback"
                )
            }

            if let plan = cycle.plan {
                PlanningInteractionArtifactRow(
                    title: "Planner response plan",
                    badge: "Plan",
                    output: plan,
                    identifier: "planning.reviewCycle.\(cycle.number).plan"
                )
            }
        }
        .padding(.leading, theme.spacing.compact)
    }
}

private struct PlanningInteractionArtifactRow: View {
    let title: String
    let badge: String
    let output: InteractiveStepOutput
    let identifier: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            HStack(spacing: theme.spacing.compact) {
                Text(title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityIdentifier(identifier)

                Text(badge)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, theme.spacing.compact)
                    .padding(.vertical, 2)
                    .background(theme.colors.selectionBackground)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))

                Spacer()
            }

            if let summary = output.summary {
                Text(summary)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Text(pathText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.compact)
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        }
    }

    private var pathText: String {
        output.artifact.projectRelativePath ?? output.summary ?? output.artifact.title
    }
}

private struct PlanningInteractionReviewCycleArtifacts: Identifiable {
    let number: Int
    var feedback: InteractiveStepOutput?
    var plan: InteractiveStepOutput?

    var id: Int {
        number
    }

    static func group(outputs: [InteractiveStepOutput]) -> [PlanningInteractionReviewCycleArtifacts] {
        var cycles: [Int: PlanningInteractionReviewCycleArtifacts] = [:]
        for output in outputs {
            guard let cycleNumber = output.reviewCycleNumber else { continue }
            var cycle = cycles[cycleNumber] ?? PlanningInteractionReviewCycleArtifacts(number: cycleNumber)
            switch output.reviewArtifactRole {
            case .feedback:
                cycle.feedback = output
            case .plan:
                cycle.plan = output
            case .other:
                break
            }
            cycles[cycleNumber] = cycle
        }
        return cycles.values.sorted { $0.number < $1.number }
    }
}

private enum PlanningInteractionReviewArtifactRole {
    case feedback
    case plan
    case other
}

private extension InteractiveStepOutput {
    var reviewCycleNumber: Int? {
        artifact.projectRelativePath?.reviewCycleNumber
    }

    var reviewArtifactRole: PlanningInteractionReviewArtifactRole {
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
    func uniquedByID() -> [InteractiveStepOutput] {
        var seenIDs: Set<InteractiveStepOutput.ID> = []
        return filter { output in
            seenIDs.insert(output.id).inserted
        }
    }
}
