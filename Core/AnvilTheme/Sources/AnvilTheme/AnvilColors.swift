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

    public static let workbench = AnvilColors(
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

    public static let hephaestus = AnvilColors(
        windowBackground: Color(red: 0.090, green: 0.067, blue: 0.055),
        sidebarBackground: Color(red: 0.125, green: 0.092, blue: 0.073),
        panelBackground: Color(red: 0.158, green: 0.117, blue: 0.091),
        elevatedPanelBackground: Color(red: 0.205, green: 0.145, blue: 0.108),
        logBackground: Color(red: 0.061, green: 0.047, blue: 0.041),
        selectionBackground: Color(red: 0.770, green: 0.167, blue: 0.100).opacity(0.24),
        border: Color(red: 0.995, green: 0.484, blue: 0.314).opacity(0.18),
        separator: Color(red: 0.995, green: 0.484, blue: 0.314).opacity(0.13),
        textPrimary: Color(red: 0.980, green: 0.943, blue: 0.884),
        textSecondary: Color(red: 0.760, green: 0.675, blue: 0.594),
        textTertiary: Color(red: 0.560, green: 0.486, blue: 0.421),
        accent: Color(red: 0.906, green: 0.212, blue: 0.118),
        accentForeground: Color(red: 1.000, green: 0.965, blue: 0.910),
        success: Color(red: 0.373, green: 0.706, blue: 0.431),
        warning: Color(red: 0.965, green: 0.596, blue: 0.208),
        danger: Color(red: 1.000, green: 0.286, blue: 0.224)
    )
}
