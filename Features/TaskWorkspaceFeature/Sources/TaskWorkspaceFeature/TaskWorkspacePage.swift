import AnvilTheme
import AnvilUI
import SwiftUI

public struct TaskWorkspacePage: View {
    public let state: TaskWorkspaceState
    public let handle: (TaskWorkspaceAction) -> Void
    @State private var isTranscriptPinnedToBottom = true
    @Environment(\.anvilTheme) private var theme

    private var trimmedDraft: String {
        state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !state.isRunning && !trimmedDraft.isEmpty
    }

    public init(state: TaskWorkspaceState, handle: @escaping (TaskWorkspaceAction) -> Void) {
        self.state = state
        self.handle = handle
    }

    public var body: some View {
        pageLayout
            .frame(minWidth: 920, minHeight: 560)
            .background(theme.colors.windowBackground)
            .sheet(isPresented: providerSettingsPresented) {
                ProviderSettingsSheet(state: state.providerSettings, handle: handle)
            }
            .popover(
                isPresented: inspectorPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                RunInspectorSheet(state: state.inspector)
            }
    }

    private var pageLayout: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            conversationColumn
        }
    }

    private var sidebar: some View {
        HistorySidebar(
            sessions: state.sessionSummaries,
            selectedRunID: state.runID,
            isLoading: state.isLoadingSessions,
            errorMessage: state.persistenceErrorMessage,
            handle: handle
        )
        .frame(width: 250)
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            TaskHeader(
                isRunning: state.isRunning,
                runID: state.runID,
                canInspect: state.runID != nil,
                canCancel: state.isRunning,
                handle: handle
            )

            Divider()
            transcript
            Divider()
            composerPanel
        }
    }

    private var composerPanel: some View {
        VStack(spacing: theme.spacing.medium) {
            if let errorMessage = state.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            composer
        }
        .padding(.horizontal, theme.spacing.large)
        .padding(.vertical, theme.spacing.medium)
        .background(theme.colors.panelBackground)
    }

    private var providerSettingsPresented: Binding<Bool> {
        Binding(
            get: { state.providerSettings.isPresented },
            set: { if !$0 { handle(.dismissSettings) } }
        )
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { state.inspector.isPresented },
            set: { if !$0 { handle(.dismissInspector) } }
        )
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
            transcriptMessages(viewport: viewport)
                .padding(.horizontal, theme.spacing.xLarge)
                .padding(.vertical, theme.spacing.large)
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

    private func transcriptMessages(viewport: GeometryProxy) -> some View {
        LazyVStack(spacing: theme.spacing.large) {
            if state.messages.isEmpty {
                EmptyTaskState()
                    .padding(.top, theme.spacing.xxLarge + theme.spacing.xxLarge + theme.spacing.xSmall)
            } else {
                ForEach(state.messages) { message in
                    MessageBubble(message: message)
                }
            }

            if state.isRunning {
                RunningStatus()
            }

            bottomScrollMarker(viewport: viewport)
        }
    }

    private func bottomScrollMarker(viewport: GeometryProxy) -> some View {
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

    private func scrollToBottomIfPinned(_ proxy: ScrollViewProxy) {
        guard isTranscriptPinnedToBottom else { return }
        proxy.scrollTo(ConversationScrollTarget.bottom, anchor: .bottom)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: theme.spacing.medium) {
            messageField
            sendButton
        }
    }

    private var messageField: some View {
        AnvilSurface(border: .separator) {
            TextField("Add task instruction", text: draftTextBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit {
                    handle(.tapSend)
                }
                .accessibilityLabel("Message")
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.messageInput)
            }
    }

    private var sendButton: some View {
        Button {
            handle(.tapSend)
        } label: {
            Label("Send", systemImage: "paperplane.fill")
                .labelStyle(.iconOnly)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSend)
        .help("Send message")
        .accessibilityLabel("Send message")
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.sendButton)
    }

    private var draftTextBinding: Binding<String> {
        Binding(
            get: { state.draftText },
            set: { handle(.changeDraft($0)) }
        )
    }
}

struct ConversationBottomDistancePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
