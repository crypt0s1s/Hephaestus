import AnvilTheme
import SwiftUI

struct WorkflowCanvas: View {
    let definition: WorkflowGraphDefinition
    let selectedNodeID: String?
    let selectNode: (String) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                workflowLinks
                ForEach(definition.nodes) { node in
                    WorkflowCanvasNode(
                        node: node,
                        isSelected: node.id == selectedNodeID
                    ) {
                        selectNode(node.id)
                    }
                    .frame(width: 190)
                    .position(x: node.position.x + 95, y: node.position.y + 48)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
            .background(theme.colors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(theme.colors.border, lineWidth: 1)
            }
        }
    }

    private var workflowLinks: some View {
        Path { path in
            let nodesByID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
            for link in definition.links {
                guard let from = nodesByID[link.fromNodeID], let to = nodesByID[link.toNodeID] else {
                    continue
                }
                drawLink(path: &path, from: from, to: to)
            }
        }
        .stroke(theme.colors.accent.opacity(0.45), lineWidth: 2)
    }

    private var canvasWidth: CGFloat {
        CGFloat((definition.nodes.map(\.position.x).max() ?? 700) + 280)
    }

    private var canvasHeight: CGFloat {
        CGFloat((definition.nodes.map(\.position.y).max() ?? 260) + 160)
    }

    private func drawLink(path: inout Path, from: WorkflowNode, to: WorkflowNode) {
        let start = CGPoint(x: from.position.x + 190, y: from.position.y + 48)
        let end = CGPoint(x: to.position.x, y: to.position.y + 48)
        let midX = (start.x + end.x) / 2
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: midX, y: start.y),
            control2: CGPoint(x: midX, y: end.y)
        )
    }
}

private struct WorkflowCanvasNode: View {
    let node: WorkflowNode
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: theme.spacing.squishy) {
                header
                Text(node.title)
                    .font(theme.typography.rowTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                Text(node.role.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(theme.spacing.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.elevatedPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .stroke(isSelected ? theme.colors.accent : theme.colors.border, lineWidth: strokeWidth)
            }
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.accent)
            Spacer()
            Text(node.executionMode.title)
                .font(.caption2)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var strokeWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var icon: String {
        switch node.executionMode {
        case .automatic:
            "gearshape.2"
        case .interactivePause:
            "person.crop.circle.badge.questionmark"
        case .approvalGate:
            "checkmark.seal"
        case .terminalAssisted:
            "terminal"
        case .separateCodexInstance:
            "rectangle.stack.badge.person.crop"
        case .manualOnly:
            "hand.raised"
        }
    }
}
