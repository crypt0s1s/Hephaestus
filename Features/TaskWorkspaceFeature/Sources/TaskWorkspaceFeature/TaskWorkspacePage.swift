import AnvilTheme
import AnvilUI
import SwiftUI

public struct TaskWorkspacePage: View {
    public let state: TaskWorkspaceState
    public let handle: (TaskWorkspaceAction) -> Void
    @Environment(\.anvilTheme) private var theme

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
                inspector: state.inspector,
                inspectorPresented: inspectorPresented,
                canInspect: state.runID != nil,
                canCancel: state.isRunning,
                handle: handle
            )

            Divider()
            chatSurface
        }
    }

    private var chatSurface: some View {
        ChatSurface(
            state: ChatSurfaceState(
                messages: state.messages,
                draftText: state.draftText,
                isRunning: state.isRunning,
                errorMessage: state.errorMessage
            )
        ) { chatAction in
            switch chatAction {
            case .changeDraft(let text):
                handle(.changeDraft(text))
            case .tapSend:
                handle(.tapSend)
            }
        }
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

}

struct ConversationBottomDistancePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
