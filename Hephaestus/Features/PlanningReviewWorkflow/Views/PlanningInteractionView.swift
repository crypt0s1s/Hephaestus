import AnvilTheme
import SwiftUI

struct PlanningInteractionView: View {
  enum PresentationStyle {
    case inline
    case editorPrimary
  }

  let state: WorkflowInteractionState
  let presentationStyle: PresentationStyle
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  init(
    state: WorkflowInteractionState,
    presentationStyle: PresentationStyle = .editorPrimary,
    action: @escaping (PlanningInteractionActionProcessor.Action) -> Void
  ) {
    self.state = state
    self.presentationStyle = presentationStyle
    self.action = action
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.cozy) {
      PlanningInteractionHeader(state: state, action: action)
      PlanningInteractionContent(state: state, presentationStyle: presentationStyle, action: action)
      PlanningInteractionDecisionBar(state: state, action: action)
    }
    .padding(theme.spacing.comfortable)
    .background(theme.colors.elevatedPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        .stroke(theme.colors.border, lineWidth: 1)
    }
  }
}

private struct PlanningInteractionHeader: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    HStack(spacing: theme.spacing.cozy) {
      Image(systemName: "bubble.left.and.text.bubble.right")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(theme.colors.accent)
        .frame(width: 30, height: 30)
        .background(theme.colors.selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))

      VStack(alignment: .leading, spacing: theme.spacing.tiny) {
        Text(state.title)
          .font(theme.typography.rowTitle)
          .foregroundStyle(theme.colors.textPrimary)
          .accessibilityIdentifier("planning.interaction")
        Text(statusText)
          .font(theme.typography.caption)
          .foregroundStyle(theme.colors.textSecondary)
      }

      Spacer()

      if state.isBusy {
        ProgressView()
          .controlSize(.small)
          .accessibilityIdentifier("planning.busyIndicator")
      }

      Button(
        action: { action(.tapSubmit) },
        label: {
          Label(submitButtonTitle, systemImage: submitButtonSystemImage)
        }
      )
      .buttonStyle(.borderedProminent)
      .disabled(!state.canSubmit)
      .accessibilityIdentifier("planning.submitPlan")
    }
  }

  private var statusText: String {
    switch state.phase {
    case .sending:
      return "Planner is responding."
    case .materializing:
      return "Submitting and validating the plan artifact."
    case .reviewing:
      return "Automated review cycles are running."
    case .completed:
      return "Automated review cycles finished. Review the plan before accepting it."
    case .accepted:
      return "Planning review workflow accepted."
    case .idle:
      break
    }
    if state.draftRequiresUserEdit {
      return "Review and edit the generated draft before submitting it."
    }
    if let submittedOutput = state.submittedOutput {
      return "Submitted plan artifact \(submittedOutput.id)."
    }
    return state.subtitle
  }

  private var submitButtonTitle: String {
    if state.isBusy {
      return "Working"
    }
    return state.submittedOutput == nil ? "Submit Plan" : "Submitted"
  }

  private var submitButtonSystemImage: String {
    if state.isBusy {
      return "hourglass"
    }
    return state.submittedOutput == nil ? "tray.and.arrow.up.fill" : "checkmark.circle.fill"
  }
}

private struct PlanningInteractionDecisionBar: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    if state.canResolveCompletedOutput {
      HStack(spacing: theme.spacing.compact) {
        Button(
          action: { action(.tapAcceptPlan) },
          label: { Label("Accept Plan", systemImage: "checkmark.circle.fill") }
        )
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("planning.acceptPlan")

        Button(
          action: { action(.tapRequestAnotherCycle) },
          label: { Label("Another Cycle", systemImage: "arrow.triangle.2.circlepath") }
        )
        .accessibilityIdentifier("planning.anotherCycle")

        Button(
          action: { action(.tapContinuePlanning) },
          label: { Label("Continue Planning", systemImage: "square.and.pencil") }
        )
        .accessibilityIdentifier("planning.continuePlanning")

        Spacer()
      }
      .padding(.top, theme.spacing.compact)
    }
  }
}

private struct PlanningInteractionContent: View {
  let state: WorkflowInteractionState
  let presentationStyle: PlanningInteractionView.PresentationStyle
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    switch presentationStyle {
    case .editorPrimary:
      HStack(alignment: .top, spacing: theme.spacing.comfortable) {
        PlanningInteractionDraftEditor(state: state, action: action)
          .frame(minWidth: 520, maxWidth: .infinity, minHeight: 440)

        PlanningInteractionNotes(state: state, action: action)
          .frame(width: 360)
          .frame(minHeight: 440)
      }
    case .inline:
      HStack(alignment: .top, spacing: theme.spacing.comfortable) {
        PlanningInteractionNotes(state: state, action: action)
          .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320)

        PlanningInteractionDraftEditor(state: state, action: action)
          .frame(minWidth: 360, maxWidth: .infinity, minHeight: 320)
      }
    }
  }
}

private struct PlanningInteractionNotes: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.compact) {
      Text("Interaction notes")
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textSecondary)

      PlanningInteractionEntryList(entries: state.entries)

      if let errorMessage = state.errorMessage {
        Text(errorMessage)
          .font(theme.typography.caption)
          .foregroundStyle(theme.colors.danger)
          .accessibilityIdentifier("planning.error")
      }

      PlanningInteractionNoteComposer(state: state, action: action)
    }
  }
}

private struct PlanningInteractionEntryList: View {
  let entries: [WorkflowInteractionEntry]
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: theme.spacing.compact) {
        ForEach(entries) { entry in
          PlanningInteractionEntryBubble(entry: entry)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.spacing.cozy)
    }
    .background(theme.colors.panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
        .stroke(theme.colors.border, lineWidth: 1)
    }
    .accessibilityIdentifier("planning.conversation")
  }
}

private struct PlanningInteractionNoteComposer: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    HStack(spacing: theme.spacing.compact) {
      TextField(state.inputPlaceholder, text: noteBinding, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...3)
        .padding(.horizontal, theme.spacing.cozy)
        .padding(.vertical, theme.spacing.compact)
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
            .stroke(theme.colors.border, lineWidth: 1)
        }
        .accessibilityLabel("Interaction note")
        .accessibilityIdentifier("planning.messageInput")

      Button(
        action: { action(.tapAddNote) },
        label: {
          Label("Add note", systemImage: "plus.message.fill")
            .labelStyle(.iconOnly)
            .frame(width: 30, height: 30)
        }
      )
      .buttonStyle(.borderedProminent)
      .disabled(!state.canAddNote)
      .accessibilityLabel("Add interaction note")
      .accessibilityIdentifier("planning.sendButton")
    }
  }

  private var noteBinding: Binding<String> {
    Binding(get: { state.note }, set: { action(.changeNote($0)) })
  }
}

private struct PlanningInteractionDraftEditor: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.compact) {
      Text(state.draftTitle)
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textSecondary)

      if state.phase == .sending {
        Text("The draft updates only when the planner returns an explicit markdown plan.")
          .font(theme.typography.caption)
          .foregroundStyle(theme.colors.textSecondary)
      }
      if state.draftRequiresUserEdit {
        Text("Edit the generated draft before submitting it to the workflow.")
          .font(theme.typography.caption)
          .foregroundStyle(theme.colors.textSecondary)
          .accessibilityIdentifier("planning.requiresUserEdit")
      }

      TextEditor(text: draftBinding)
        .font(theme.typography.body)
        .foregroundStyle(theme.colors.textPrimary)
        .scrollContentBackground(.hidden)
        .padding(theme.spacing.compact)
        .background(theme.colors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
            .stroke(theme.colors.border, lineWidth: 1)
        }
        .disabled(state.submittedOutput != nil || state.isBusy)
        .accessibilityLabel(state.draftTitle)
        .accessibilityIdentifier("planning.draftPlan")
    }
  }

  private var draftBinding: Binding<String> {
    Binding(get: { state.draft }, set: { action(.changeDraft($0)) })
  }
}

private struct PlanningInteractionEntryBubble: View {
  let entry: WorkflowInteractionEntry
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    HStack(alignment: .bottom) {
      if entry.source == .user {
        Spacer(minLength: 42)
      }

      entryContent

      if entry.source != .user {
        Spacer(minLength: 42)
      }
    }
  }

  private var entryContent: some View {
    VStack(alignment: .leading, spacing: theme.spacing.tiny) {
      Text(entry.title)
        .font(theme.typography.caption.weight(.semibold))
        .foregroundStyle(theme.colors.textSecondary)
      Text(entry.text)
        .font(theme.typography.body)
        .foregroundStyle(theme.colors.textPrimary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(theme.spacing.cozy)
    .background(entry.source == .user ? theme.colors.selectionBackground : theme.colors.elevatedPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
        .stroke(entry.source == .user ? theme.colors.accent.opacity(0.24) : theme.colors.border, lineWidth: 1)
    }
    .frame(maxWidth: 520, alignment: entry.source == .user ? .trailing : .leading)
    .accessibilityElement(children: .combine)
  }
}

private extension WorkflowInteractionEntry {
  var title: String {
    switch source {
    case .system:
      return "Workflow"
    case .user:
      return "You"
    case .assistant:
      return "Planner"
    }
  }
}
