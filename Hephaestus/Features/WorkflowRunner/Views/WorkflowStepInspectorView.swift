import AnvilTheme
import AppKit
import SwiftUI

struct WorkflowStepInspector: View {
  let record: WorkflowStepRecord
  let debugLogURL: URL?
  let close: () -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WorkflowStepInspectorHeader(record: record, close: close)
      Divider()
      WorkflowStepInspectorContent(record: record, debugLogURL: debugLogURL)
    }
    .frame(minHeight: 360, maxHeight: 620)
    .inspectorPanelStyle()
  }
}

private struct WorkflowStepInspectorHeader: View {
  let record: WorkflowStepRecord
  let close: () -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    HStack(alignment: .center, spacing: theme.spacing.compact) {
      TimelineStatusIcon(status: TimelineDisplayStatus(recordStatus: record.status))
      WorkflowStepInspectorTitle(record: record)
      Spacer()
      WorkflowStepInspectorCloseButton(close: close)
    }
    .padding(theme.spacing.cozy)
  }
}

private struct WorkflowStepInspectorTitle: View {
  let record: WorkflowStepRecord
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.tiny) {
      Text(record.title)
        .font(theme.typography.rowTitle)
        .foregroundStyle(theme.colors.textPrimary)

      Text(statusLabel)
        .font(theme.typography.caption)
        .foregroundStyle(statusColor)
    }
  }

  private var statusLabel: String {
    switch record.status {
    case .pending:
      return "Pending"
    case .inProgress:
      return "In progress"
    case .succeeded:
      return "Completed"
    case .needsFix:
      return "Needs fix"
    case .failed:
      return "Needs attention"
    }
  }

  private var statusColor: Color {
    switch record.status {
    case .pending:
      return theme.colors.textTertiary
    case .inProgress:
      return theme.colors.accent
    case .succeeded:
      return theme.colors.success
    case .needsFix:
      return theme.colors.warning
    case .failed:
      return theme.colors.danger
    }
  }
}

private struct WorkflowStepInspectorCloseButton: View {
  let close: () -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    Button(action: close) {
      Image(systemName: "xmark")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .foregroundStyle(theme.colors.textSecondary)
    .accessibilityLabel("Close step details")
  }
}

private struct WorkflowStepInspectorContent: View {
  let record: WorkflowStepRecord
  let debugLogURL: URL?
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.spacing.cozy) {
        InspectorRuntimeSection(record: record)
        InspectorSection(title: "What happened", text: record.summary)
        InspectorOptionalSection(
          title: "Result", text: WorkflowStepOutputSummary(record: record).text)
        InspectorOptionalDisclosureSection(title: "Prompt", text: record.inputPreview)
        InspectorOptionalDisclosureSection(title: "Raw output", text: record.outputPreview)
        DebugLogRevealButton(debugLogURL: debugLogURL)
      }
      .padding(theme.spacing.cozy)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }
}

private struct InspectorRuntimeSection: View {
  let record: WorkflowStepRecord
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.squishy) {
      Text("Runtime")
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textSecondary)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading,
        spacing: theme.spacing.compact
      ) {
        ForEach(runtimeFacts) { fact in
          InspectorRuntimeFact(label: fact.label, value: fact.value)
        }
      }
    }
  }

  private var runtimeFacts: [InspectorRuntimeFactData] {
    guard let timing = record.timing else {
      return [InspectorRuntimeFactData(label: "Status", value: statusLabel)]
    }
    var facts = [InspectorRuntimeFactData(label: "Status", value: statusLabel)]
    if let elapsed = timing.elapsedLabel(status: record.status) {
      facts.append(InspectorRuntimeFactData(label: "Elapsed", value: elapsed))
    }
    if let timeout = timing.timeoutLabel {
      facts.append(InspectorRuntimeFactData(label: "Timeout", value: timeout))
    }
    if let started = timing.startedAt {
      facts.append(
        InspectorRuntimeFactData(label: "Started", value: Self.timeFormatter.string(from: started)))
    }
    if let finished = timing.finishedAt {
      facts.append(
        InspectorRuntimeFactData(
          label: "Finished", value: Self.timeFormatter.string(from: finished)))
    }
    return facts
  }

  private var statusLabel: String {
    switch record.status {
    case .pending:
      return "Pending"
    case .inProgress:
      return "In progress"
    case .succeeded:
      return "Completed"
    case .needsFix:
      return "Needs fix"
    case .failed:
      return "Needs attention"
    }
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter
  }()
}

private struct InspectorRuntimeFactData: Identifiable {
  var id: String { label }
  let label: String
  let value: String
}

private struct InspectorRuntimeFact: View {
  let label: String
  let value: String
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textTertiary)
      Text(value)
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textPrimary)
        .monospacedDigit()
        .lineLimit(1)
    }
    .padding(theme.spacing.compact)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
        .stroke(theme.colors.border, lineWidth: 1)
    }
  }
}

private struct InspectorOptionalSection: View {
  let title: String
  let text: String?

  var body: some View {
    if let text, !text.isEmpty {
      InspectorSection(title: title, text: text)
    }
  }
}

private struct InspectorOptionalDisclosureSection: View {
  let title: String
  let text: String?

  var body: some View {
    if let text, !text.isEmpty {
      InspectorDisclosureSection(title: title, text: text)
    }
  }
}

private struct InspectorDisclosureSection: View {
  let title: String
  let text: String
  @State private var isExpanded = false
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      InspectorSection(title: title, text: text)
        .padding(.top, theme.spacing.compact)
    } label: {
      Text(title)
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.accent)
    }
  }
}

private struct DebugLogRevealButton: View {
  let debugLogURL: URL?

  var body: some View {
    if let debugLogURL {
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([debugLogURL])
      } label: {
        Label("Reveal full run log", systemImage: "arrow.up.forward.app")
      }
      .buttonStyle(.bordered)
    }
  }
}
