import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningReviewWorkflowTests {
  @Test
  func planningReviewWorkflowStartsInInteractiveWaitingState() throws {
    let catalog = BuiltInWorkflowCatalog.production()
    let planningDefinition = try #require(catalog.workflow(id: PlanningReviewWorkflowRunner.id)?.definition)
    #expect(catalog.definitions.map(\.id).contains(PlanningReviewWorkflowRunner.id))
    #expect(planningDefinition.steps.first?.id == "interactive-planning")

    let projectURL = try makeTemporaryPlanningProject()
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    let progress = PlanningReviewWorkflowRunner().startInteractivePlanning(project: project)

    #expect(progress.timeline.contains("Interactive planning phase is waiting for user input."))
    #expect(progress.timeline.contains("Automated reviewer cycles have not started."))
    #expect(progress.stepRecords.first?.id == "planning-review-interactive-planning")
    #expect(progress.stepRecords.first?.status == .inProgress)
    #expect(progress.stepRecords.dropFirst().allSatisfy { $0.status == .pending })
  }

  @Test
  func submittingPlanAdvancesToReviewReadyState() throws {
    let projectURL = try makeTemporaryPlanningProject()
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    let message = InteractiveStepMessage(
      kind: .submittedArtifact,
      producerStepID: "interactive-planning",
      payload: .artifact(
        InteractiveStepArtifact(
          contentType: "text/markdown; artifact=plan",
          content: "# Plan\n\nBuild the interactive phase."
        )
      ),
      summary: "Submitted plan for review"
    )

    let progress = PlanningReviewWorkflowRunner().submitPlan(project: project, message: message)

    #expect(progress.timeline.contains("Interactive planning phase submitted a plan message."))
    #expect(progress.timeline.contains("Automated reviewer cycles are ready to start."))
    #expect(progress.stepRecords.count == 4)
    #expect(progress.stepRecords[0].status == .succeeded)
    #expect(progress.stepRecords[1].status == .succeeded)
    #expect(progress.stepRecords[1].outputPreview?.contains("Build the interactive phase.") == true)
    #expect(progress.stepRecords[2].status == .pending)
    #expect(
      progress.stepRecords[2].summary
        == "Automated reviewer cycles are ready to consume the submitted plan.")
  }
}

private func makeTemporaryPlanningProject() throws -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("hephaestus-planning-review-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
