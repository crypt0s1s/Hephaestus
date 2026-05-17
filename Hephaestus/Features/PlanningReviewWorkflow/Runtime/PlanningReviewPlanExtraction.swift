import Foundation

enum PlanningPlanExtractor {
    static func extractMarkdownPlan(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let candidate = extractFencedMarkdown(from: trimmed) ?? extractPlanDocument(from: trimmed)
        else { return nil }
        do {
            try PlanningPlanArtifactPolicy.validate(candidate)
            return candidate
        } catch {
            return nil
        }
    }

    private static func extractFencedMarkdown(from output: String) -> String? {
        let fencePrefixes = ["```markdown", "```md", "```"]
        for prefix in fencePrefixes {
            guard let start = output.range(of: prefix),
                let end = output[start.upperBound...].range(of: "```")
            else { continue }
            return String(output[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func extractPlanDocument(from output: String) -> String? {
        guard let start = output.range(of: "# Plan") else { return nil }
        return String(output[start.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
