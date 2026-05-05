import SwiftUI

public struct AnvilTheme: Sendable {
    public var colors: AnvilColors
    public var spacing: AnvilSpacing
    public var typography: AnvilTypography
    public var radii: AnvilRadii
    public var motion: AnvilMotion

    public init(
        colors: AnvilColors,
        spacing: AnvilSpacing,
        typography: AnvilTypography,
        radii: AnvilRadii,
        motion: AnvilMotion
    ) {
        self.colors = colors
        self.spacing = spacing
        self.typography = typography
        self.radii = radii
        self.motion = motion
    }

    /// Infrastructure fallback used when no concrete theme is injected.
    public static let fallback = AnvilTheme(
        colors: .fallback,
        spacing: .fallback,
        typography: .fallback,
        radii: .fallback,
        motion: .fallback
    )
}

private struct AnvilThemeKey: EnvironmentKey {
    static let defaultValue = AnvilTheme.fallback
}

public extension EnvironmentValues {
    var anvilTheme: AnvilTheme {
        get { self[AnvilThemeKey.self] }
        set { self[AnvilThemeKey.self] = newValue }
    }
}

public extension View {
    func anvilTheme(_ theme: AnvilTheme) -> some View {
        environment(\.anvilTheme, theme)
    }
}
