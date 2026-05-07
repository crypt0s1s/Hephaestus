import Foundation

actor WorkflowRunState {
  private let debugLog: WorkflowDebugLog
  private let debugLogURL: URL
  private let progress: WorkflowProgressHandler?

  private var timeline: [String] = []
  private var stepRecords: [WorkflowStepRecord] = []
  private var nextSequenceOrder = 0

  init(debugLog: WorkflowDebugLog, progress: WorkflowProgressHandler?) {
    self.debugLog = debugLog
    self.debugLogURL = debugLog.directoryURL
    self.progress = progress
  }

  nonisolated func setupHierarchy(
    phaseOrder: Int,
    outcome: WorkflowStepRecordCycleOutcome? = nil
  ) -> WorkflowStepRecordHierarchy {
    WorkflowStepRecordHierarchy(
      groupID: "setup",
      parentID: nil,
      cycleIndex: nil,
      depth: 1,
      phaseOrder: phaseOrder,
      cycleOutcome: outcome
    )
  }

  nonisolated func cycleHierarchy(
    cycle: Int,
    parentID: String? = nil,
    depth: Int = 1,
    phaseOrder: Int,
    outcome: WorkflowStepRecordCycleOutcome? = nil
  ) -> WorkflowStepRecordHierarchy {
    WorkflowStepRecordHierarchy(
      groupID: "cycle-\(cycle)",
      parentID: parentID,
      cycleIndex: cycle,
      depth: depth,
      phaseOrder: phaseOrder,
      cycleOutcome: outcome
    )
  }

  func emit(_ line: String) async {
    timeline.append(line)
    await debugLog.append("[timeline] \(line)\n")
    await debugLog.append(line + "\n", to: "timeline.log")
    await publishProgress()
  }

  func upsertStep(
    id: String,
    title: String,
    status: WorkflowStepRecordStatus,
    summary: String,
    inputPreview: String? = nil,
    outputPreview: String? = nil,
    sortOrder: Int,
    hierarchy: WorkflowStepRecordHierarchy? = nil,
    timeoutSeconds: TimeInterval? = nil
  ) async {
    if let index = stepRecords.firstIndex(where: { $0.id == id }) {
      updateStep(
        at: index,
        title: title,
        status: status,
        summary: summary,
        inputPreview: inputPreview,
        outputPreview: outputPreview,
        sortOrder: sortOrder,
        hierarchy: hierarchy,
        timeoutSeconds: timeoutSeconds
      )
    } else {
      appendStep(
        id: id,
        title: title,
        status: status,
        summary: summary,
        inputPreview: inputPreview,
        outputPreview: outputPreview,
        sortOrder: sortOrder,
        hierarchy: hierarchy,
        timeoutSeconds: timeoutSeconds
      )
    }
    await publishProgress()
  }

  func result(exitCode: Int32, output: String, timedOut: Bool = false) -> ProcessResult {
    let snapshot = stateSnapshot()
    return ProcessResult(
      exitCode: exitCode,
      output: output,
      timeline: snapshot.timeline,
      debugLogURL: debugLogURL,
      timedOut: timedOut,
      stepRecords: snapshot.stepRecords
    )
  }

  private var sortedStepRecords: [WorkflowStepRecord] {
    stepRecords.sorted { $0.sortOrder < $1.sortOrder }
  }

  private func publishProgress() async {
    let snapshot = stateSnapshot()
    await progress?(
      WorkflowRunProgress(
        timeline: snapshot.timeline,
        debugLogURL: debugLogURL,
        stepRecords: snapshot.stepRecords
      ))
  }

  private func stateSnapshot() -> (timeline: String, stepRecords: [WorkflowStepRecord]) {
    (timeline.joined(separator: "\n"), sortedStepRecords)
  }

  private func updateStep(
    at index: Int,
    title: String,
    status: WorkflowStepRecordStatus,
    summary: String,
    inputPreview: String?,
    outputPreview: String?,
    sortOrder: Int,
    hierarchy: WorkflowStepRecordHierarchy?,
    timeoutSeconds: TimeInterval?
  ) {
    let now = Date()
    var updatedHierarchy = hierarchy
    if var replacementHierarchy = updatedHierarchy,
      let existingHierarchy = stepRecords[index].hierarchy {
      replacementHierarchy.sequenceOrder = existingHierarchy.sequenceOrder
      updatedHierarchy = replacementHierarchy
    }

    stepRecords[index].title = title
    stepRecords[index].status = status
    stepRecords[index].summary = summary
    stepRecords[index].sortOrder = sortOrder
    stepRecords[index].timing = updatedTiming(
      from: stepRecords[index].timing,
      status: status,
      timeoutSeconds: timeoutSeconds,
      now: now
    )
    if let inputPreview {
      stepRecords[index].inputPreview = inputPreview
    }
    if let outputPreview {
      stepRecords[index].outputPreview = outputPreview
    }
    if updatedHierarchy != nil {
      stepRecords[index].hierarchy = updatedHierarchy
    }
  }

  private func appendStep(
    id: String,
    title: String,
    status: WorkflowStepRecordStatus,
    summary: String,
    inputPreview: String?,
    outputPreview: String?,
    sortOrder: Int,
    hierarchy: WorkflowStepRecordHierarchy?,
    timeoutSeconds: TimeInterval?
  ) {
    let now = Date()
    var newHierarchy = hierarchy
    if newHierarchy != nil {
      newHierarchy?.sequenceOrder = nextSequenceOrder
      nextSequenceOrder += 1
    }

    stepRecords.append(
      WorkflowStepRecord(
        id: id,
        title: title,
        status: status,
        summary: summary,
        inputPreview: inputPreview,
        outputPreview: outputPreview,
        sortOrder: sortOrder,
        hierarchy: newHierarchy,
        timing: initialTiming(status: status, timeoutSeconds: timeoutSeconds, now: now)
      ))
  }

  private func updatedTiming(
    from currentTiming: WorkflowStepTiming?,
    status: WorkflowStepRecordStatus,
    timeoutSeconds: TimeInterval?,
    now: Date
  ) -> WorkflowStepTiming {
    var timing = currentTiming ?? WorkflowStepTiming()
    if timing.startedAt == nil {
      timing.startedAt = now
    }
    if status == .inProgress {
      timing.finishedAt = nil
    } else if timing.finishedAt == nil {
      timing.finishedAt = now
    }
    if let timeoutSeconds {
      timing.timeoutSeconds = timeoutSeconds
    }
    return timing
  }

  private func initialTiming(
    status: WorkflowStepRecordStatus,
    timeoutSeconds: TimeInterval?,
    now: Date
  ) -> WorkflowStepTiming {
    WorkflowStepTiming(
      startedAt: status == .pending ? nil : now,
      finishedAt: status == .inProgress || status == .pending ? nil : now,
      timeoutSeconds: timeoutSeconds
    )
  }
}
