import Foundation

nonisolated enum TimelineDisplayStatus: Hashable {
  case pending
  case inProgress
  case succeeded
  case failed
  case needsFix

  nonisolated init(recordStatus: WorkflowStepRecordStatus) {
    switch recordStatus {
    case .pending:
      self = .pending
    case .inProgress:
      self = .inProgress
    case .succeeded:
      self = .succeeded
    case .needsFix:
      self = .needsFix
    case .failed:
      self = .failed
    }
  }
}

nonisolated struct TimelineDisplayRow: Identifiable {
  let id: String
  var label: String
  var detail: String?
  var status: TimelineDisplayStatus
  var sortOrder: Int
  var record: WorkflowStepRecord?
  var depth: Int = 0
  var isExpandable: Bool = false
  var isExpanded: Bool = false
}
