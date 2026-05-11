import Anvil
import Foundation
import HephaestusObservation
import HephaestusRuntime
import TaskWorkspaceContracts

@MainActor
public final class TaskWorkspaceInteractor: Interactor {
    @Published public private(set) var state: TaskWorkspaceState

    private let workspace: TaskWorkspaceService
    private let initialRunID: UUID?
    private let loadProviderSettings: LoadProviderSettingsUseCase?
    private let saveProviderSettings: SaveProviderSettingsUseCase?
    private let clearProviderSettings: ClearProviderSettingsUseCase?
    private let validateProviderSettings: ValidateProviderSettingsUseCase?
    private let loadRunInspection: LoadRunInspectionUseCase?
    private let subscribeToWorkspace: Bool
    private let taskScope = PageTaskScope()
    private var didLoadInitialState = false
    private var workspaceTaskID: UUID?
    private var lifecycleTaskID: UUID?

    public init(
        input: TaskWorkspaceRouteInput,
        workspace: TaskWorkspaceService,
        loadProviderSettings: LoadProviderSettingsUseCase? = nil,
        saveProviderSettings: SaveProviderSettingsUseCase? = nil,
        clearProviderSettings: ClearProviderSettingsUseCase? = nil,
        validateProviderSettings: ValidateProviderSettingsUseCase? = nil,
        loadRunInspection: LoadRunInspectionUseCase? = nil,
        subscribeToWorkspace: Bool = true
    ) {
        self.workspace = workspace
        self.initialRunID = input.taskID
        self.loadProviderSettings = loadProviderSettings
        self.saveProviderSettings = saveProviderSettings
        self.clearProviderSettings = clearProviderSettings
        self.validateProviderSettings = validateProviderSettings
        self.loadRunInspection = loadRunInspection
        self.subscribeToWorkspace = subscribeToWorkspace
        self.state = TaskWorkspaceState(runID: input.taskID)
    }

    public func handle(_ action: TaskWorkspaceAction) {
        taskScope.run { [weak self] in
            await self?.handleAction(action)
        }
    }

    public func onAppear() {
        cancelPageTask(lifecycleTaskID)
        lifecycleTaskID = nil
        if didLoadInitialState {
            if subscribeToWorkspace, workspaceTaskID == nil {
                attachToWorkspace()
            }
            return
        }

        didLoadInitialState = true
        lifecycleTaskID = runPageTask { [weak self] in
            await self?.loadInitialState()
        }
    }

    public func onDisappear() {
        cancelPageTask(lifecycleTaskID)
        lifecycleTaskID = nil
        detachWorkspace()
        taskScope.cancelAll()
    }

    public func handleAction(_ action: TaskWorkspaceAction) async {
        switch action {
        case .changeDraft(let text):
            handleChangeDraft(text)
        case .tapSend:
            await handleTapSend()
        case .tapNewTask:
            await handleTapNewTask()
        case .tapTask(let id):
            await handleTapTask(id)
        case .tapCancel:
            handleTapCancel()
        case .tapSettings:
            await handleTapSettings()
        case .dismissSettings:
            setState { $0.providerSettings.isPresented = false }
        case .changeProviderBaseURL(let value):
            updateProviderSettingsDraft { $0.baseURLString = value }
        case .changeProviderAPIKey(let value):
            updateProviderSettingsDraft { $0.apiKeyReplacement = value }
        case .changeProviderModel(let value):
            updateProviderSettingsDraft { $0.model = value }
        case .validateProviderSettings:
            await handleValidateProviderSettings()
        case .saveProviderSettings:
            await handleSaveProviderSettings()
        case .clearProviderSettings:
            await handleClearProviderSettings()
        case .tapInspector:
            await handleTapInspector()
        case .dismissInspector:
            setState { $0.inspector.isPresented = false }
        }
    }

    private func updateProviderSettingsDraft(
        _ update: (inout ProviderSettingsPanelState) -> Void
    ) {
        setState {
            update(&$0.providerSettings)
            $0.providerSettings.validation = .idle
        }
    }

    public func setState(_ update: (inout TaskWorkspaceState) -> Void) {
        update(&state)
    }

    @discardableResult
    public func runPageTask(_ operation: @escaping @MainActor () async -> Void) -> UUID {
        taskScope.run(operation)
    }

    public func cancelPageTask(_ id: UUID?) {
        guard let id else { return }
        taskScope.cancel(id)
    }

    private func loadInitialState() async {
        await loadProviderSettingsIntoState(present: false)
        guard subscribeToWorkspace else { return }
        await workspace.refreshSummaries()
        if let initialRunID {
            await workspace.selectTask(initialRunID, force: true)
        }
        if workspaceTaskID == nil {
            attachToWorkspace()
        }
    }

    private func handleChangeDraft(_ text: String) {
        setState { state in
            state.draftText = text
        }
    }

    private func handleTapSend() async {
        guard !state.isRunning else { return }
        let text = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let runID = state.runID, workspace.snapshot.selectedTaskID != runID {
            let selected = await workspace.selectTask(runID, force: true)
            apply(workspace.snapshot)
            guard selected else {
                return
            }
        }

        setState { state in
            state.draftText = ""
            state.isRunning = true
            state.errorMessage = nil
        }

        let accepted = await workspace.sendMessage(text)
        apply(workspace.snapshot)
        if !accepted {
            setState { $0.isRunning = false }
        }
    }

    private func handleTapNewTask() async {
        let changed = await workspace.createNewTask(title: nil)
        apply(workspace.snapshot)
        if changed {
            setState {
                $0.draftText = ""
                $0.inspector = RunInspectorPanelState()
            }
        }
    }

    private func handleTapTask(_ id: UUID) async {
        guard state.runID != id else { return }
        let changed = await workspace.selectTask(id)
        apply(workspace.snapshot)
        if changed {
            setState {
                $0.draftText = ""
                $0.inspector = RunInspectorPanelState()
            }
        }
    }

    private func handleTapCancel() {
        workspace.cancelSelectedTurn()
        apply(workspace.snapshot)
    }

    private func attachToWorkspace() {
        cancelPageTask(workspaceTaskID)
        workspaceTaskID = runPageTask { [weak self] in
            guard let self else { return }
            for await snapshot in workspace.subscribeSnapshots() {
                apply(snapshot)
            }
        }
    }

    private func detachWorkspace() {
        cancelPageTask(workspaceTaskID)
        workspaceTaskID = nil
    }

    private func apply(_ snapshot: TaskWorkspaceSnapshot) {
        setState { state in
            if let currentSnapshot = state.workspaceSnapshot,
                snapshot.revision < currentSnapshot.revision {
                return
            }
            state.workspaceSnapshot = snapshot
            if let selectedTaskID = snapshot.selectedTaskID {
                state.runID = selectedTaskID
                state.selectedSnapshot = snapshot.selectedTask
                state.messages = snapshot.selectedTask?.messages ?? []
                state.isRunning = snapshot.selectedTask?.isRunning ?? false
                state.errorMessage =
                    snapshot.selectedTask?.errorMessage ?? snapshot.selectionError?.description
            } else if state.runID == nil, !state.isRunning {
                state.selectedSnapshot = nil
                state.messages = []
                state.isRunning = false
                state.errorMessage = snapshot.selectionError?.description
            } else if let selectionError = snapshot.selectionError {
                state.errorMessage = selectionError.description
            }
            state.sessions = snapshot.sessions.mapError(TaskWorkspaceError.init)
        }
    }

    private func handleTapSettings() async {
        await loadProviderSettingsIntoState(present: true)
    }

    private func loadProviderSettingsIntoState(present: Bool) async {
        do {
            let summary = try await loadProviderSettings?.loadProviderSettings()
            setState { state in
                state.providerSettings.isPresented = present || state.providerSettings.isPresented
                state.providerSettings.baseURLString =
                    summary?.baseURLString ?? state.providerSettings.baseURLString
                state.providerSettings.model = summary?.model ?? state.providerSettings.model
                state.providerSettings.apiKeyReplacement = ""
                state.providerSettings.hasSavedAPIKey = summary?.hasSavedAPIKey ?? false
                state.providerSettings.validatedAt = summary?.validatedAt
                state.providerSettings.validation = .idle
                state.providerSettings.errorMessage = nil
            }
        } catch {
            setState { state in
                state.providerSettings.isPresented = present || state.providerSettings.isPresented
                state.providerSettings.errorMessage = String(describing: error)
            }
        }
    }

    private func handleValidateProviderSettings() async {
        guard let validateProviderSettings else { return }
        let draft = currentProviderDraft()
        setState {
            $0.providerSettings.validation = .validating
            $0.providerSettings.errorMessage = nil
        }
        let result = await validateProviderSettings.validateProviderSettings(draft)
        setState { state in
            switch result {
            case .success:
                state.providerSettings.validation = .success("Provider validated.")
            case .failure(let message):
                state.providerSettings.validation = .failure(message)
            }
        }
    }

    private func handleSaveProviderSettings() async {
        guard let saveProviderSettings else { return }
        let draft = currentProviderDraft()
        setState {
            $0.providerSettings.isSaving = true
            $0.providerSettings.errorMessage = nil
        }

        let validation = await validateProviderSettings?.validateProviderSettings(draft) ?? .success
        guard validation == .success else {
            setState { state in
                if case .failure(let message) = validation {
                    state.providerSettings.validation = .failure(message)
                }
                state.providerSettings.isSaving = false
            }
            return
        }

        do {
            let validatedAt = Date()
            try await saveProviderSettings.saveProviderSettings(draft, validatedAt: validatedAt)
            setState { state in
                state.providerSettings.hasSavedAPIKey =
                    state.providerSettings.apiKeyReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    ? state.providerSettings.hasSavedAPIKey
                    : true
                state.providerSettings.apiKeyReplacement = ""
                state.providerSettings.validatedAt = validatedAt
                state.providerSettings.validation = .success("Provider settings saved.")
                state.providerSettings.isSaving = false
                state.providerSettings.isPresented = false
            }
        } catch {
            setState { state in
                state.providerSettings.errorMessage = String(describing: error)
                state.providerSettings.isSaving = false
            }
        }
    }

    private func handleClearProviderSettings() async {
        guard let clearProviderSettings else { return }
        do {
            try await clearProviderSettings.clearProviderSettings()
            setState { state in
                state.providerSettings = ProviderSettingsPanelState(isPresented: true)
            }
        } catch {
            setState { $0.providerSettings.errorMessage = String(describing: error) }
        }
    }

    private func handleTapInspector() async {
        guard let runID = state.runID, let loadRunInspection else { return }
        setState {
            $0.inspector.isPresented = true
            $0.inspector.loadState = .loading(placeholder: $0.inspector.inspection)
        }
        do {
            let inspection = try await loadRunInspection.loadRunInspection(runID: runID)
            setState {
                $0.inspector.loadState = .loaded(inspection)
            }
        } catch {
            setState {
                $0.inspector.loadState = .error(TaskWorkspaceError(error))
            }
        }
    }

    private func currentProviderDraft() -> ProviderSettingsDraft {
        ProviderSettingsDraft(
            baseURLString: state.providerSettings.baseURLString,
            apiKey: state.providerSettings.apiKeyReplacement.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).nilIfEmpty,
            model: state.providerSettings.model
        )
    }
}
