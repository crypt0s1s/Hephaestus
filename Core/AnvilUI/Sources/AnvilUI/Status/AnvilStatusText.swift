import AnvilTheme
import SwiftUI

public enum AnvilStatusTone: Sendable {
    case neutral
    case success
    case warning
    case danger
}

/// Experimental: semantic status label for short workbench messages.
public struct AnvilStatusText: View {
    private let text: String
    private let tone: AnvilStatusTone

    @Environment(\.anvilTheme) private var theme

    public init(_ text: String, tone: AnvilStatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(theme.typography.status)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private var color: Color {
        switch tone {
        case .neutral:
            theme.colors.textSecondary
        case .success:
            theme.colors.success
        case .warning:
            theme.colors.warning
        case .danger:
            theme.colors.danger
        }
    }
}
