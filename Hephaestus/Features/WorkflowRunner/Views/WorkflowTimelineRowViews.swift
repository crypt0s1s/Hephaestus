import AnvilTheme
import SwiftUI

struct WorkflowTimelineRow: View {
    let row: TimelineDisplayRow
    let isSelected: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.compact) {
            TimelineStatusIcon(status: row.status)
            TimelineText(row: row)
            Spacer(minLength: theme.spacing.compact)
            TimelineRuntimeLabel(record: row.record)
            TimelineChevron(isVisible: row.isExpandable || row.record != nil, isExpanded: row.isExpanded)
        }
        .padding(.horizontal, theme.spacing.cozy)
        .padding(.vertical, theme.spacing.compact)
        .padding(.leading, CGFloat(row.depth) * 22)
        .background(isSelected ? theme.colors.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineText: View {
    let row: TimelineDisplayRow
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.tiny) {
            Text(row.label)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)

            if let detail = row.detail {
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct TimelineRuntimeLabel: View {
    let record: WorkflowStepRecord?
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if let label = record?.timing?.compactRuntimeLabel(status: record?.status) {
            Text(label)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct TimelineChevron: View {
    let isVisible: Bool
    let isExpanded: Bool
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.colors.textTertiary)
            .opacity(isVisible ? 1 : 0)
    }
}
