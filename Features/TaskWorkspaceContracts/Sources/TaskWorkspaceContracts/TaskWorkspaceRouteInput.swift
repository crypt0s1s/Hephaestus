import Anvil
import Foundation

public struct TaskWorkspaceRouteInput: RouteInput {
    public static let routeID = "hephaestus.task.workspace"
    public static let version = 1

    public let taskID: UUID?

    public init(taskID: UUID?) {
        self.taskID = taskID
    }
}

public struct TaskWorkspaceSettingsModalInput: ModalInput {
    public static let modalID = "hephaestus.task.settings"
    public static let version = 1

    public init() {}
}
