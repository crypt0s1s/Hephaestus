import Foundation

public struct AnvilSpacing: Sendable {
    public var xxSmall: CGFloat
    public var xSmall: CGFloat
    public var small: CGFloat
    public var medium: CGFloat
    public var large: CGFloat
    public var xLarge: CGFloat
    public var xxLarge: CGFloat

    public init(
        xxSmall: CGFloat,
        xSmall: CGFloat,
        small: CGFloat,
        medium: CGFloat,
        large: CGFloat,
        xLarge: CGFloat,
        xxLarge: CGFloat
    ) {
        self.xxSmall = xxSmall
        self.xSmall = xSmall
        self.small = small
        self.medium = medium
        self.large = large
        self.xLarge = xLarge
        self.xxLarge = xxLarge
    }

    public static let fallback = AnvilSpacing(
        xxSmall: 2,
        xSmall: 4,
        small: 8,
        medium: 12,
        large: 18,
        xLarge: 24,
        xxLarge: 32
    )
}
