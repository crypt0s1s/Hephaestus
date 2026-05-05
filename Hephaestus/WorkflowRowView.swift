import AnvilTheme
import SwiftUI

struct WorkflowRow: View {
    let workflow: WorkflowDefinition
    let isExpanded: Bool
    let isRunning: Bool
    let isActive: Bool
    let lastRunSucceeded: Bool?
    @Binding var implementationPlanPath: String
    @Binding var implementationBuildCommand: String
    let toggleExpansion: () -> Void
    let run: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        WorkflowRowSurface(isExpanded: isExpanded) {
            WorkflowRowHeader(
                workflow: workflow,
                isExpanded: isExpanded,
                isRunning: isRunning,
                isActive: isActive,
                lastRunSucceeded: lastRunSucceeded,
                toggleExpansion: toggleExpansion,
                run: run
            )

            if isExpanded {
                WorkflowExpandedContent(
                    workflow: workflow,
                    planPath: $implementationPlanPath,
                    buildCommand: $implementationBuildCommand
                )
            }
        }
    }
}

private struct WorkflowRowSurface<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: Content
    @Environment(\.anvilTheme) private var theme

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
    let isRunning: Bool
    let isActive: Bool
    let lastRunSucceeded: Bool?
    let toggleExpansion: () -> Void
    let run: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.medium) {
            WorkflowDisclosureButton(
                title: workflow.title,
                isExpanded: isExpanded,
                action: toggleExpansion
            )

            WorkflowKindIcon(kind: workflow.kind)
            WorkflowTitleBlock(title: workflow.title, subtitle: workflow.subtitle)
            Spacer(minLength: theme.spacing.medium)
            WorkflowStateBadge(isActive: isActive, lastRunSucceeded: lastRunSucceeded)
            runButton
        }
        .padding(.horizontal, theme.spacing.medium)
        .padding(.vertical, theme.spacing.small)
    }

    private var runButton: some View {
        Button(action: run) {
            Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.colors.accent)
        .disabled(isRunning)
    }
}

private struct WorkflowDisclosureButton: View {
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
    }
}

private struct WorkflowKindIcon: View {
    let kind: WorkflowKind
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.colors.accent)
            .frame(width: 34, height: 34)
            .background(theme.colors.selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    }

    private var systemImage: String {
        kind == .implementationReviewLoop ? "point.3.connected.trianglepath.dotted" : "doc.text"
    }
}

private struct WorkflowTitleBlock: View {
    let title: String
    let subtitle: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxSmall) {
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
    let isActive: Bool
    let lastRunSucceeded: Bool?
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Group {
            if isActive {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Running")
            } else if let lastRunSucceeded {
                Image(systemName: lastRunSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(lastRunSucceeded ? theme.colors.success : theme.colors.danger)
                    .accessibilityLabel(lastRunSucceeded ? "Last run completed" : "Last run failed")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct WorkflowExpandedContent: View {
    let workflow: WorkflowDefinition
    @Binding var planPath: String
    @Binding var buildCommand: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            configuration
            WorkflowStepList(steps: workflow.steps)
        }
        .padding(.leading, 72)
        .padding(.trailing, theme.spacing.medium)
        .padding(.bottom, theme.spacing.medium)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var configuration: some View {
        if workflow.kind == .implementationReviewLoop {
            ImplementationReviewConfiguration(
                planPath: $planPath,
                buildCommand: $buildCommand
            )
        }
    }
}

private struct WorkflowStepList: View {
    let steps: [WorkflowStepDefinition]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                WorkflowStepRow(step: step, stepNumber: index + 1)
            }
        }
    }
}

private struct ImplementationReviewConfiguration: View {
    @Binding var planPath: String
    @Binding var buildCommand: String
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("Configuration")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

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

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(WorkflowInputTextFieldStyle())
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct WorkflowInputTextFieldStyle: TextFieldStyle {
    @Environment(\.anvilTheme) private var theme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(theme.colors.textPrimary)
            .font(theme.typography.body)
            .padding(.horizontal, theme.spacing.medium)
            .padding(.vertical, theme.spacing.small)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
    }
}

private struct WorkflowStepRow: View {
    let step: WorkflowStepDefinition
    let stepNumber: Int
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            WorkflowStepNumber(number: stepNumber)
            WorkflowTitleBlock(title: step.title, subtitle: step.subtitle)
        }
        .padding(.vertical, theme.spacing.xxSmall)
    }
}

private struct WorkflowStepNumber: View {
    let number: Int
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: 22, height: 22)
            .background(theme.colors.panelBackground)
            .clipShape(Circle())
    }
}
