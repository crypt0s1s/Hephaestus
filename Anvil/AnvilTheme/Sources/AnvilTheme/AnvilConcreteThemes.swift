import SwiftUI

public extension AnvilTheme {
    static let anvilWorkbench = AnvilTheme(
        colors: .anvilWorkbench,
        spacing: .anvilWorkbench,
        typography: .anvilWorkbench,
        radii: .anvilWorkbench,
        motion: .anvilWorkbench
    )

    static let hephaestus = AnvilTheme(
        colors: .hephaestus,
        spacing: .hephaestus,
        typography: .hephaestus,
        radii: .hephaestus,
        motion: .hephaestus
    )
}

public extension AnvilColors {
    static let anvilWorkbench = AnvilColors.fallback

    static let hephaestus = AnvilColors(
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

public extension AnvilSpacing {
    static let anvilWorkbench = AnvilSpacing.fallback
    static let hephaestus = AnvilSpacing.anvilWorkbench
}

public extension AnvilTypography {
    static let anvilWorkbench = AnvilTypography.fallback
    static let hephaestus = AnvilTypography.anvilWorkbench
}

public extension AnvilRadii {
    static let anvilWorkbench = AnvilRadii.fallback
    static let hephaestus = AnvilRadii.anvilWorkbench
}

public extension AnvilMotion {
    static let anvilWorkbench = AnvilMotion.fallback
    static let hephaestus = AnvilMotion.anvilWorkbench
}
