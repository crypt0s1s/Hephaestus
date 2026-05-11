import Foundation
import Testing

@testable import Hephaestus

struct WorkflowTimelineProjectionTests {
    @Test
    func projectionGroupsSetupCyclesAndReviewersInCycleMajorOrder() throws {
        let records = [
            record(
                "setup-plan", "Plan validation", .succeeded, groupID: "setup", cycle: nil, depth: 1,
                phase: 0, sequence: 0),
            record(
                "cycle-1-implementer", "Step 1 - Implementer", .inProgress, groupID: "cycle-1", cycle: 1,
                depth: 1, phase: 10, sequence: 6, outcome: .running),
            record(
                "cycle-0-feedback", "Step 4 - Feedback relay", .succeeded, groupID: "cycle-0", cycle: 0,
                depth: 1, phase: 40, sequence: 5, outcome: .needsFix),
            record(
                "cycle-0-reviewer-b", "Step 3.2 - Reviewer B", .failed, groupID: "cycle-0",
                parentID: "cycle-0-review", cycle: 0, depth: 2, phase: 31, sequence: 4),
            record(
                "cycle-0-build", "Step 2 - Build", .succeeded, groupID: "cycle-0", cycle: 0, depth: 1,
                phase: 20, sequence: 2),
            record(
                "cycle-0-reviewer-a", "Step 3.1 - Reviewer A", .failed, groupID: "cycle-0",
                parentID: "cycle-0-review", cycle: 0, depth: 2, phase: 30, sequence: 3),
            record(
                "cycle-0-implementer", "Step 1 - Implementer", .succeeded, groupID: "cycle-0", cycle: 0,
                depth: 1, phase: 10, sequence: 1),
        ]

        let projection = WorkflowTimelineProjection.make(records: records)

        #expect(projection.nodes.map { $0.id } == ["setup", "cycle-0", "cycle-1"])
        let cycle0 = try #require(projection.nodes.first { $0.id == "cycle-0" })
        #expect(cycle0.status == TimelineDisplayStatus.needsFix)
        #expect(
            cycle0.children.map { $0.label } == [
                "Step 1 - Implementer",
                "Step 2 - Build",
                "Step 3 - Review",
                "Step 4 - Feedback relay",
            ])
        let review = try #require(cycle0.children.first { $0.id == "cycle-0-review" })
        #expect(review.children.map { $0.label } == ["Step 3.1 - Reviewer A", "Step 3.2 - Reviewer B"])
    }

    @Test
    func projectionDistinguishesNeedsFixFromTerminalFailureDefaults() throws {
        let continuingRecords = [
            record(
                "cycle-0-reviewer", "Reviewer A", .failed, groupID: "cycle-0", parentID: "cycle-0-review",
                cycle: 0, depth: 2, phase: 30, sequence: 0),
            record(
                "cycle-0-feedback", "Step 4 - Feedback relay", .succeeded, groupID: "cycle-0", cycle: 0,
                depth: 1, phase: 40, sequence: 1, outcome: .needsFix),
            record(
                "cycle-1-implementer", "Step 1 - Implementer", .inProgress, groupID: "cycle-1", cycle: 1,
                depth: 1, phase: 10, sequence: 2, outcome: .running),
        ]
        let continuing = WorkflowTimelineProjection.make(records: continuingRecords)

        let cycle0 = try #require(continuing.nodes.first { $0.id == "cycle-0" })
        let cycle1 = try #require(continuing.nodes.first { $0.id == "cycle-1" })
        #expect(cycle0.status == TimelineDisplayStatus.needsFix)
        #expect(!continuing.defaultExpandedIDs.contains(cycle0.id))
        #expect(continuing.defaultExpandedIDs.contains(cycle1.id))

        let terminal = WorkflowTimelineProjection.make(records: [
            record(
                "cycle-0-build", "Step 2 - Build", .failed, groupID: "cycle-0", cycle: 0, depth: 1,
                phase: 20, sequence: 0, outcome: .terminalFailed)
        ])
        let terminalCycle = try #require(terminal.nodes.first)
        #expect(terminalCycle.status == TimelineDisplayStatus.failed)
        #expect(terminal.defaultExpandedIDs.contains(terminalCycle.id))
    }

    @Test
    func projectionCollapseOverridesAndDepthTwoSummaryAreStable() throws {
        let projection = WorkflowTimelineProjection.make(records: [
            record(
                "cycle-0-reviewer", "Reviewer A", .succeeded, groupID: "cycle-0",
                parentID: "cycle-0-review", cycle: 0, depth: 2, phase: 30, sequence: 0, outcome: .succeeded),
            record(
                "cycle-0-deep-attempt", "Attempt 1", .succeeded, groupID: "cycle-0",
                parentID: "cycle-0-review", cycle: 0, depth: 3, phase: 31, sequence: 1),
        ])

        let defaultCollapsed = WorkflowTimelineProjection.collapsedIDs(
            defaultExpandedIDs: projection.defaultExpandedIDs,
            manuallyExpandedIDs: [],
            manuallyCollapsedIDs: [],
            in: projection.nodes
        )
        #expect(defaultCollapsed.contains("cycle-0"))

        let manuallyExpanded = WorkflowTimelineProjection.collapsedIDs(
            defaultExpandedIDs: projection.defaultExpandedIDs,
            manuallyExpandedIDs: ["cycle-0"],
            manuallyCollapsedIDs: [],
            in: projection.nodes
        )
        #expect(!manuallyExpanded.contains("cycle-0"))

        let visible = projection.visibleNodes(collapsedIDs: ["cycle-0-review"])
        #expect(visible.map { $0.id }.contains("cycle-0-review"))
        let review = try #require(projection.nodes.first?.children.first { $0.id == "cycle-0-review" })
        #expect(
            review.children.contains { $0.kind == WorkflowTimelineNode.Kind.summary && $0.depth == 2 })
    }

    @Test
    func legacyRecordsKeepFlatFallbackRows() {
        let rows = TimelineDisplayRowsBuilder(
            timeline: "",
            stepRecords: [
                WorkflowStepRecord(
                    id: "b", title: "Second", status: .pending, summary: "two", sortOrder: 2),
                WorkflowStepRecord(
                    id: "a", title: "First", status: .succeeded, summary: "one", sortOrder: 1),
            ]
        ).rows

        #expect(!WorkflowTimelineProjection.hasHierarchyMetadata(rows.compactMap { $0.record }))
        #expect(rows.map { $0.id } == ["a", "b"])
        #expect(rows.allSatisfy { !$0.isExpandable && $0.depth == 0 })
    }

    private func record(
        _ id: String,
        _ title: String,
        _ status: WorkflowStepRecordStatus,
        groupID: String,
        parentID: String? = nil,
        cycle: Int?,
        depth: Int,
        phase: Int,
        sequence: Int,
        outcome: WorkflowStepRecordCycleOutcome? = nil
    ) -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: id,
            title: title,
            status: status,
            summary: title,
            sortOrder: sequence,
            hierarchy: WorkflowStepRecordHierarchy(
                groupID: groupID,
                parentID: parentID,
                cycleIndex: cycle,
                depth: depth,
                phaseOrder: phase,
                sequenceOrder: sequence,
                cycleOutcome: outcome
            )
        )
    }
}
