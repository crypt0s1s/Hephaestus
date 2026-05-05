import Foundation

public struct AnvilRadii: Sendable {
    public var small: CGFloat
    public var medium: CGFloat
    public var large: CGFloat

    public init(small: CGFloat, medium: CGFloat, large: CGFloat) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    public static let workbench = AnvilRadii(
        small: 6,
        medium: 8,
        large: 10
    )

    public static let hephaestus = AnvilRadii.workbench
}
