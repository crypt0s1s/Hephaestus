import Foundation

public protocol LoadRunInspectionUseCase: Sendable {
    func loadRunInspection(runID: UUID) async throws -> RunInspectionSnapshot
}
