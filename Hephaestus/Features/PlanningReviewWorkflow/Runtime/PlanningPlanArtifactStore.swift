import Foundation

struct PlanningPlanArtifactStore: PlanningPlanArtifactMaterializing {
    private let fileManager: FileManager
    private let planValidator: PlanFileValidator

    init(
        fileManager: FileManager = .default,
        planValidator: PlanFileValidator = PlanFileValidator()
    ) {
        self.fileManager = fileManager
        self.planValidator = planValidator
    }

    func prepareDraftArtifact(project: WorkflowProject, sessionID: String) throws -> PlanningDraftArtifact {
        let relativePath = PlanningPlanArtifactPolicy.draftPlanPath(sessionID: sessionID)
        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
        let fileURL = projectURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        return PlanningDraftArtifact(project: project, relativePath: relativePath, fileURL: fileURL)
    }

    func loadDraftArtifact(_ artifact: PlanningDraftArtifact) throws -> PlanningLoadedDraftArtifact {
        guard fileManager.fileExists(atPath: artifact.fileURL.path) else {
            throw PlanningPlanArtifactMaterializationError.missingDraftArtifact(artifact.relativePath)
        }
        let content = try String(contentsOf: artifact.fileURL, encoding: .utf8)
        try PlanningPlanArtifactPolicy.validate(content)
        _ = try planValidator.loadPlan(project: artifact.project, relativePath: artifact.relativePath)
        return PlanningLoadedDraftArtifact(artifact: artifact, content: content)
    }

    func materializeDraftArtifact(
        project: WorkflowProject,
        sessionID: String,
        content: String
    ) throws -> PlanningLoadedDraftArtifact {
        try PlanningPlanArtifactPolicy.validate(content)
        let artifact = try prepareDraftArtifact(project: project, sessionID: sessionID)
        try content.write(to: artifact.fileURL, atomically: true, encoding: .utf8)
        return try loadDraftArtifact(artifact)
    }

    func acceptDraftForReview(
        project: WorkflowProject,
        sessionID: String,
        producerStepID: String,
        request: PlanningDraftAcceptanceRequest
    ) throws -> PlanningDraftAcceptance {
        try PlanningPlanArtifactPolicy.validate(request.candidate.content)
        try validateExpectedRevision(request)
        let paths = PlanningDraftAcceptancePaths(project: project, sessionID: sessionID)
        let contentHash = PlanningPlanArtifactPolicy.contentHash(request.candidate.content)
        if let existing = try loadExistingAcceptance(
            paths: paths,
            request: request,
            contentHash: contentHash
        ) {
            return existing.acceptance(
                projectRelativePath: paths.planPath,
                producerStepID: producerStepID,
                isNewAcceptance: false
            )
        }
        try writeAcceptedPlan(request.candidate.content, paths: paths)
        _ = try planValidator.loadPlan(project: project, relativePath: paths.planPath)
        let persistedRecord = makePersistedRecord(
            request: request,
            contentHash: contentHash,
            planPath: paths.planPath
        )
        try writeAcceptanceRecord(persistedRecord, url: paths.draftAcceptanceURL)
        return persistedRecord.acceptance(
            projectRelativePath: paths.planPath,
            producerStepID: producerStepID,
            isNewAcceptance: true
        )
    }

    func materializeConsolidatedFeedback(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput {
        try writeOutputArtifact(
            project: project,
            relativePath: PlanningPlanArtifactPolicy.consolidatedFeedbackPath(
                sessionID: sessionID,
                cycle: cycle
            ),
            title: "Consolidated Review Feedback Cycle \(cycle)",
            contentType: "text/markdown; artifact=consolidated-review",
            producerStepID: "automated-review-cycle-\(cycle)",
            content: content,
            summary: "Consolidated review feedback cycle \(cycle)"
        )
    }

    func materializePlannerResponsePlan(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput {
        try PlanningPlanArtifactPolicy.validate(content)
        return try writeOutputArtifact(
            project: project,
            relativePath: PlanningPlanArtifactPolicy.plannerResponsePlanPath(
                sessionID: sessionID,
                cycle: cycle
            ),
            title: "Planner Response Plan Cycle \(cycle)",
            contentType: PlanningPlanArtifactPolicy.contentType,
            producerStepID: "planner-response-cycle-\(cycle)",
            content: content,
            summary: Self.planSummary(from: content)
        )
    }

    func finalizeReviewedPlan(
        project: WorkflowProject,
        sessionID: String,
        output: InteractiveStepOutput
    ) throws -> InteractiveStepOutput {
        try PlanningPlanArtifactPolicy.validate(output.artifact.content)
        let paths = PlanningDraftAcceptancePaths(project: project, sessionID: sessionID)
        try writeAcceptedPlan(output.artifact.content, paths: paths)
        let contentHash = PlanningPlanArtifactPolicy.contentHash(output.artifact.content)
        let persistedRecord = makeFinalPersistedRecord(
            output: output,
            contentHash: contentHash,
            planPath: paths.planPath
        )
        try writeAcceptanceRecord(persistedRecord, url: paths.finalAcceptanceURL)
        return InteractiveStepOutput(
            id: output.id,
            producerStepID: output.producerStepID,
            createdAt: output.createdAt,
            artifact: InteractiveStepArtifact(
                title: output.artifact.title,
                contentType: output.artifact.contentType,
                content: output.artifact.content,
                projectRelativePath: paths.planPath
            ),
            summary: output.summary
        )
    }

    private func validateExpectedRevision(_ request: PlanningDraftAcceptanceRequest) throws {
        guard request.candidate.revision == request.expectedRevision else {
            throw PlanningPlanArtifactMaterializationError.staleRevision(
                expected: request.expectedRevision,
                actual: request.candidate.revision
            )
        }
    }

    private func writeAcceptedPlan(_ content: String, paths: PlanningDraftAcceptancePaths) throws {
        try fileManager.createDirectory(
            at: paths.planURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.acceptedPlanURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: paths.acceptedPlanURL, atomically: true, encoding: .utf8)
        try content.write(to: paths.planURL, atomically: true, encoding: .utf8)
    }

    private func makePersistedRecord(
        request: PlanningDraftAcceptanceRequest,
        contentHash: String,
        planPath: String
    ) -> PersistedPlanningDraftAcceptanceRecord {
        PersistedPlanningDraftAcceptanceRecord(
            kind: .draftAcceptedForReview,
            outputID: request.candidate.outputID,
            acceptedRevision: request.candidate.revision,
            contentHash: contentHash,
            acceptedAt: Date.persistenceTimestampNow(),
            idempotencyKey: request.idempotencyKey,
            contentType: request.candidate.contentType,
            content: request.candidate.content,
            projectRelativePath: planPath
        )
    }

    private func writeAcceptanceRecord(
        _ persistedRecord: PersistedPlanningDraftAcceptanceRecord,
        url: URL
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.planningAcceptance.encode(persistedRecord).write(to: url, options: .atomic)
    }

    private func writeOutputArtifact(
        project: WorkflowProject,
        relativePath: String,
        title: String,
        contentType: String,
        producerStepID: String,
        content: String,
        summary: String
    ) throws -> InteractiveStepOutput {
        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
        let outputURL = projectURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        return InteractiveStepOutput(
            producerStepID: producerStepID,
            artifact: InteractiveStepArtifact(
                title: title,
                contentType: contentType,
                content: content,
                projectRelativePath: relativePath
            ),
            summary: summary
        )
    }

    private func loadExistingAcceptance(
        paths: PlanningDraftAcceptancePaths,
        request: PlanningDraftAcceptanceRequest,
        contentHash: String
    ) throws -> PersistedPlanningDraftAcceptanceRecord? {
        let url = paths.draftAcceptanceURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let existing = try JSONDecoder.planningAcceptance.decode(
            PersistedPlanningDraftAcceptanceRecord.self,
            from: data
        )
        guard existing.idempotencyKey == request.idempotencyKey else {
            throw PlanningPlanArtifactMaterializationError.alreadyAccepted
        }
        guard existing.contentHash == contentHash else {
            throw PlanningPlanArtifactMaterializationError.idempotencyKeyConflict
        }
        try writeAcceptedPlan(existing.content, paths: paths)
        return existing
    }

    private func makeFinalPersistedRecord(
        output: InteractiveStepOutput,
        contentHash: String,
        planPath: String
    ) -> PersistedPlanningDraftAcceptanceRecord {
        PersistedPlanningDraftAcceptanceRecord(
            kind: .finalReviewedPlanAccepted,
            outputID: output.id,
            acceptedRevision: 0,
            contentHash: contentHash,
            acceptedAt: Date.persistenceTimestampNow(),
            idempotencyKey: "final-review-\(output.id)",
            contentType: output.artifact.contentType,
            content: output.artifact.content,
            projectRelativePath: planPath
        )
    }

    private static func planSummary(from plan: String) -> String {
        let firstLine = plan
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        return firstLine.map { "Submitted plan: \($0)" } ?? "Submitted plan"
    }
}

private struct PlanningDraftAcceptancePaths {
    let planPath: String
    let acceptedPlanPath: String
    let draftAcceptanceRecordPath: String
    let finalAcceptanceRecordPath: String
    let projectURL: URL

    init(project: WorkflowProject, sessionID: String) {
        planPath = PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID)
        acceptedPlanPath = PlanningPlanArtifactPolicy.acceptedPlanPath(sessionID: sessionID)
        draftAcceptanceRecordPath = PlanningPlanArtifactPolicy.draftAcceptanceRecordPath(sessionID: sessionID)
        finalAcceptanceRecordPath = PlanningPlanArtifactPolicy.finalAcceptanceRecordPath(sessionID: sessionID)
        projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
    }

    var planURL: URL {
        projectURL.appendingPathComponent(planPath)
    }

    var acceptedPlanURL: URL {
        projectURL.appendingPathComponent(acceptedPlanPath)
    }

    var draftAcceptanceURL: URL {
        projectURL.appendingPathComponent(draftAcceptanceRecordPath)
    }

    var finalAcceptanceURL: URL {
        projectURL.appendingPathComponent(finalAcceptanceRecordPath)
    }
}

private struct PersistedPlanningDraftAcceptanceRecord: Codable, Equatable {
    let kind: Kind
    let outputID: String
    let acceptedRevision: Int
    let contentHash: String
    let acceptedAt: Date
    let idempotencyKey: String
    let contentType: String
    let content: String
    let projectRelativePath: String

    enum Kind: String, Codable, Equatable {
        case draftAcceptedForReview
        case finalReviewedPlanAccepted
    }

    func acceptance(
        projectRelativePath: String,
        producerStepID: String,
        isNewAcceptance: Bool
    ) -> PlanningDraftAcceptance {
        let artifact = InteractiveStepArtifact(
            title: PlanningPlanArtifactPolicy.artifactTitle,
            contentType: contentType,
            content: content,
            projectRelativePath: projectRelativePath
        )
        let output = InteractiveStepOutput(
            id: outputID,
            producerStepID: producerStepID,
            createdAt: acceptedAt,
            artifact: artifact,
            summary: Self.planSummary(from: content)
        )
        let record = InteractiveOutputAcceptanceRecord(
            outputID: outputID,
            acceptedRevision: acceptedRevision,
            contentHash: contentHash,
            acceptedAt: acceptedAt,
            idempotencyKey: idempotencyKey
        )
        return PlanningDraftAcceptance(
            record: record,
            output: output,
            isNewAcceptance: isNewAcceptance
        )
    }

    private static func planSummary(from plan: String) -> String {
        let firstLine = plan
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        return firstLine.map { "Submitted plan: \($0)" } ?? "Submitted plan"
    }
}

private extension JSONEncoder {
    static var planningAcceptance: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var planningAcceptance: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
