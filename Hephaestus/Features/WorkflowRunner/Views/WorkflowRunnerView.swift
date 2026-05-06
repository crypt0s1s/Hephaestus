import AnvilTheme
import AnvilUI
import AppKit
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
        VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
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
            .padding(.horizontal, theme.spacing.roomy)
            .padding(.top, theme.spacing.roomy)

            if model.state.projects.isEmpty {
                AnvilEmptyState(
                    title: "No projects",
                    message: "Select a project folder to run a workflow.",
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.compact) {
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
                    .padding(.horizontal, theme.spacing.cozy)
                    .padding(.bottom, theme.spacing.roomy)
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
                AnvilEmptyState(
                    title: "Select a project",
                    message: "Choose a folder from the sidebar to run a workflow.",
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.cozy) {
            VStack(alignment: .leading, spacing: theme.spacing.squishy) {
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
        .padding(.horizontal, theme.spacing.roomy)
        .padding(.vertical, theme.spacing.comfortable)
    }

    private func selectedProjectContent(_ project: WorkflowProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
                AnvilSurface {
                    HStack(spacing: theme.spacing.cozy) {
                        AnvilIconTile(systemName: "point.3.connected.trianglepath.dotted")

                        AnvilStatusPill(model.state.branchName(for: project) ?? "No git branch detected")

                        Spacer()

                        AnvilIconButton(
                            systemName: "arrow.clockwise",
                            accessibilityLabel: "Refresh",
                            help: "Refresh branch"
                        ) {
                            model.refreshSelectedProject()
                        }
                    }
                }

                AnvilPanelSection(title: "Workflows") {
                    VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                        ForEach(model.state.workflows) { workflow in
                            WorkflowRow(
                                workflow: workflow,
                                isExpanded: model.state.isWorkflowExpanded(workflow),
                                isRunning: model.state.isRunning,
                                isActive: model.state.activeWorkflowID == workflow.id,
                                lastRunSucceeded: model.state.lastRunWorkflowID == workflow.id ? model.state.lastRunSucceeded : nil,
                                implementationPlanPath: Binding(
                                    get: { model.state.implementationPlanPath },
                                    set: { model.updateImplementationPlanPath($0) }
                                ),
                                implementationBuildCommand: Binding(
                                    get: { model.state.implementationBuildCommand },
                                    set: { model.updateImplementationBuildCommand($0) }
                                ),
                                externalInputValues: model.state.externalWorkflowInputValues[workflow.id] ?? [:],
                                updateExternalInput: { inputID, value in
                                    model.updateExternalWorkflowInput(
                                        workflowID: workflow.id,
                                        inputID: inputID,
                                        value: value
                                    )
                                },
                                toggleExpansion: {
                                    model.toggleWorkflowExpansion(workflow)
                                },
                                run: {
                                    model.runWorkflow(workflow)
                                }
                            )
                        }

                        if let statusMessage = model.state.statusMessage {
                            AnvilBanner(
                                message: statusMessage,
                                tone: model.state.lastRunSucceeded == false ? .danger : .neutral
                            )
                        }

                        if !model.state.timelineOutput.isEmpty || !model.state.output.isEmpty {
                            WorkflowRunOutput(
                                timeline: model.state.timelineOutput,
                                stepRecords: model.state.stepRecords,
                                fullLog: model.state.output,
                                debugLogURL: model.state.debugLogURL
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(theme.spacing.roomy)
        }
    }
}
