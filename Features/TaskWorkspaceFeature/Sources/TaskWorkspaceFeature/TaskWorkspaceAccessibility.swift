import SwiftUI

enum ConversationScrollTarget {
    static let bottom = "conversation-scroll-bottom"
    static let coordinateSpace = "conversation-scroll-coordinate-space"
    static let pinnedThreshold: CGFloat = 44
}

enum TaskWorkspaceAccessibilityID {
    static let historyList = "task.list"
    static let historyEmptyState = "task.list.emptyState"
    static let newTaskButton = "task.new"
    static let settingsButton = "task.provider.settings"
    static let inspectorButton = "task.inspector.open"
    static let transcript = "conversation.transcript"
    static let emptyState = "task.emptyState"
    static let messageInput = "conversation.messageInput"
    static let sendButton = "conversation.sendButton"
    static let runningStatus = "task.runningStatus"
    static let errorBanner = "task.errorBanner"
    static let persistenceError = "task.persistence.error"
    static let providerBaseURL = "provider.baseURL"
    static let providerAPIKey = "provider.apiKey"
    static let providerModel = "provider.model"
    static let providerValidate = "provider.validate"
    static let providerSave = "provider.save"
    static let providerClear = "provider.clear"
    static let inspectorPanel = "inspector.panel"
    static let inspectorTimeline = "inspector.timeline"
}
