import AnvilTheme
import AnvilUI
import HephaestusObservation
import SwiftUI

struct RunInspectorSheet: View {
  let state: RunInspectorPanelState
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
      Text("Run Inspector")
        .font(theme.typography.pageTitle)
        .foregroundStyle(theme.colors.textPrimary)
      content
    }
    .padding(theme.spacing.roomy)
    .frame(width: 720, height: 620)
    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorPanel)
  }

  @ViewBuilder
  private var content: some View {
    if state.isLoading {
      loadingState
    } else if let errorMessage = state.errorMessage {
      ErrorBanner(message: errorMessage)
      Spacer()
    } else if let inspection = state.inspection {
      RunInspectionContent(inspection: inspection)
    } else {
      AnvilEmptyState(
        title: "No run selected",
        message: "Select a task run before opening inspection details.",
        systemImage: "list.bullet.rectangle"
      )
      Spacer()
    }
  }

  private var loadingState: some View {
    VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
      HStack(spacing: theme.spacing.compact) {
        ProgressView()
          .controlSize(.small)
        AnvilStatusText("Loading run details")
      }
      Spacer()
    }
  }
}

struct RunInspectionContent: View {
  let inspection: RunInspectionSnapshot
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.spacing.comfortable) {
        timelineSection
        turnsSection
        providerSection
        contextSection
      }
    }
  }

  private var timelineSection: some View {
    AnvilPanelSection(title: "Timeline") {
      if inspection.events.isEmpty {
        UnavailableRow(text: "No runtime events are available.")
      } else {
        ForEach(inspection.events) { event in
          RuntimeEventRow(event: event)
        }
      }
    }
    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorTimeline)
  }

  private var turnsSection: some View {
    AnvilPanelSection(title: "Turns") {
      if inspection.turns.isEmpty {
        UnavailableRow(text: "No turns are available.")
      } else {
        ForEach(inspection.turns) { turn in
          TurnInspectionRow(turn: turn)
        }
      }
    }
  }

  private var providerSection: some View {
    AnvilPanelSection(title: "Provider") {
      if inspection.providerRequests.isEmpty {
        UnavailableRow(text: "Provider request details are unavailable.")
      } else {
        ForEach(inspection.providerRequests) { request in
          ProviderRequestRow(request: request)
        }
      }
    }
  }

  private var contextSection: some View {
    AnvilPanelSection(title: "Context") {
      if inspection.contextTraces.isEmpty {
        UnavailableRow(text: "Context details are unavailable.")
      } else {
        ForEach(inspection.contextTraces) { trace in
          ContextTraceRow(trace: trace)
        }
      }
    }
  }
}

struct RuntimeEventRow: View {
  let event: ObservationEvent
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    AnvilSurface(tone: event.error == nil ? .neutral : .danger) {
      VStack(alignment: .leading, spacing: theme.spacing.squishy) {
        AnvilNumberedRow(
          number: event.sequence,
          title: event.kind.rawValue,
          subtitle: event.summary
        )
        .textSelection(.enabled)
        errorText
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var errorText: some View {
    if let error = event.error {
      Text(error)
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.danger)
        .textSelection(.enabled)
    }
  }
}

struct ProviderRequestRow: View {
  let request: ObservedProviderRequest
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    AnvilSurface {
      Text(summary)
        .font(theme.typography.caption)
    }
  }

  private var summary: String {
    let streamState = request.stream ? "on" : "off"
    let systemPromptState = request.systemPromptIncluded ? "included" : "excluded"
    return """
    \(request.model): \(request.messageCount) messages, stream \(streamState), \
    system prompt \(systemPromptState)
    """
  }
}

struct TurnInspectionRow: View {
  let turn: ObservedTurn
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    AnvilSurface(tone: turn.status == .failed ? .danger : .neutral) {
      VStack(alignment: .leading, spacing: theme.spacing.compact) {
        Text("Turn \(turn.id.uuidString.prefix(8)) - \(turn.status.rawValue)")
          .font(theme.typography.caption.weight(.semibold))
        Text("User message: \(shortID(turn.userMessageID))")
          .font(theme.typography.caption)
          .textSelection(.enabled)
        if let assistantMessageID = turn.assistantMessageID {
          Text("Assistant message: \(assistantMessageID.uuidString.prefix(8))")
            .font(theme.typography.caption)
            .textSelection(.enabled)
        } else {
          Text("Assistant message unavailable")
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
    }
  }

  private func shortID(_ id: UUID?) -> String {
    id.map { String($0.uuidString.prefix(8)) } ?? "unavailable"
  }
}

struct ContextTraceRow: View {
  let trace: ObservedContextTrace
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    AnvilSurface {
      VStack(alignment: .leading, spacing: theme.spacing.compact) {
        Text(trace.policyName)
          .font(theme.typography.caption.weight(.semibold))
        if let messageLimit = trace.messageLimit {
          Text("Budget: last \(messageLimit) messages")
            .font(theme.typography.smallCaption)
            .foregroundStyle(theme.colors.textSecondary)
        } else {
          Text("Budget unavailable")
            .font(theme.typography.smallCaption)
            .foregroundStyle(theme.colors.textSecondary)
        }
        ContextMessageList(
          title: "Included", ids: trace.includedMessageIDs, emptyText: "No messages were included.")
        ContextMessageList(
          title: "Excluded", ids: trace.excludedMessageIDs, emptyText: "No messages were excluded.")
      }
    }
  }
}

struct ContextMessageList: View {
  let title: String
  let ids: [UUID]
  let emptyText: String
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.squishy) {
      Text(title)
        .font(theme.typography.smallCaption.weight(.semibold))
        .foregroundStyle(theme.colors.textSecondary)
      if ids.isEmpty {
        AnvilStatusText(emptyText)
      } else {
        ForEach(ids, id: \.self) { id in
          Text("Message \(id.uuidString.prefix(8))")
            .font(theme.typography.caption)
            .textSelection(.enabled)
        }
      }
    }
  }
}

struct UnavailableRow: View {
  let text: String
  @Environment(\.anvilTheme) private var theme

  var body: some View {
    AnvilSurface {
      AnvilStatusText(text)
    }
  }
}
