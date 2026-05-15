import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningInteractionReviewGateTests {
    @Test
    func missingDraftCandidateEntersActionableNeedsOutputGate() {
        let candidate = PlanningInteractionState.makePlanningDraftCandidate()

        let gateState = PlanningInteractionGateEvaluator.evaluate(candidate: candidate)

        guard case .needsOutput(let issue) = gateState else {
            Issue.record("Expected missing draft to enter needsOutput.")
            return
        }
        #expect(issue.reason == .missing)
        #expect(issue.recoveryActions.contains(.requestAgentRevision(outputID: candidate.outputID)))
        #expect(issue.recoveryActions.contains(.editOutput(outputID: candidate.outputID)))
        #expect(issue.recoveryActions.contains(.pasteOutput(outputID: candidate.outputID)))
    }

    @Test
    func plannerTurnWithoutDraftArtifactRequiresOutputWhenNoCandidateExists() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let store = PlanningPlanArtifactStore()
        let artifact = try store.prepareDraftArtifact(project: project, sessionID: interaction.sessionID)

        let settlement = PlanningReviewPrototypeTurnSettlement(artifactStore: store).settle(
            draftArtifact: artifact,
            interaction: interaction
        )

        #expect(settlement.proposedPlan == nil)
        #expect(settlement.shouldRequireOutput)
    }

    @Test
    func plannerTurnSettlementLoadsDraftArtifactInsteadOfChatOutput() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let store = PlanningPlanArtifactStore()
        let artifact = try store.prepareDraftArtifact(project: project, sessionID: interaction.sessionID)
        try validPlanMarkdown.write(to: artifact.fileURL, atomically: true, encoding: .utf8)

        let settlement = PlanningReviewPrototypeTurnSettlement(artifactStore: store).settle(
            draftArtifact: artifact,
            interaction: interaction
        )

        #expect(settlement.proposedPlan == validPlanMarkdown)
        #expect(settlement.errorMessage == nil)
        #expect(settlement.shouldRequireOutput == false)
    }

    @Test
    func acceptedGateIgnoresLaterCandidateUpdates() {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .agent)
        let acceptedRevision = interaction.outputCandidate.revision
        let acceptanceRecord = InteractiveOutputAcceptanceRecord(
            outputID: interaction.outputCandidate.outputID,
            acceptedRevision: acceptedRevision,
            contentHash: PlanningPlanArtifactPolicy.contentHash(validPlanMarkdown),
            acceptedAt: Date(timeIntervalSince1970: 0),
            idempotencyKey: "accept-once"
        )
        interaction.acceptPlanningDraftCandidate(acceptanceRecord)

        interaction.updatePlanningDraftCandidate(content: alternateValidPlanMarkdown, source: .user)

        #expect(interaction.draft == validPlanMarkdown)
        #expect(interaction.outputCandidate.revision == acceptedRevision)
        #expect(interaction.gateState == .accepted(acceptanceRecord))
    }

    @Test
    func userEditBeforeAcceptancePromotesEditedCandidate() {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .agent)
        let generatedRevision = interaction.outputCandidate.revision

        interaction.updatePlanningDraftCandidate(content: alternateValidPlanMarkdown, source: .user)

        #expect(interaction.outputCandidate.content == alternateValidPlanMarkdown)
        #expect(interaction.outputCandidate.source == .user)
        #expect(interaction.outputCandidate.revision == generatedRevision + 1)
        #expect(interaction.canSubmit)
    }

    @Test
    func staleDraftAcceptanceFailsWithoutWriting() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let sessionID = UUID().uuidString
        let candidate = InteractiveStepOutputCandidate(
            outputID: PlanningInteractionOutputContract.draftPlanOutputID,
            contentType: PlanningInteractionOutputContract.draftPlanContentType,
            content: validPlanMarkdown,
            source: .user,
            revision: 2
        )

        #expect(throws: PlanningPlanArtifactMaterializationError.self) {
            _ = try PlanningPlanArtifactStore().acceptDraftForReview(
                project: project,
                sessionID: sessionID,
                producerStepID: "interactive-planning",
                request: PlanningDraftAcceptanceRequest(
                    candidate: candidate,
                    expectedRevision: 1,
                    idempotencyKey: "stale"
                )
            )
        }
        let planURL = projectURL.appendingPathComponent(
            PlanningPlanArtifactPolicy.acceptedPlanPath(sessionID: sessionID)
        )
        #expect(!FileManager.default.fileExists(atPath: planURL.path))
    }

    @Test
    func idempotentDraftAcceptanceReturnsExistingRecordForSameContent() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let sessionID = UUID().uuidString
        let candidate = InteractiveStepOutputCandidate(
            outputID: PlanningInteractionOutputContract.draftPlanOutputID,
            contentType: PlanningInteractionOutputContract.draftPlanContentType,
            content: validPlanMarkdown,
            source: .user,
            revision: 1
        )
        let request = PlanningDraftAcceptanceRequest(
            candidate: candidate,
            expectedRevision: 1,
            idempotencyKey: "same-request"
        )
        let store = PlanningPlanArtifactStore()

        let first = try store.acceptDraftForReview(
            project: project,
            sessionID: sessionID,
            producerStepID: "interactive-planning",
            request: request
        )
        let second = try store.acceptDraftForReview(
            project: project,
            sessionID: sessionID,
            producerStepID: "interactive-planning",
            request: request
        )

        #expect(second.record == first.record)
        #expect(second.output.id == first.output.id)
        #expect(second.output.id == first.record.outputID)
        #expect(second.output.artifact.projectRelativePath == first.output.artifact.projectRelativePath)
    }

    @Test
    func repeatedAcceptanceWithDifferentKeyFailsAfterDraftAccepted() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let sessionID = UUID().uuidString
        let candidate = makeValidDraftCandidate()
        let store = PlanningPlanArtifactStore()
        let accepted = try store.acceptDraftForReview(
            project: project,
            sessionID: sessionID,
            producerStepID: "interactive-planning",
            request: PlanningDraftAcceptanceRequest(
                candidate: candidate,
                expectedRevision: candidate.revision,
                idempotencyKey: "first-key"
            )
        )

        expectAcceptanceFailure(.alreadyAccepted) {
            _ = try store.acceptDraftForReview(
                project: project,
                sessionID: sessionID,
                producerStepID: "interactive-planning",
                request: PlanningDraftAcceptanceRequest(
                    candidate: candidate,
                    expectedRevision: candidate.revision,
                    idempotencyKey: "second-key"
                )
            )
        }
        try expectAcceptedDraftPersistence(
            projectURL: projectURL,
            sessionID: sessionID,
            acceptance: accepted
        )
    }

    @Test
    func repeatedAcceptanceWithSameKeyAndDifferentContentFails() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let sessionID = UUID().uuidString
        let candidate = makeValidDraftCandidate()
        let store = PlanningPlanArtifactStore()
        let accepted = try store.acceptDraftForReview(
            project: project,
            sessionID: sessionID,
            producerStepID: "interactive-planning",
            request: PlanningDraftAcceptanceRequest(
                candidate: candidate,
                expectedRevision: candidate.revision,
                idempotencyKey: "same-key"
            )
        )

        expectAcceptanceFailure(.idempotencyKeyConflict) {
            _ = try store.acceptDraftForReview(
                project: project,
                sessionID: sessionID,
                producerStepID: "interactive-planning",
                request: PlanningDraftAcceptanceRequest(
                    candidate: makeValidDraftCandidate(content: alternateValidPlanMarkdown),
                    expectedRevision: candidate.revision,
                    idempotencyKey: "same-key"
                )
            )
        }
        try expectAcceptedDraftPersistence(
            projectURL: projectURL,
            sessionID: sessionID,
            acceptance: accepted
        )
    }

    private func makeValidDraftCandidate(
        content: String = validPlanMarkdown
    ) -> InteractiveStepOutputCandidate {
        InteractiveStepOutputCandidate(
            outputID: PlanningInteractionOutputContract.draftPlanOutputID,
            contentType: PlanningInteractionOutputContract.draftPlanContentType,
            content: content,
            source: .user,
            revision: 1
        )
    }

    private func expectAcceptanceFailure(
        _ expected: PlanningPlanArtifactMaterializationError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected acceptance failure \(expected).")
        } catch let error as PlanningPlanArtifactMaterializationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected acceptance failure \(expected), got \(error).")
        }
    }

    private func expectAcceptedDraftPersistence(
        projectURL: URL,
        sessionID: String,
        acceptance: PlanningDraftAcceptance
    ) throws {
        let acceptedPlanURL = projectURL.appendingPathComponent(
            PlanningPlanArtifactPolicy.acceptedPlanPath(sessionID: sessionID)
        )
        let canonicalPlanURL = projectURL.appendingPathComponent(
            PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID)
        )
        #expect(try String(contentsOf: acceptedPlanURL, encoding: .utf8) == acceptance.output.artifact.content)
        #expect(try String(contentsOf: canonicalPlanURL, encoding: .utf8) == acceptance.output.artifact.content)
        let record = try loadPersistedPlanningAcceptanceRecord(
            projectURL: projectURL,
            sessionID: sessionID,
            kind: .draft
        )
        #expect(record.kind == "draftAcceptedForReview")
        #expect(record.outputID == acceptance.record.outputID)
        #expect(record.acceptedRevision == acceptance.record.acceptedRevision)
        #expect(record.contentHash == acceptance.record.contentHash)
        #expect(record.idempotencyKey == acceptance.record.idempotencyKey)
        #expect(record.content == acceptance.output.artifact.content)
        #expect(record.contentType == acceptance.output.artifact.contentType)
        #expect(record.projectRelativePath == acceptance.output.artifact.projectRelativePath)
    }
}
