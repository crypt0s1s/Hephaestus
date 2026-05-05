import Foundation

public struct AnvilMotion: Sendable {
    public var quick: TimeInterval
    public var standard: TimeInterval

    public init(quick: TimeInterval, standard: TimeInterval) {
        self.quick = quick
        self.standard = standard
    }

    public static let workbench = AnvilMotion(
        quick: 0.12,
        standard: 0.18
    )

    public static let hephaestus = AnvilMotion.workbench
}
