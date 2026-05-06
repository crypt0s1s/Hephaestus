import Foundation

public struct AnvilSpacing: Sendable {
    public var tiny: CGFloat
    public var squishy: CGFloat
    public var compact: CGFloat
    public var cozy: CGFloat
    public var comfortable: CGFloat
    public var roomy: CGFloat
    public var spacious: CGFloat

    public init(
        tiny: CGFloat,
        squishy: CGFloat,
        compact: CGFloat,
        cozy: CGFloat,
        comfortable: CGFloat,
        roomy: CGFloat,
        spacious: CGFloat
    ) {
        self.tiny = tiny
        self.squishy = squishy
        self.compact = compact
        self.cozy = cozy
        self.comfortable = comfortable
        self.roomy = roomy
        self.spacious = spacious
    }

    public static let fallback = AnvilSpacing(
        tiny: 2,
        squishy: 4,
        compact: 8,
        cozy: 12,
        comfortable: 16,
        roomy: 24,
        spacious: 32
    )
}
