import AnvilTheme
import SwiftUI

struct WorkflowNodeInspector: View {
    let definition: WorkflowGraphDefinition
    let node: WorkflowNode?
    @ObservedObject var model: WorkflowBuilderModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            header
            loopButton
            if let node {
                nodeEditor(node)
            } else {
                Text("Select a workflow step on the canvas.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
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

    private var header: some View {
        HStack {
            Text("Inspector")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            iconButton("plus", "Add step", action: model.addStep)
            iconButton("link", "Connect to next step", action: model.connectSelectedToNext)
            Button(role: .destructive) {
                model.deleteSelectedNode()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete selected step")
            .disabled(node == nil)
        }
    }

    private var loopButton: some View {
        Button {
            model.wrapAllStepsInLoop()
        } label: {
            Label("Wrap in Loop", systemImage: "repeat")
        }
        .buttonStyle(.bordered)
        .disabled(definition.nodes.isEmpty)
    }

    private func nodeEditor(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.compact) {
            nodeIdentityEditor(node)
            instructionsEditor
            WorkflowCapabilityEditor(model: model)
            WorkflowIOEditor(model: model)
            WorkflowLoopSummary(definition: definition, model: model)
        }
    }

    private func nodeIdentityEditor(_ node: WorkflowNode) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            TextField("Step title", text: selectedTitle)
                .textFieldStyle(.roundedBorder)
            Picker("Role", selection: selectedRole) {
                ForEach(WorkflowStepRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            Picker("Mode", selection: selectedMode) {
                ForEach(WorkflowExecutionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Picker("Actor", selection: selectedActor(fallback: node.actorID)) {
                ForEach(definition.actors) { actor in
                    Text(actor.displayName).tag(actor.id)
                }
            }
        }
    }

    private var instructionsEditor: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text("Instructions")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            TextEditor(text: selectedInstructions)
                .font(theme.typography.body)
                .frame(height: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                        .stroke(theme.colors.border, lineWidth: 1)
                }
        }
    }

    private var selectedTitle: Binding<String> {
        Binding(
            get: { model.state.selectedNode?.title ?? "" },
            set: { model.updateSelectedNodeTitle($0) }
        )
    }

    private var selectedRole: Binding<WorkflowStepRole> {
        Binding(
            get: { model.state.selectedNode?.role ?? .automatedExecution },
            set: { model.updateSelectedNodeRole($0) }
        )
    }

    private var selectedMode: Binding<WorkflowExecutionMode> {
        Binding(
            get: { model.state.selectedNode?.executionMode ?? .automatic },
            set: { model.updateSelectedNodeExecutionMode($0) }
        )
    }

    private var selectedInstructions: Binding<String> {
        Binding(
            get: { model.state.selectedNode?.instructions ?? "" },
            set: { model.updateSelectedNodeInstructions($0) }
        )
    }

    private func selectedActor(fallback: String) -> Binding<String> {
        Binding(
            get: { model.state.selectedNode?.actorID ?? fallback },
            set: { model.updateSelectedNodeActor($0) }
        )
    }

    private func iconButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .help(help)
    }
}
