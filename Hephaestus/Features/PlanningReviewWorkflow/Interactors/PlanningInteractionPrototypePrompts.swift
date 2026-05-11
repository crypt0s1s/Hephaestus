import Foundation

enum PlanningInteractionPrototypePrompts {
  static func plannerPrompt(for note: String) -> String {
    """
    You are the Codex planning partner inside Hephaestus.

    Discuss the user's planning note briefly, then include the current best draft plan inside a
    fenced markdown block. The app will only copy the fenced plan into the draft editor.

    Required sections:
    ## Summary
    ## Scope
    ## Non-Goals
    ## Implementation Approach
    ## Validation
    ## Open Questions

    User note:
    \(note)
    """
  }

  static func extractDraftPlan(from response: String) -> String? {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let fenceStart = trimmed.range(of: "```markdown") ?? trimmed.range(of: "```md"),
       let fenceEnd = trimmed[fenceStart.upperBound...].range(of: "```") {
      return String(trimmed[fenceStart.upperBound..<fenceEnd.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard trimmed.hasPrefix("# Plan") || trimmed.hasPrefix("## Summary") else { return nil }
    return hasRequiredPlanSections(trimmed) ? trimmed : nil
  }

  private static func hasRequiredPlanSections(_ plan: String) -> Bool {
    ["## Summary", "## Scope", "## Validation"].allSatisfy {
      plan.localizedCaseInsensitiveContains($0)
    }
  }

  static func submittedPlanSummary(from plan: String) -> String {
    let firstLine = plan
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty && !$0.hasPrefix("#") }
    return firstLine.map { "Submitted plan: \($0)" } ?? "Submitted plan artifact"
  }
}
