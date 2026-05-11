import SwiftUI

extension AnvilTheme {
    public static let anvilWorkbench = AnvilTheme(
        colors: .anvilWorkbench,
        spacing: .anvilWorkbench,
        typography: .anvilWorkbench,
        radii: .anvilWorkbench,
        motion: .anvilWorkbench
    )

    public static let hephaestus = AnvilTheme(
        colors: .hephaestus,
        spacing: .hephaestus,
        typography: .hephaestus,
        radii: .hephaestus,
        motion: .hephaestus
    )
}

extension AnvilColors {
    public static let anvilWorkbench = AnvilColors.fallback

    public static let hephaestus = AnvilColors(
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

extension AnvilSpacing {
    public static let anvilWorkbench = AnvilSpacing.fallback
    public static let hephaestus = AnvilSpacing.anvilWorkbench
}

extension AnvilTypography {
    public static let anvilWorkbench = AnvilTypography.fallback
    public static let hephaestus = AnvilTypography.anvilWorkbench
}

extension AnvilRadii {
    public static let anvilWorkbench = AnvilRadii.fallback
    public static let hephaestus = AnvilRadii.anvilWorkbench
}

extension AnvilMotion {
    public static let anvilWorkbench = AnvilMotion.fallback
    public static let hephaestus = AnvilMotion.anvilWorkbench
}
