import Anvil
import HephaestusObservation
import HephaestusRuntime
import SwiftUI
import TaskWorkspaceContracts

public enum TaskWorkspaceRoutes {
    public static var registration: RouteRegistration {
        RouteRegistration(
            routeID: TaskWorkspaceRouteInput.routeID,
            version: TaskWorkspaceRouteInput.version,
            decodeDeepLink: { url in
                guard url.host == "route",
                    url.pathComponents.first(where: { $0 != "/" }) == TaskWorkspaceRouteInput.routeID
                else { return nil }
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let taskIDValue = components?.queryItems?.first(where: { $0.name == "taskID" })?.value
                let taskID: UUID?
                if let taskIDValue {
                    guard let parsedTaskID = UUID(uuidString: taskIDValue) else {
                        return nil
                    }
                    taskID = parsedTaskID
                } else {
                    taskID = nil
                }
                return try AnyRouteInput(TaskWorkspaceRouteInput(taskID: taskID))
            },
            build: { anyInput, context in
                let input = try anyInput.decode(TaskWorkspaceRouteInput.self)
                return try buildTaskWorkspace(
                    input: input,
                    context: context
                )
            }
        )
    }

    public static var settingsModalRegistration: ModalRegistration {
        ModalRegistration(
            modalID: TaskWorkspaceSettingsModalInput.modalID,
            version: TaskWorkspaceSettingsModalInput.version,
            decodeDeepLink: { url in
                guard url.host == "modal",
                    url.pathComponents.first(where: { $0 != "/" }) == TaskWorkspaceSettingsModalInput.modalID
                else { return nil }
                return try AnyModalInput(TaskWorkspaceSettingsModalInput())
            },
            build: { _, context in
                let workspace = try context.dependency(TaskWorkspaceService.self)
                let input = TaskWorkspaceRouteInput(taskID: workspace.snapshot.selectedTaskID)
                return try buildTaskWorkspace(input: input, context: context)
            }
        )
    }

    @MainActor
    private static func buildTaskWorkspace(
        input: TaskWorkspaceRouteInput,
        context: RouteBuildContext
    ) throws -> AnyView {
        let loadProviderSettings = try? context.dependency(LoadProviderSettingsUseCase.self)
        let saveProviderSettings = try? context.dependency(SaveProviderSettingsUseCase.self)
        let clearProviderSettings = try? context.dependency(ClearProviderSettingsUseCase.self)
        let validateProviderSettings = try? context.dependency(ValidateProviderSettingsUseCase.self)
        let loadRunInspection = try? context.dependency(LoadRunInspectionUseCase.self)
        let workspace = try context.dependency(TaskWorkspaceService.self)
        return AnyView(
            Page(
                interactor: TaskWorkspaceInteractor(
                    input: input,
                    workspace: workspace,
                    loadProviderSettings: loadProviderSettings,
                    saveProviderSettings: saveProviderSettings,
                    clearProviderSettings: clearProviderSettings,
                    validateProviderSettings: validateProviderSettings,
                    loadRunInspection: loadRunInspection
                ),
                view: TaskWorkspacePage.init
            )
        )
    }
}
