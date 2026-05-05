import AnvilTheme
import AnvilUI
import SwiftUI

struct WorkflowRunnerView: View {
    @ObservedObject var model: WorkflowRunnerModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ProjectSidebar(model: model)
                .frame(width: sidebarWidth)

            Divider()

            WorkflowDetail(model: model)
        }
        .frame(minWidth: minWindowWidth, minHeight: minWindowHeight)
        .background(theme.colors.windowBackground)
    }

    private var sidebarWidth: CGFloat { 300 }
    private var minWindowWidth: CGFloat { 920 }
    private var minWindowHeight: CGFloat { 560 }
}

private struct ProjectSidebar: View {
    @ObservedObject var model: WorkflowRunnerModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            HStack {
                Text("Projects")
                    .font(theme.typography.sectionTitle)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer()

                AnvilIconButton(
                    systemName: "folder.badge.plus",
                    accessibilityLabel: "Select project",
                    help: "Select project folder"
                ) {
                    model.selectProjectFolder()
                }
            }
            .padding(.horizontal, theme.spacing.xLarge)
            .padding(.top, theme.spacing.xLarge)

            if model.state.projects.isEmpty {
                ContentUnavailableView(
                    "No projects",
                    systemImage: "folder",
                    description: Text("Select a project folder to run a workflow.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.small) {
                        ForEach(model.state.projects) { project in
                            ProjectRow(
                                project: project,
                                isSelected: project.id == model.state.selectedProjectID,
                                branchName: model.state.branchName(for: project)
                            ) {
                                model.selectProject(project)
                            }
                        }
                    }
                    .padding(.horizontal, theme.spacing.medium)
                    .padding(.bottom, theme.spacing.xLarge)
                }
            }
        }
        .background(theme.colors.sidebarBackground)
    }
}

private struct ProjectRow: View {
    let project: WorkflowProject
    let isSelected: Bool
    let branchName: String?
    let select: () -> Void

    var body: some View {
        AnvilSidebarRow(
            title: project.name,
            subtitle: branchName.map { "$\($0)" } ?? "No branch",
            systemImage: "folder",
            isSelected: isSelected,
            action: select
        )
    }
}

private struct WorkflowDetail: View {
    @ObservedObject var model: WorkflowRunnerModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let project = model.state.selectedProject {
                selectedProjectContent(project)
            } else {
                ContentUnavailableView(
                    "Select a project",
                    systemImage: "folder",
                    description: Text("Choose a folder from the sidebar to run a workflow.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.medium) {
            VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
                Text(model.state.selectedProject?.name ?? "Workflow Runner")
                    .font(theme.typography.pageTitle)
                    .foregroundStyle(theme.colors.textPrimary)

                Text(model.state.selectedProject?.path ?? "Run headless workflows against a local project folder.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.selectProjectFolder()
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, theme.spacing.xLarge)
        .padding(.vertical, theme.spacing.large)
    }

    private func selectedProjectContent(_ project: WorkflowProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                HStack(spacing: theme.spacing.medium) {
                    Label(
                        model.state.branchName(for: project) ?? "No git branch detected",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)

                    Spacer()

                    AnvilIconButton(
                        systemName: "arrow.clockwise",
                        accessibilityLabel: "Refresh",
                        help: "Refresh branch"
                    ) {
                        model.refreshSelectedProject()
                    }
                }

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    ForEach(model.state.workflows) { workflow in
                        WorkflowRow(
                            workflow: workflow,
                            isExpanded: model.state.isWorkflowExpanded(workflow),
                            isRunning: model.state.isRunning,
                            toggleExpansion: {
                                model.toggleWorkflowExpansion(workflow)
                            },
                            run: {
                                model.runHelloWorldWorkflow()
                            }
                        )
                    }

                    if let statusMessage = model.state.statusMessage {
                        AnvilStatusText(
                            statusMessage,
                            tone: model.state.lastRunSucceeded == false ? .danger : .neutral
                        )
                    }

                    if !model.state.output.isEmpty {
                        AnvilLogSurface(model.state.output)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(theme.spacing.xLarge)
        }
    }
}

private struct WorkflowRow: View {
    let workflow: WorkflowDefinition
    let isExpanded: Bool
    let isRunning: Bool
    let toggleExpansion: () -> Void
    let run: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        AnvilDisclosureRow(
            title: workflow.title,
            subtitle: workflow.subtitle,
            systemImage: "doc.badge.plus",
            isExpanded: isExpanded,
            onToggle: toggleExpansion
        ) {
            Button(action: run) {
                Label(isRunning ? "Running" : "Run", systemImage: isRunning ? "hourglass" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)
            .disabled(isRunning)
        } content: {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepRow(step: step, stepNumber: index + 1)
                }
            }
        }
    }
}

private struct WorkflowStepRow: View {
    let step: WorkflowStepDefinition
    let stepNumber: Int
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.medium) {
            Text("\(stepNumber)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: stepBadgeSize, height: stepBadgeSize)
                .background(theme.colors.selectionBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
                Text(step.title)
                    .font(theme.typography.body.weight(.medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(step.subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, theme.spacing.xxSmall)
    }

    private var stepBadgeSize: CGFloat { 20 }
}
