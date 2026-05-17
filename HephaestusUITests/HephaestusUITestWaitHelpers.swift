import Foundation
import XCTest

extension HephaestusUITests {
    func waitForElement(containing text: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if match.exists {
                return true
            }
            scrollWorkflowContent(in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return match.exists
    }

    func waitForTimelineRow(_ id: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let row = app.descendants(matching: .any)["workflow.timeline.row.\(id)"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if row.exists {
                return true
            }
            scrollWorkflowContent(in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return row.exists
    }

    func waitForFile(at url: URL, containing text: String, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latestOutput = ""
        while Date() < deadline {
            if let output = try? String(contentsOf: url, encoding: .utf8) {
                latestOutput = output
                if output.contains(text) {
                    return output
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return latestOutput.isEmpty ? try String(contentsOf: url, encoding: .utf8) : latestOutput
    }

    private func scrollWorkflowContent(in app: XCUIApplication) {
        let scroll = app.scrollViews["workflow.contentScroll"]
        if scroll.exists {
            scroll.swipeUp()
        } else if app.scrollViews.firstMatch.exists {
            app.scrollViews.firstMatch.swipeUp()
        }
    }
}
