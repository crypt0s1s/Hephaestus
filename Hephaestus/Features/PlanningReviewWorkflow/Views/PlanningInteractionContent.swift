import AnvilTheme
import AnvilUI
import SwiftUI

struct PlanningInteractionContent: View {
    let state: PlanningInteractionState
    let presentationStyle: PlanningInteractionView.PresentationStyle
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        switch presentationStyle {
        case .editorPrimary:
            ViewThatFits(in: .horizontal) {
                editorPrimaryHorizontal
                editorPrimaryVertical
            }
        case .inline:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: theme.spacing.comfortable) {
                    PlanningInteractionNotes(state: state, action: action)
                        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320)

                    PlanningInteractionDraftEditor(state: state, action: action)
                        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 320)
                }
                VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
                    PlanningInteractionNotes(state: state, action: action)
                        .frame(maxWidth: .infinity, minHeight: 280)

                    PlanningInteractionDraftEditor(state: state, action: action)
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
        }
    }

    private var editorPrimaryHorizontal: some View {
        HStack(alignment: .top, spacing: theme.spacing.comfortable) {
            PlanningInteractionDraftEditor(state: state, action: action)
                .frame(minWidth: 520, maxWidth: .infinity, minHeight: 440)

            PlanningInteractionNotes(state: state, action: action)
                .frame(width: 360)
                .frame(minHeight: 440)
        }
    }

    private var editorPrimaryVertical: some View {
        VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
            PlanningInteractionDraftEditor(state: state, action: action)
                .frame(maxWidth: .infinity, minHeight: 360)

            PlanningInteractionNotes(state: state, action: action)
                .frame(maxWidth: .infinity, minHeight: 280)
        }
    }
}

private struct PlanningInteractionNotes: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void

    var body: some View {
        AnvilFieldSection(
            title: "Interaction notes",
            error: state.errorMessage,
            errorAccessibilityIdentifier: "planning.error"
        ) {
            PlanningInteractionEntryList(entries: state.entries)

            PlanningInteractionNoteComposer(state: state, action: action)
        }
    }
}

private struct PlanningInteractionEntryList: View {
    let entries: [PlanningInteractionEntry]
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        AnvilList(
            configuration: AnvilListConfiguration(
                style: .panel,
                spacing: theme.spacing.compact,
                contentPadding: theme.spacing.cozy,
                accessibilityIdentifier: "planning.conversation"
            )
        ) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.compact) {
                    ForEach(entries) { entry in
                        PlanningInteractionEntryBubble(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PlanningInteractionNoteComposer: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.compact) {
            AnvilTextField(
                text: noteBinding,
                configuration: AnvilTextFieldConfiguration(
                    placeholder: state.inputPlaceholder,
                    axis: .vertical,
                    lineLimit: 1...3,
                    accessibilityLabel: "Interaction note",
                    accessibilityIdentifier: "planning.messageInput"
                )
            )

            AnvilActionButton(
                configuration: AnvilActionButtonConfiguration(
                    title: "Add note",
                    systemImage: "plus.message.fill",
                    style: .primary,
                    labelStyle: .iconOnly,
                    isDisabled: !state.canAddNote,
                    accessibilityLabel: "Add interaction note",
                    accessibilityIdentifier: "planning.sendButton"
                ),
                action: { action(.tapAddNote) }
            )
        }
    }

    private var noteBinding: Binding<String> {
        Binding(get: { state.note }, set: { action(.changeNote($0)) })
    }
}

private struct PlanningInteractionDraftEditor: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void

    var body: some View {
        AnvilFieldSection(title: state.draftTitle) {
            PlanningInteractionDraftGate(state: state, action: action)

            AnvilTextEditor(
                text: draftBinding,
                configuration: AnvilTextEditorConfiguration(
                    accessibilityLabel: state.draftTitle,
                    accessibilityIdentifier: "planning.draftPlan"
                )
            )
                .disabled(state.submittedOutput != nil || state.isBusy)
        }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { state.draft }, set: { action(.changeDraft($0)) })
    }
}

private struct PlanningInteractionDraftGate: View {
    let state: PlanningInteractionState
    let action: (PlanningInteractionActionProcessor.Action) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        if state.phase == .sending {
            Text("The draft updates only when the planner returns an explicit markdown plan.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        switch state.gateState {
        case .awaitingUserReview:
            Text("Review this draft before starting automated review.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("planning.awaitingUserReview")
        case .needsOutput(let issue):
            Text(issue.message)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("planning.needsOutput")
            PlanningInteractionRecoveryActions(issue: issue, action: action)
        case .interacting, .accepted:
            EmptyView()
        }
    }
}

private struct PlanningInteractionEntryBubble: View {
    let entry: PlanningInteractionEntry
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

private extension PlanningInteractionEntry {
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
