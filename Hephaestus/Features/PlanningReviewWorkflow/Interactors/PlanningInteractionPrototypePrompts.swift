import Foundation

enum PlanningInteractionPrototypePrompts {
    static func plannerPrompt(for note: String) -> String {
        """
        You are the Codex planning partner inside Hephaestus.

        Discuss the user's planning note briefly, then return the current best draft plan as a
        complete markdown document. The Hephaestus app will validate and write the draft artifact.

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

    static func submittedPlanSummary(from plan: String) -> String {
        let firstLine =
            plan
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        return firstLine.map { "Submitted plan: \($0)" } ?? "Submitted plan artifact"
    }
}
