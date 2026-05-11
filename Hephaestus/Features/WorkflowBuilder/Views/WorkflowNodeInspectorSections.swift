import AnvilTheme
import SwiftUI

struct WorkflowCapabilityEditor: View {
    @ObservedObject var model: WorkflowBuilderModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text("Capabilities")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            TextField("Tools, comma-separated", text: tools)
                .textFieldStyle(.roundedBorder)
            TextField("Skills, comma-separated", text: skills)
                .textFieldStyle(.roundedBorder)
            TextField("MCP servers, comma-separated", text: mcpServers)
                .textFieldStyle(.roundedBorder)
            Picker("Files", selection: filesystemPolicy) {
                ForEach(WorkflowFilesystemPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            Picker("Network", selection: networkPolicy) {
                ForEach(WorkflowNetworkPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
        }
    }

    private var tools: Binding<String> {
        Binding(
            get: { model.state.selectedNode?.capabilityScope.allowedTools.joined(separator: ", ") ?? "" },
            set: { model.updateSelectedNodeToolList($0) }
        )
    }

    private var skills: Binding<String> {
        Binding(
            get: { model.state.selectedNode?.capabilityScope.allowedSkills.joined(separator: ", ") ?? "" },
            set: { model.updateSelectedNodeSkillList($0) }
        )
    }

    private var mcpServers: Binding<String> {
        Binding(
            get: { model.state.selectedNode?.capabilityScope.allowedMCPServers.joined(separator: ", ") ?? "" },
            set: { model.updateSelectedNodeMCPList($0) }
        )
    }

    private var filesystemPolicy: Binding<WorkflowFilesystemPolicy> {
        Binding(
            get: { model.state.selectedNode?.capabilityScope.filesystemPolicy ?? .readOnly },
            set: { model.updateSelectedNodeFilesystemPolicy($0) }
        )
    }

    private var networkPolicy: Binding<WorkflowNetworkPolicy> {
        Binding(
            get: { model.state.selectedNode?.capabilityScope.networkPolicy ?? .disabled },
            set: { model.updateSelectedNodeNetworkPolicy($0) }
        )
    }
}

struct WorkflowIOEditor: View {
    @ObservedObject var model: WorkflowBuilderModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text("IO")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            TextField("Inputs as Name:kind, comma-separated", text: inputs)
                .textFieldStyle(.roundedBorder)
            TextField("Outputs as Name:kind, comma-separated", text: outputs)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var inputs: Binding<String> {
        Binding(
            get: { Self.ioList(model.state.selectedNode?.inputs ?? []) },
            set: { model.updateSelectedNodeInputs($0) }
        )
    }

    private var outputs: Binding<String> {
        Binding(
            get: { Self.ioList(model.state.selectedNode?.outputs ?? []) },
            set: { model.updateSelectedNodeOutputs($0) }
        )
    }

    private static func ioList(_ declarations: [WorkflowIODeclaration]) -> String {
        declarations
            .map { "\($0.name):\($0.valueKind.rawValue)" }
            .joined(separator: ", ")
    }
}

struct WorkflowLoopSummary: View {
    let definition: WorkflowGraphDefinition
    @ObservedObject var model: WorkflowBuilderModel
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text("Loops")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            if let firstLoop = definition.loops.first {
                loopEditor(firstLoop)
            } else {
                Text("No loops configured.")
                    .font(.caption2)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private func loopEditor(_ firstLoop: WorkflowLoop) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.squishy) {
            Text(firstLoop.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
            Picker("Stop", selection: stopPreset) {
                ForEach(WorkflowLoopStopPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Stepper("Max iterations: \(firstLoop.stopCondition.maxIterations ?? 1)", value: maxIterations, in: 1...10)
                .disabled(WorkflowLoopStopPreset(condition: firstLoop.stopCondition) == .manual)
        }
    }

    private var stopPreset: Binding<WorkflowLoopStopPreset> {
        Binding(
            get: {
                let condition = model.state.definition?.loops.first?.stopCondition ?? .maxIterations(3)
                return WorkflowLoopStopPreset(condition: condition)
            },
            set: { model.updateFirstLoopStopPreset($0) }
        )
    }

    private var maxIterations: Binding<Int> {
        Binding(
            get: { model.state.definition?.loops.first?.stopCondition.maxIterations ?? 1 },
            set: { model.updateFirstLoopMaxIterations($0) }
        )
    }
}
