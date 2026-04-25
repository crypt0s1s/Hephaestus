import Anvil
import Foundation

public struct ChatRouteInput: RouteInput {
    public static let routeID = "hephaestus.chat.main"
    public static let version = 1

    public let runID: UUID?

    public init(runID: UUID?) {
        self.runID = runID
    }
}

public struct ChatSettingsModalInput: ModalInput {
    public static let modalID = "hephaestus.chat.settings"
    public static let version = 1

    public init() {}
}
