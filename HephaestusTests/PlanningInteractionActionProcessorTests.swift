import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningInteractionActionProcessorTests {
    @Test
    func copyArtifactPathUsesInjectedCopierAndUpdatesStatus() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        let copier = SpyPlanningReviewArtifactPathCopier()
        let processor = PlanningInteractionActionProcessor(
            model: model,
            artifactPathCopier: copier
        )
        let path = ".hephaestus/planning-review/session/cycles/2/plan.md"

        processor.handle(.tapCopyArtifactPath(path))

        #expect(copier.copiedPaths == [path])
        #expect(model.state.statusMessage == "Copied review artifact path: \(path)")
    }
}

private final class SpyPlanningReviewArtifactPathCopier: PlanningReviewArtifactPathCopying {
    var copiedPaths: [String] = []

    func copyArtifactPath(_ path: String) {
        copiedPaths.append(path)
    }
}
