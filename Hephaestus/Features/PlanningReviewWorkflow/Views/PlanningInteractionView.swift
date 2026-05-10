import AnvilTheme
import SwiftUI

struct PlanningInteractionView: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.cozy) {
      PlanningInteractionHeader(state: state, action: action)
      PlanningInteractionContent(state: state, action: action)
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
    if let submittedMessage = state.submittedMessage {
      return "Submitted workflow message \(submittedMessage.id)."
    }
    return state.subtitle
  }

  private var submitButtonTitle: String {
    state.submittedMessage == nil ? "Submit Plan" : "Submitted"
  }

  private var submitButtonSystemImage: String {
    state.submittedMessage == nil ? "tray.and.arrow.up.fill" : "checkmark.circle.fill"
  }
}

private struct PlanningInteractionContent: View {
  let state: WorkflowInteractionState
  let action: (PlanningInteractionActionProcessor.Action) -> Void
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: theme.spacing.comfortable) {
      PlanningInteractionNotes(state: state, action: action)
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320)

      PlanningInteractionDraftEditor(state: state, action: action)
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 320)
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
        .disabled(state.submittedMessage != nil)
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

      if entry.source == .system {
        Spacer(minLength: 42)
      }
    }
  }

  private var entryContent: some View {
    VStack(alignment: .leading, spacing: theme.spacing.tiny) {
      Text(entry.source == .user ? "You" : "Workflow")
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
