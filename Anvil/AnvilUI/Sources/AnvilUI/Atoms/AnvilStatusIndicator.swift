import AnvilTheme
import SwiftUI

public enum AnvilStatusIndicatorState: Sendable {
    case idle
    case pending
    case running
    case succeeded
    case failed
    case waiting
}

public struct AnvilStatusIndicator: View {
    private let state: AnvilStatusIndicatorState
    private let label: String?
    private let accessibilityLabel: String

    @Environment(\.anvilTheme) private var theme

    public init(
        state: AnvilStatusIndicatorState,
        label: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.state = state
        self.label = label
        self.accessibilityLabel = accessibilityLabel ?? label ?? state.defaultAccessibilityLabel
    }

    public var body: some View {
        HStack(spacing: theme.spacing.tiny) {
            indicator

            if let label {
                Text(label)
                    .font(theme.typography.caption.weight(.semibold))
            }
        }
        .foregroundStyle(color)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded, .failed, .waiting:
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
        case .idle:
            Color.clear
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        case .pending:
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }

    private var systemImage: String {
        switch state {
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        case .waiting:
            "pause.circle.fill"
        case .idle, .pending, .running:
            ""
        }
    }

    private var color: Color {
        switch state {
        case .idle, .pending, .running:
            theme.colors.textSecondary
        case .succeeded:
            theme.colors.success
        case .failed:
            theme.colors.danger
        case .waiting:
            theme.colors.accent
        }
    }
}

private extension AnvilStatusIndicatorState {
    var defaultAccessibilityLabel: String {
        switch self {
        case .idle:
            "Idle"
        case .pending:
            "Pending"
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .waiting:
            "Waiting"
        }
    }
}
