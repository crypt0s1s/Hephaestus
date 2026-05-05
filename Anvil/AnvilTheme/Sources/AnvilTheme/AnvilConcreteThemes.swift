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
        windowBackground: Color(red: 0.965, green: 0.967, blue: 0.970),
        sidebarBackground: Color(red: 0.925, green: 0.932, blue: 0.940),
        panelBackground: Color(red: 0.985, green: 0.986, blue: 0.988),
        elevatedPanelBackground: Color(red: 1.000, green: 1.000, blue: 1.000),
        logBackground: Color(red: 0.102, green: 0.110, blue: 0.122),
        selectionBackground: Color(red: 0.208, green: 0.455, blue: 0.760).opacity(0.14),
        border: Color(red: 0.128, green: 0.145, blue: 0.168).opacity(0.10),
        separator: Color(red: 0.128, green: 0.145, blue: 0.168).opacity(0.12),
        textPrimary: Color(red: 0.090, green: 0.101, blue: 0.120),
        textSecondary: Color(red: 0.325, green: 0.355, blue: 0.395),
        textTertiary: Color(red: 0.540, green: 0.570, blue: 0.610),
        accent: Color(red: 0.208, green: 0.455, blue: 0.760),
        accentForeground: Color.white,
        success: Color(red: 0.100, green: 0.565, blue: 0.335),
        warning: Color(red: 0.780, green: 0.435, blue: 0.120),
        danger: Color(red: 0.780, green: 0.185, blue: 0.170)
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
