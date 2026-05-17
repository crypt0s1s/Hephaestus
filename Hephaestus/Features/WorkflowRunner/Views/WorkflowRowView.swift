import AnvilTheme
import AnvilUI
import SwiftUI

struct WorkflowRow: View {
    let workflow: WorkflowDefinition
    let isExpanded: Bool
    let isRunDisabled: Bool
    let isActive: Bool
    let activeActivity: ActiveWorkflowActivity?
    let lastRunSucceeded: Bool?
    @Binding var implementationPlanPath: String
    @Binding var implementationBuildCommand: String
    let externalInputValues: [String: String]
    let updateExternalInput: (String, String) -> Void
    let toggleExpansion: () -> Void
    let run: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        WorkflowRowSurface(isExpanded: isExpanded) {
            WorkflowRowHeader(
                workflow: workflow,
                isExpanded: isExpanded,
                isRunDisabled: isRunDisabled,
                isActive: isActive,
                activeActivity: activeActivity,
                lastRunSucceeded: lastRunSucceeded,
                toggleExpansion: toggleExpansion,
                run: run
            )

            if isExpanded {
                WorkflowExpandedContent(
                    workflow: workflow,
                    planPath: $implementationPlanPath,
                    buildCommand: $implementationBuildCommand,
                    externalInputValues: externalInputValues,
                    updateExternalInput: updateExternalInput
                )
            }
        }
    }
}

private struct WorkflowRowSurface<Content: View>: View {
    let isExpanded: Bool
    let content: Content
    @Environment(\.anvilTheme) private var theme

    init(isExpanded: Bool, @ViewBuilder content: () -> Content) {
        self.isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var borderColor: Color {
        isExpanded ? theme.colors.accent.opacity(0.24) : theme.colors.border
    }
}

private struct WorkflowRowHeader: View {
    let workflow: WorkflowDefinition
    let isExpanded: Bool
    let isRunDisabled: Bool
    let isActive: Bool
    let activeActivity: ActiveWorkflowActivity?
    let lastRunSucceeded: Bool?
    let toggleExpansion: () -> Void
    let run: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.cozy) {
            WorkflowDisclosureButton(
                workflowID: workflow.id,
                title: workflow.title,
                isExpanded: isExpanded,
                action: toggleExpansion
            )

            WorkflowKindIcon(systemImage: workflow.systemImage)
            WorkflowTitleBlock(title: workflow.title, subtitle: workflow.subtitle)
            Spacer(minLength: theme.spacing.cozy)
            WorkflowStateBadge(
                workflowID: workflow.id,
                isActive: isActive,
                activeActivity: activeActivity,
                lastRunSucceeded: lastRunSucceeded
            )
            runButton
        }
        .padding(.horizontal, theme.spacing.cozy)
        .padding(.vertical, theme.spacing.compact)
    }

    private var runButton: some View {
        AnvilActionButton(
            configuration: AnvilActionButtonConfiguration(
                title: "Run",
                systemImage: "play.fill",
                style: .primary,
                isDisabled: isRunDisabled,
                accessibilityLabel: "Run \(workflow.title)",
                accessibilityIdentifier: "workflow.run.\(workflow.id)",
                help: isRunDisabled ? "A workflow is already active." : "Run \(workflow.title)"
            ),
            action: run
        )
    }
}

private struct WorkflowDisclosureButton: View {
    let workflowID: WorkflowDefinition.ID
    let title: String
    let isExpanded: Bool
    let action: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        .accessibilityIdentifier("workflow.disclosure.\(workflowID)")
    }
}

private struct WorkflowKindIcon: View {
    let systemImage: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.colors.accent)
            .frame(width: 34, height: 34)
            .background(theme.colors.selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    }
}

struct WorkflowTitleBlock: View {
    let title: String
    let subtitle: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(title)
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text(subtitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
        }
    }
}

private struct WorkflowStateBadge: View {
    let workflowID: WorkflowDefinition.ID
    let isActive: Bool
    let activeActivity: ActiveWorkflowActivity?
    let lastRunSucceeded: Bool?

    var body: some View {
        Group {
            if isActive {
                activeBadge
            } else if let lastRunSucceeded {
                AnvilStatusIndicator(
                    state: lastRunSucceeded ? .succeeded : .failed,
                    accessibilityLabel: lastRunSucceeded ? "Last run completed" : "Last run failed"
                )
            } else {
                AnvilStatusIndicator(state: .idle)
            }
        }
        .frame(width: 132, alignment: .trailing)
        .frame(minHeight: 22)
        .accessibilityIdentifier("workflow.stateBadge.\(workflowID)")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var activeBadge: some View {
        switch activeActivity {
        case .running:
            AnvilStatusIndicator(state: .running, label: "Running")
        case .waitingForInteraction:
            WorkflowActivityPill(
                title: "Waiting for draft",
                systemImage: "pause.circle.fill"
            )
        case .waitingForUserReview:
            WorkflowActivityPill(
                title: "Review needed",
                systemImage: "person.crop.circle.badge.checkmark"
            )
        case nil:
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private var accessibilityValue: String {
        if isActive {
            switch activeActivity {
            case .running:
                return "running"
            case .waitingForInteraction:
                return "waiting for interaction"
            case .waitingForUserReview:
                return "waiting for user review"
            case nil:
                return "active"
            }
        }
        if let lastRunSucceeded {
            return lastRunSucceeded ? "succeeded" : "failed"
        }
        return "idle"
    }
}

private struct WorkflowExpandedContent: View {
    let workflow: WorkflowDefinition
    @Binding var planPath: String
    @Binding var buildCommand: String
    let externalInputValues: [String: String]
    let updateExternalInput: (String, String) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            configuration
            WorkflowStepList(steps: workflow.steps)
        }
        .padding(.leading, 72)
        .padding(.trailing, theme.spacing.cozy)
        .padding(.bottom, theme.spacing.cozy)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var configuration: some View {
        switch workflow.configuration {
        case .none:
            EmptyView()
        case .implementationReview:
            ImplementationReviewConfiguration(
                planPath: $planPath,
                buildCommand: $buildCommand
            )
        case .inputs:
            WorkflowInputsConfiguration(
                workflowID: workflow.id,
                inputs: workflow.inputs,
                values: externalInputValues,
                updateInput: updateExternalInput
            )
        }
    }
}

private struct WorkflowInputsConfiguration: View {
    let workflowID: WorkflowDefinition.ID
    let inputs: [WorkflowInputDefinition]
    let values: [String: String]
    let updateInput: (String, String) -> Void

    var body: some View {
        AnvilFieldSection(title: "Inputs") {
            ForEach(inputs, id: \.id) { input in
                WorkflowInputField(
                    placeholder: input.label,
                    text: Binding(
                        get: { values[input.id] ?? input.defaultValue ?? "" },
                        set: { updateInput(input.id, $0) }
                    ),
                    accessibilityLabel: input.label,
                    accessibilityIdentifier: "workflow.input.\(workflowID).\(input.id)"
                )
            }
        }
    }
}

private struct WorkflowStepList: View {
    let steps: [WorkflowStepDefinition]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                WorkflowStepRow(step: step, stepNumber: index + 1)
            }
        }
    }
}

private struct ImplementationReviewConfiguration: View {
    @Binding var planPath: String
    @Binding var buildCommand: String

    var body: some View {
        AnvilFieldSection(title: "Configuration") {
            WorkflowInputField(
                placeholder: "Project-relative plan path, for example docs/plans/my-plan.md",
                text: $planPath,
                accessibilityLabel: "Implementation plan path"
            )

            WorkflowInputField(
                placeholder: "Build command",
                text: $buildCommand,
                accessibilityLabel: "Build command"
            )
        }
    }
}

private struct WorkflowInputField: View {
    let placeholder: String
    @Binding var text: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String?

    var body: some View {
        AnvilTextField(
            text: $text,
            configuration: AnvilTextFieldConfiguration(
                placeholder: placeholder,
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }
}
