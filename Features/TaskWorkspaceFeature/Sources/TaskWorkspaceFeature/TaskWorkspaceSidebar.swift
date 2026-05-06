import AnvilTheme
import AnvilUI
import SwiftUI

struct HistorySidebar: View {
    let sessions: [TaskSummaryState]
    let selectedRunID: UUID?
    let isLoading: Bool
    let errorMessage: String?
    let handle: (TaskWorkspaceAction) -> Void
    @Environment(\.anvilTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            header
            persistenceError
            historyContent
        }
        .padding(theme.spacing.cozy)
        .background(theme.colors.sidebarBackground)
    }

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(theme.typography.rowTitle)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            AnvilIconButton(
                systemName: "square.and.pencil",
                accessibilityLabel: "New task",
                size: 28
            ) {
                handle(.tapNewTask)
            }
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.newTaskButton)
        }
    }

    @ViewBuilder
    private var persistenceError: some View {
        if let errorMessage {
            ErrorBanner(message: errorMessage)
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.persistenceError)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if isLoading && sessions.isEmpty {
            loadingState
        } else if sessions.isEmpty {
            emptyState
        } else {
            sessionList
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: theme.spacing.cozy) {
            loadingIndicator("Loading")
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack {
            AnvilEmptyState(
                title: "No tasks",
                message: "Start a task and it will appear here.",
                systemImage: "tray"
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, theme.spacing.comfortable)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.historyEmptyState)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.compact) {
                if isLoading {
                    loadingIndicator("Refreshing")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.spacing.cozy)
                        .padding(.vertical, theme.spacing.compact)
                }

                ForEach(sessions) { session in
                    historyRow(for: session)
                }
            }
        }
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.historyList)
    }

    private func historyRow(for session: TaskSummaryState) -> some View {
        let isSelected = selectedRunID == session.id
        return HistoryRow(
            session: session,
            isSelected: isSelected
        ) {
            guard !isSelected else { return }
            handle(.tapTask(session.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingIndicator(_ text: String) -> some View {
        HStack(spacing: theme.spacing.compact) {
            ProgressView()
                .controlSize(.small)
            AnvilStatusPill(text)
        }
    }
}

struct HistoryRow: View {
    let session: TaskSummaryState
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        AnvilSidebarRow(
            title: session.title,
            subtitle: "\(session.messageCount) messages",
            isSelected: isSelected,
            action: action
        ) {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.messageCount) messages")
    }
}
