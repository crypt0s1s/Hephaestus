import Foundation

nonisolated struct WorkflowTimelineNode: Identifiable, Equatable {
  nonisolated enum Kind: Equatable {
    case group
    case parent
    case leaf
    case summary
  }

  let id: String
  var label: String
  var detail: String?
  var status: TimelineDisplayStatus
  var depth: Int
  var isExpandable: Bool
  var record: WorkflowStepRecord?
  var children: [WorkflowTimelineNode]
  var kind: Kind
}

nonisolated struct WorkflowTimelineProjection: Equatable {
  nonisolated static let maxExpandableDepth = 2

  var nodes: [WorkflowTimelineNode]
  var defaultExpandedIDs: Set<String>

  nonisolated static func hasHierarchyMetadata(_ records: [WorkflowStepRecord]) -> Bool {
    records.contains { $0.hierarchy != nil }
  }

  nonisolated static func make(records: [WorkflowStepRecord]) -> WorkflowTimelineProjection {
    let hierarchicalRecords = records.filter { $0.hierarchy != nil }
    guard !hierarchicalRecords.isEmpty else {
      return WorkflowTimelineProjection(nodes: [], defaultExpandedIDs: [])
    }

    var nodes: [WorkflowTimelineNode] = []
    if !setupRecords(in: hierarchicalRecords).isEmpty {
      nodes.append(makeSetupNode(records: setupRecords(in: hierarchicalRecords)))
    }

    let cycleRecords =
      hierarchicalRecords
      .filter { $0.hierarchy?.cycleIndex != nil }
    let cycleIndexes = Set(cycleRecords.compactMap { $0.hierarchy?.cycleIndex }).sorted()
    for cycleIndex in cycleIndexes {
      nodes.append(
        makeCycleNode(
          cycleIndex: cycleIndex,
          records: cycleRecords.filter { $0.hierarchy?.cycleIndex == cycleIndex },
          hasLaterCycle: cycleIndexes.contains { $0 > cycleIndex }
        ))
    }

    let defaultExpandedIDs = defaultExpandedIDs(for: nodes)
    return WorkflowTimelineProjection(nodes: nodes, defaultExpandedIDs: defaultExpandedIDs)
  }

  nonisolated func visibleNodes(collapsedIDs: Set<String>) -> [WorkflowTimelineNode] {
    nodes.flatMap { visibleNodes(from: $0, collapsedIDs: collapsedIDs) }
  }

  private nonisolated func visibleNodes(from node: WorkflowTimelineNode, collapsedIDs: Set<String>)
    -> [WorkflowTimelineNode] {
    guard node.isExpandable, !collapsedIDs.contains(node.id) else {
      return [node]
    }
    return [node] + node.children.flatMap { visibleNodes(from: $0, collapsedIDs: collapsedIDs) }
  }

  nonisolated static func collapsedIDs(
    defaultExpandedIDs: Set<String>, manuallyExpandedIDs: Set<String>,
    manuallyCollapsedIDs: Set<String>, in nodes: [WorkflowTimelineNode]
  ) -> Set<String> {
    let expandableIDs = allExpandableIDs(in: nodes)
    return
      expandableIDs
      .subtracting(defaultExpandedIDs)
      .subtracting(manuallyExpandedIDs)
      .union(manuallyCollapsedIDs)
  }

  private nonisolated static func setupRecords(in records: [WorkflowStepRecord])
    -> [WorkflowStepRecord] {
    records.filter { record in
      record.hierarchy?.groupID == "setup"
        || (record.hierarchy?.cycleIndex == nil && record.hierarchy?.parentID == nil)
    }
  }

  private nonisolated static func makeSetupNode(records: [WorkflowStepRecord])
    -> WorkflowTimelineNode {
    let children = leafNodes(from: records, fallbackDepth: 1)
    return WorkflowTimelineNode(
      id: "setup",
      label: "Setup",
      detail: aggregateDetail(for: children),
      status: aggregateStatus(children.map(\.status)),
      depth: 0,
      isExpandable: !children.isEmpty,
      record: nil,
      children: children,
      kind: .group
    )
  }

  private nonisolated static func makeCycleNode(
    cycleIndex: Int, records: [WorkflowStepRecord], hasLaterCycle: Bool
  ) -> WorkflowTimelineNode {
    let directRecords = records.filter {
      ($0.hierarchy?.parentID).isNilOrEmpty && ($0.hierarchy?.depth ?? 1) <= 1
    }
    let parentIDs =
      records
      .compactMap { $0.hierarchy?.parentID }
      .filter { !$0.isEmpty }
    let uniqueParentIDs = Array(Set(parentIDs)).sorted { lhs, rhs in
      sortKey(
        parentSortKey(parentID: lhs, records: records),
        isLessThan: parentSortKey(parentID: rhs, records: records))
    }

    var children = leafNodes(from: directRecords, fallbackDepth: 1)
    for parentID in uniqueParentIDs {
      children.append(
        makeParentNode(
          parentID: parentID, records: records.filter { $0.hierarchy?.parentID == parentID }))
    }
    children.sort(by: nodeSort)

    let outcome = aggregateCycleOutcome(
      records: records, children: children, hasLaterCycle: hasLaterCycle)
    return WorkflowTimelineNode(
      id: "cycle-\(cycleIndex)",
      label: cycleIndex == 0
        ? "Cycle 0 - Initial implementation" : "Cycle \(cycleIndex) - Fix cycle \(cycleIndex)",
      detail: aggregateDetail(for: children),
      status: status(for: outcome, childStatuses: children.map(\.status)),
      depth: 0,
      isExpandable: !children.isEmpty,
      record: nil,
      children: children,
      kind: .group
    )
  }

  private nonisolated static func makeParentNode(parentID: String, records: [WorkflowStepRecord])
    -> WorkflowTimelineNode {
    let visibleRecords = records.filter { ($0.hierarchy?.depth ?? 2) <= maxExpandableDepth }
    let clippedRecords = records.filter { ($0.hierarchy?.depth ?? 2) > maxExpandableDepth }
    var children = leafNodes(from: visibleRecords, fallbackDepth: 2)

    if !clippedRecords.isEmpty {
      children.append(
        WorkflowTimelineNode(
          id: "\(parentID)-depth-summary",
          label: "Nested work",
          detail:
            "\(clippedRecords.count) deeper update\(clippedRecords.count == 1 ? "" : "s") summarized.",
          status: aggregateStatus(
            clippedRecords.map { TimelineDisplayStatus(recordStatus: $0.status) }),
          depth: maxExpandableDepth,
          isExpandable: false,
          record: nil,
          children: [],
          kind: .summary
        ))
    }

    children.sort(by: nodeSort)
    return WorkflowTimelineNode(
      id: parentID,
      label: label(forParentID: parentID),
      detail: aggregateDetail(for: children),
      status: aggregateStatus(children.map(\.status)),
      depth: 1,
      isExpandable: !children.isEmpty,
      record: nil,
      children: children,
      kind: .parent
    )
  }

  private nonisolated static func leafNodes(from records: [WorkflowStepRecord], fallbackDepth: Int)
    -> [WorkflowTimelineNode] {
    records.sorted(by: recordSort).map { record in
      let rawDepth = record.hierarchy?.depth ?? fallbackDepth
      return WorkflowTimelineNode(
        id: record.id,
        label: record.title,
        detail: record.summary,
        status: TimelineDisplayStatus(recordStatus: record.status),
        depth: min(rawDepth, maxExpandableDepth),
        isExpandable: false,
        record: record,
        children: [],
        kind: .leaf
      )
    }
  }

  private nonisolated static func label(forParentID parentID: String) -> String {
    if parentID.localizedCaseInsensitiveContains("review") {
      return "Step 3 - Review"
    }
    return
      parentID
      .split(separator: "-")
      .map { $0.capitalized }
      .joined(separator: " ")
  }

  private nonisolated static func aggregateCycleOutcome(
    records: [WorkflowStepRecord], children: [WorkflowTimelineNode], hasLaterCycle: Bool
  ) -> WorkflowStepRecordCycleOutcome? {
    let outcomes = records.compactMap { $0.hierarchy?.cycleOutcome }
    if outcomes.contains(.terminalFailed) {
      return .terminalFailed
    }
    if outcomes.contains(.needsFix) || (hasLaterCycle && children.contains { $0.status == .failed }) {
      return .needsFix
    }
    if outcomes.contains(.running) {
      return .running
    }
    if outcomes.contains(.succeeded) {
      return .succeeded
    }
    return nil
  }

  private nonisolated static func status(
    for outcome: WorkflowStepRecordCycleOutcome?, childStatuses: [TimelineDisplayStatus]
  ) -> TimelineDisplayStatus {
    switch outcome {
    case .running:
      return .inProgress
    case .succeeded:
      return .succeeded
    case .needsFix:
      return .needsFix
    case .terminalFailed:
      return .failed
    case nil:
      return aggregateStatus(childStatuses)
    }
  }

  private nonisolated static func aggregateStatus(_ statuses: [TimelineDisplayStatus])
    -> TimelineDisplayStatus {
    if statuses.contains(.inProgress) { return .inProgress }
    if statuses.contains(.failed) { return .failed }
    if statuses.contains(.needsFix) { return .needsFix }
    if !statuses.isEmpty, statuses.allSatisfy({ $0 == .succeeded }) { return .succeeded }
    return .pending
  }

  private nonisolated static func aggregateDetail(for children: [WorkflowTimelineNode]) -> String? {
    guard !children.isEmpty else { return nil }
    let counts = Dictionary(grouping: children, by: \.status).mapValues(\.count)
    if children.allSatisfy({
      $0.kind == .leaf && $0.label.localizedCaseInsensitiveContains("Reviewer")
    }),
      counts.keys.allSatisfy({ $0 == .succeeded }) {
      return "\(children.count) reviewers complete"
    }
    let ordered: [(TimelineDisplayStatus, String)] = [
      (.inProgress, "running"),
      (.failed, "failed"),
      (.needsFix, "needs fix"),
      (.succeeded, "complete"),
      (.pending, "pending"),
    ]
    let parts = ordered.compactMap { status, label in
      counts[status].map { "\($0) \(label)" }
    }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  private nonisolated static func defaultExpandedIDs(for nodes: [WorkflowTimelineNode]) -> Set<
    String
  > {
    var expanded = Set<String>()
    for node in nodes {
      if shouldExpandByDefault(node) {
        expanded.insert(node.id)
      }
      for child in node.children where shouldExpandByDefault(child) {
        expanded.insert(child.id)
      }
    }
    return expanded
  }

  private nonisolated static func shouldExpandByDefault(_ node: WorkflowTimelineNode) -> Bool {
    guard node.isExpandable else { return false }
    switch node.status {
    case .inProgress, .failed:
      return true
    case .pending, .succeeded, .needsFix:
      return false
    }
  }

  private nonisolated static func allExpandableIDs(in nodes: [WorkflowTimelineNode]) -> Set<String> {
    Set(
      nodes.flatMap { node -> [String] in
        let own = node.isExpandable ? [node.id] : []
        return own + Array(allExpandableIDs(in: node.children))
      })
  }

  private nonisolated static func recordSort(_ lhs: WorkflowStepRecord, _ rhs: WorkflowStepRecord)
    -> Bool {
    sortKey(recordSortKey(lhs), isLessThan: recordSortKey(rhs))
  }

  private nonisolated static func recordSortKey(_ record: WorkflowStepRecord) -> [Int] {
    let hierarchy = record.hierarchy
    return [
      hierarchy?.cycleIndex ?? -1,
      hierarchy?.phaseOrder ?? record.sortOrder,
      hierarchy?.depth ?? 0,
      hierarchy?.sequenceOrder ?? record.sortOrder,
      record.sortOrder,
    ]
  }

  private nonisolated static func nodeSort(_ lhs: WorkflowTimelineNode, _ rhs: WorkflowTimelineNode)
    -> Bool {
    sortKey(nodeSortKey(lhs), isLessThan: nodeSortKey(rhs))
  }

  private nonisolated static func nodeSortKey(_ node: WorkflowTimelineNode) -> [Int] {
    if let record = node.record {
      return recordSortKey(record)
    }
    let childKey = node.children.first.flatMap { child -> [Int]? in
      if let record = child.record {
        return recordSortKey(record)
      }
      return nil
    }
    return childKey ?? [Int.max]
  }

  private nonisolated static func parentSortKey(parentID: String, records: [WorkflowStepRecord])
    -> [Int] {
    records
      .filter { $0.hierarchy?.parentID == parentID }
      .map(recordSortKey)
      .min { sortKey($0, isLessThan: $1) } ?? [Int.max]
  }

  private nonisolated static func sortKey(_ lhs: [Int], isLessThan rhs: [Int]) -> Bool {
    for (left, right) in zip(lhs, rhs) {
      if left != right {
        return left < right
      }
    }
    return lhs.count < rhs.count
  }
}

nonisolated extension Optional where Wrapped == String {
  fileprivate var isNilOrEmpty: Bool {
    self?.isEmpty ?? true
  }
}
