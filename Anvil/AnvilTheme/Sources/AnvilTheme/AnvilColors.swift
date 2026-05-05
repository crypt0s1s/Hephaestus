import SwiftUI

public struct AnvilColors: Sendable {
    public var windowBackground: Color
    public var sidebarBackground: Color
    public var panelBackground: Color
    public var elevatedPanelBackground: Color
    public var logBackground: Color
    public var selectionBackground: Color
    public var border: Color
    public var separator: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textTertiary: Color
    public var accent: Color
    public var accentForeground: Color
    public var success: Color
    public var warning: Color
    public var danger: Color

    public init(
        windowBackground: Color,
        sidebarBackground: Color,
        panelBackground: Color,
        elevatedPanelBackground: Color,
        logBackground: Color,
        selectionBackground: Color,
        border: Color,
        separator: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        accent: Color,
        accentForeground: Color,
        success: Color,
        warning: Color,
        danger: Color
    ) {
        self.windowBackground = windowBackground
        self.sidebarBackground = sidebarBackground
        self.panelBackground = panelBackground
        self.elevatedPanelBackground = elevatedPanelBackground
        self.logBackground = logBackground
        self.selectionBackground = selectionBackground
        self.border = border
        self.separator = separator
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentForeground = accentForeground
        self.success = success
        self.warning = warning
        self.danger = danger
    }

    public static let fallback = AnvilColors(
        windowBackground: Color(nsColor: .windowBackgroundColor),
        sidebarBackground: Color(nsColor: .controlBackgroundColor),
        panelBackground: Color(nsColor: .textBackgroundColor),
        elevatedPanelBackground: Color(nsColor: .controlBackgroundColor),
        logBackground: Color(nsColor: .textBackgroundColor),
        selectionBackground: Color.accentColor.opacity(0.14),
        border: Color.primary.opacity(0.08),
        separator: Color.primary.opacity(0.10),
        textPrimary: Color.primary,
        textSecondary: Color.secondary,
        textTertiary: Color(nsColor: .tertiaryLabelColor),
        accent: Color.accentColor,
        accentForeground: Color.white,
        success: Color.green,
        warning: Color.orange,
        danger: Color.red
    )
}
