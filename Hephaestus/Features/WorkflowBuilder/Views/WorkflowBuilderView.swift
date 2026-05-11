import AnvilTheme
import AnvilUI
import SwiftUI

struct WorkflowBuilderView: View {
    let project: WorkflowProject
    @ObservedObject var model: WorkflowBuilderModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        AnvilPanelSection(title: "Workflow Builder") {
            VStack(alignment: .leading, spacing: theme.spacing.cozy) {
                builderToolbar

                if let definition = model.state.definition {
                    workflowMetadata(definition)
                    builderWorkspace(definition)
                    validationSummary
                    normalizedDefinitionPreview
                }
            }
        }
        .onAppear {
            model.setProject(project)
        }
        .onChange(of: project.id) { _, _ in
            model.setProject(project)
        }
    }

    private var builderToolbar: some View {
        HStack(spacing: theme.spacing.compact) {
            Button {
                model.createEmptyWorkflow()
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(WorkflowBuilderPattern.allCases) { pattern in
                    Button(pattern.title) {
                        model.insertPattern(pattern)
                    }
                }
            } label: {
                Label("Pattern", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.bordered)

            if !model.state.savedDefinitions.isEmpty {
                Menu {
                    ForEach(model.state.savedDefinitions) { definition in
                        Button(definition.metadata.title) {
                            model.reopen(definition.id)
                        }
                    }
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                model.validate()
            } label: {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)

            Button {
                model.save(project: project)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)
        }
    }

    private func workflowMetadata(_ definition: WorkflowGraphDefinition) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            TextField(
                "Workflow title",
                text: Binding(
                    get: { model.state.definition?.metadata.title ?? "" },
                    set: { model.updateTitle($0) }
                )
            )
            .font(theme.typography.sectionTitle)
            .textFieldStyle(.plain)

            TextField(
                "Workflow summary",
                text: Binding(
                    get: { model.state.definition?.metadata.summary ?? "" },
                    set: { model.updateSummary($0) }
                )
            )
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.textSecondary)
            .textFieldStyle(.plain)

            HStack(spacing: theme.spacing.squishy) {
                WorkflowBuilderPill(text: "\(definition.nodes.count) steps")
                WorkflowBuilderPill(text: "\(definition.links.count) links")
                WorkflowBuilderPill(text: "\(definition.loops.count) loops")
                if let result = model.state.validationResult {
                    WorkflowBuilderPill(
                        text: result.hasBlockingIssues ? "Not executable" : "Valid",
                        tone: result.hasBlockingIssues ? .danger : .success
                    )
                }
            }
        }
    }

    private func builderWorkspace(_ definition: WorkflowGraphDefinition) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.cozy) {
            WorkflowCanvas(
                definition: definition,
                selectedNodeID: model.state.selectedNodeID,
                selectNode: model.selectNode
            )
            .frame(minHeight: 360)

            WorkflowNodeInspector(
                definition: definition,
                node: model.state.selectedNode,
                model: model
            )
            .frame(width: 320)
        }
    }

    @ViewBuilder
    private var validationSummary: some View {
        if let result = model.state.validationResult {
            VStack(alignment: .leading, spacing: theme.spacing.compact) {
                HStack {
                    Text("Validation")
                        .font(theme.typography.rowTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Text(result.hasBlockingIssues ? "Blocking issues" : "Ready for runtime design")
                        .font(theme.typography.caption)
                        .foregroundStyle(
                            result.hasBlockingIssues ? theme.colors.danger : theme.colors.success)
                }

                if result.issues.isEmpty {
                    Text("No validation issues.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    ForEach(result.issues) { issue in
                        HStack(alignment: .top, spacing: theme.spacing.compact) {
                            Image(
                                systemName: issue.severity == .error
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                                .foregroundStyle(issue.severity == .error ? theme.colors.danger : theme.colors.warning)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.message)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textPrimary)
                                Text(issue.location.label)
                                    .font(.caption2)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                    }
                }

                if let status = model.state.statusMessage {
                    AnvilBanner(message: status, tone: result.hasBlockingIssues ? .danger : .neutral)
                }
            }
            .padding(theme.spacing.cozy)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
        }
    }

    private var normalizedDefinitionPreview: some View {
        DisclosureGroup {
            ScrollView(.horizontal) {
                Text(model.normalizedDefinitionJSON())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)
                    .textSelection(.enabled)
                    .padding(.top, theme.spacing.compact)
            }
            .frame(maxHeight: 220)
        } label: {
            Label("Normalized definition", systemImage: "curlybraces")
                .font(theme.typography.rowTitle)
        }
    }
}
