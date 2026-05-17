import AppKit
import Foundation

protocol PlanningReviewArtifactPathCopying {
    func copyArtifactPath(_ path: String)
}

struct PasteboardPlanningReviewArtifactPathCopier: PlanningReviewArtifactPathCopying {
    func copyArtifactPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}
