import AnvilTheme
import SwiftUI

struct WorkflowStepRow: View {
    let step: WorkflowStepDefinition
    let stepNumber: Int
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.compact) {
            WorkflowStepNumber(number: stepNumber)
            WorkflowTitleBlock(title: step.title, subtitle: step.subtitle)
        }
        .padding(.vertical, theme.spacing.tiny)
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
