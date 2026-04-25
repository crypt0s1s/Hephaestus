import Anvil
import ChatContracts
import Foundation

public enum ChatLinkProbe {
    public static func openChat(runID: UUID?) throws -> NavigationIntent {
        try .push(AnyRouteInput(ChatRouteInput(runID: runID)))
    }
}
