import AnvilTheme
import AnvilUI
import SwiftUI

public struct ChatSurfaceState: Equatable, Sendable {
    public var messages: [ConversationMessageState]
    public var draftText: String
    public var isRunning: Bool
    public var errorMessage: String?
    public var emptyTitle: String
    public var emptyMessage: String
    public var inputPlaceholder: String
    public var runningStatusText: String

    public init(
        messages: [ConversationMessageState] = [],
        draftText: String = "",
        isRunning: Bool = false,
        errorMessage: String? = nil,
        emptyTitle: String = "Start a focused task",
        emptyMessage: String = "Describe the task, then inspect the run as it moves through the workspace.",
        inputPlaceholder: String = "Message Foundry",
        runningStatusText: String = "Foundry is thinking"
    ) {
        self.messages = messages
        self.draftText = draftText
        self.isRunning = isRunning
        self.errorMessage = errorMessage
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.inputPlaceholder = inputPlaceholder
        self.runningStatusText = runningStatusText
    }
}

public enum ChatSurfaceAction: Equatable {
    case changeDraft(String)
    case tapSend
}

public struct ChatSurface: View {
    public let state: ChatSurfaceState
    public let action: (ChatSurfaceAction) -> Void

    @State private var isTranscriptPinnedToBottom = true
    @Environment(\.anvilTheme) private var theme

    private var trimmedDraft: String {
        state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !state.isRunning && !trimmedDraft.isEmpty
    }

    public init(state: ChatSurfaceState, action: @escaping (ChatSurfaceAction) -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composerPanel
        }
        .background(theme.colors.windowBackground)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                transcriptScrollView(proxy: proxy, viewport: viewport)
            }
        }
    }

    private func transcriptScrollView(proxy: ScrollViewProxy, viewport: GeometryProxy) -> some View {
        ScrollView {
            ChatTranscript(
                messages: state.messages,
                isRunning: state.isRunning,
                emptyTitle: state.emptyTitle,
                emptyMessage: state.emptyMessage,
                runningStatusText: state.runningStatusText,
                viewport: viewport
            )
            .padding(.horizontal, theme.spacing.roomy)
            .padding(.vertical, theme.spacing.comfortable)
        }
        .coordinateSpace(name: ConversationScrollTarget.coordinateSpace)
        .accessibilityLabel("Conversation transcript")
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.transcript)
        .onPreferenceChange(ConversationBottomDistancePreferenceKey.self) { distanceFromBottom in
            isTranscriptPinnedToBottom = distanceFromBottom <= ConversationScrollTarget.pinnedThreshold
        }
        .onChange(of: state.messages, initial: true) {
            scrollToBottomIfPinned(proxy)
        }
        .onChange(of: state.isRunning, initial: false) {
            scrollToBottomIfPinned(proxy)
        }
    }

    private var composerPanel: some View {
        VStack(spacing: theme.spacing.cozy) {
            if let errorMessage = state.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            ChatComposer(
                text: draftTextBinding,
                placeholder: state.inputPlaceholder,
                canSend: canSend
            ) {
                action(.tapSend)
            }
        }
        .padding(.horizontal, theme.spacing.comfortable)
        .padding(.vertical, theme.spacing.cozy)
        .background(theme.colors.panelBackground)
    }

    private var draftTextBinding: Binding<String> {
        Binding(
            get: { state.draftText },
            set: { action(.changeDraft($0)) }
        )
    }

    private func scrollToBottomIfPinned(_ proxy: ScrollViewProxy) {
        guard isTranscriptPinnedToBottom else { return }
        proxy.scrollTo(ConversationScrollTarget.bottom, anchor: .bottom)
    }
}

private struct ChatTranscript: View {
    let messages: [ConversationMessageState]
    let isRunning: Bool
    let emptyTitle: String
    let emptyMessage: String
    let runningStatusText: String
    let viewport: GeometryProxy
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        LazyVStack(spacing: theme.spacing.comfortable) {
            if messages.isEmpty {
                ChatEmptyState(title: emptyTitle, message: emptyMessage)
                    .padding(.top, theme.spacing.spacious + theme.spacing.spacious + theme.spacing.squishy)
            } else {
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }

            if isRunning {
                RunningStatus(text: runningStatusText)
            }

            bottomScrollMarker
        }
    }

    private var bottomScrollMarker: some View {
        Color.clear
            .frame(height: 1)
            .id(ConversationScrollTarget.bottom)
            .background {
                GeometryReader { bottomMarker in
                    Color.clear.preference(
                        key: ConversationBottomDistancePreferenceKey.self,
                        value: bottomMarker.frame(in: .named(ConversationScrollTarget.coordinateSpace)).maxY
                            - viewport.size.height
                    )
                }
            }
    }
}

private struct ChatComposer: View {
    @Binding var text: String
    let placeholder: String
    let canSend: Bool
    let send: () -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.cozy) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, theme.spacing.cozy)
                .padding(.vertical, theme.spacing.compact)
                .onSubmit(send)
                .accessibilityLabel("Message")
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.messageInput)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .clipShape(Circle())
            .disabled(!canSend)
            .help("Send message")
            .accessibilityLabel("Send message")
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.sendButton)
        }
        .padding(theme.spacing.squishy)
        .background(theme.colors.elevatedPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.colors.separator, lineWidth: 1)
        }
    }
}
