import AnvilTheme
import SwiftUI

struct WorkflowBuilderPill: View {
    enum Tone {
        case neutral
        case success
        case danger
    }

    let text: String
    var tone: Tone = .neutral
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, theme.spacing.compact)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            theme.colors.textSecondary
        case .success:
            theme.colors.success
        case .danger:
            theme.colors.danger
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}

extension WorkflowValidationLocation {
    var label: String {
        switch self {
        case .workflow:
            "Workflow"
        case .node(let id):
            "Step \(id)"
        case .link(let id):
            "Link \(id)"
        case .loop(let id):
            "Loop \(id)"
        case .actor(let id):
            "Actor \(id)"
        }
    }
}
