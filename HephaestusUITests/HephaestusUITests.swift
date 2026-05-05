import XCTest

final class HephaestusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTaskWorkspaceAffordances() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launch()
        openWindowIfNeeded(in: app)

        XCTAssertTrue(app.staticTexts["Task Workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["conversation.transcript"].exists)
        XCTAssertTrue(messageInput(in: app).exists)
        XCTAssertTrue(app.buttons["conversation.sendButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["task.emptyState"].exists)
    }

    @MainActor
    func testInspectorDismissesWhenClickingOutside() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launch()
        openWindowIfNeeded(in: app)

        let input = messageInput(in: app)
        XCTAssertTrue(app.staticTexts["Task Workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("manual qa dismissal check")
        app.buttons["conversation.sendButton"].click()

        let inspectorButton = app.buttons["task.inspector.open"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForEnabled(inspectorButton, timeout: 5))
        inspectorButton.click()

        let inspector = app.descendants(matching: .any)["inspector.panel"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).click()

        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: inspector)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testExternalSwiftWorkflowRunsFromWorkflowScreen() throws {
        let app = XCUIApplication()
        let repoURL = try repositoryRootURL()
        let externalWorkflowURL = repoURL
            .appendingPathComponent("ExampleWorkflows", isDirectory: true)
            .appendingPathComponent("ImplementationReviewExample", isDirectory: true)

        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launchEnvironment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"] = repoURL.path
        app.launchEnvironment["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT"] = externalWorkflowURL.path
        app.launch()
        openWorkflowWindowIfNeeded(in: app)

        let workflowsTab = app.buttons["Workflows"]
        if workflowsTab.waitForExistence(timeout: 5) {
            workflowsTab.click()
        }

        let runButton = app.buttons["workflow.run.external-implementation-review-example"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 90))
        XCTAssertTrue(waitForEnabled(runButton, timeout: 10))
        runButton.click()

        XCTAssertTrue(app.staticTexts["Implement plan"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Reviewer A"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Reviewer B"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Review gate"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["External Implementation Review Example completed for Hephaestus."].waitForExistence(timeout: 30))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func messageInput(in app: XCUIApplication) -> XCUIElement {
        let textField = app.textFields["conversation.messageInput"]
        if textField.exists {
            return textField
        }
        let anyElement = app.descendants(matching: .any)["conversation.messageInput"]
        if anyElement.exists {
            return anyElement
        }
        return app.textViews["conversation.messageInput"]
    }

    private func openWindowIfNeeded(in app: XCUIApplication) {
        if app.staticTexts["Task Workspace"].waitForExistence(timeout: 2) {
            return
        }
        app.typeKey("n", modifierFlags: .command)
    }

    private func openWorkflowWindowIfNeeded(in app: XCUIApplication) {
        if app.staticTexts["Workflows"].waitForExistence(timeout: 2) {
            return
        }
        app.typeKey("n", modifierFlags: .command)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func repositoryRootURL() throws -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent("Hephaestus.xcodeproj").path))
        return repositoryURL
    }
}
