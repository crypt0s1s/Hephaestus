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
        selectTasksMode(in: app)

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
        selectTasksMode(in: app)

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
        let externalWorkflowURL =
            repoURL
            .appendingPathComponent("ExampleWorkflows", isDirectory: true)
            .appendingPathComponent("ImplementationReviewExample", isDirectory: true)

        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launchEnvironment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"] = repoURL.path
        app.launchEnvironment["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT"] = externalWorkflowURL.path
        app.launch()
        selectWorkflowsMode(in: app)

        let workflowsTab = app.buttons["Workflows"]
        if workflowsTab.waitForExistence(timeout: 5) {
            workflowsTab.click()
        }

        let runButton = workflowRunButton(
            in: app,
            id: "external-implementation-review-example",
            title: "External Implementation Review Example"
        )
        XCTAssertTrue(runButton.waitForExistence(timeout: 90))
        XCTAssertTrue(waitForEnabled(runButton, timeout: 10))
        runButton.click()

        XCTAssertTrue(app.staticTexts["Implement plan"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Reviewer A"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Reviewer B"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Review gate"].waitForExistence(timeout: 30))
        XCTAssertTrue(
            app.staticTexts["External Implementation Review Example completed for Hephaestus."]
                .waitForExistence(timeout: 30))
    }

    @MainActor
    func testExternalSwiftWorkflowFailureShowsMalformedOutputAndExitCode() throws {
        let app = XCUIApplication()
        let repoURL = try repositoryRootURL()
        let externalWorkflowURL =
            repoURL
            .appendingPathComponent("ExampleWorkflows", isDirectory: true)
            .appendingPathComponent("ImplementationReviewExample", isDirectory: true)

        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launchEnvironment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"] = repoURL.path
        app.launchEnvironment["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT"] = externalWorkflowURL.path
        app.launch()
        selectWorkflowsMode(in: app)

        let workflowID = "external-implementation-review-example"
        let runButton = workflowRunButton(
            in: app,
            id: workflowID,
            title: "External Implementation Review Example"
        )
        XCTAssertTrue(runButton.waitForExistence(timeout: 90))

        let scenarioField = app.textFields["workflow.input.\(workflowID).scenario"]
        XCTAssertTrue(scenarioField.waitForExistence(timeout: 10))
        scenarioField.click()
        scenarioField.typeKey("a", modifierFlags: .command)
        scenarioField.typeText("malformed-failure")

        XCTAssertTrue(waitForEnabled(runButton, timeout: 10))
        runButton.click()

        XCTAssertTrue(
            app.staticTexts["External Implementation Review Example failed with exit code 42."]
                .waitForExistence(timeout: 120))
        XCTAssertTrue(waitForElement(containing: "Ignored malformed external workflow event", in: app, timeout: 30))
        XCTAssertTrue(
            waitForElement(
                containing: "plain external process output before failure",
                in: app,
                timeout: 10
            ))
    }

    @MainActor
    func testPlanningReviewWorkflowStartsInteractiveWaitingState() throws {
        let app = XCUIApplication()
        let projectURL = try temporaryWorkflowProjectURL(named: "planning-waiting-state")

        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launchEnvironment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"] = projectURL.path
        app.launch()
        selectWorkflowsMode(in: app)

        let workflowsTab = app.buttons["Workflows"]
        if workflowsTab.waitForExistence(timeout: 5) {
            workflowsTab.click()
        }

        XCTAssertTrue(app.staticTexts["Planning Review Workflow"].waitForExistence(timeout: 10))
        let runButton = workflowRunButton(
            in: app,
            id: "planning-review",
            title: "Planning Review Workflow"
        )
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForEnabled(runButton, timeout: 10))
        clickWorkflowRunButton(runButton)

        XCTAssertTrue(app.staticTexts["Interactive planning"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["workflow.timeline.row.planning-review-interactive-planning"]
                .waitForExistence(timeout: 10))
        scrollToPlanningInteraction(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["planning.interaction"].waitForExistence(timeout: 10))
        XCTAssertTrue(planningMessageInput(in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["planning.draftPlan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planning.submitPlan"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPlanningReviewWorkflowSubmitsInteractivePlan() throws {
        let app = XCUIApplication()
        let projectURL = try temporaryWorkflowProjectURL(named: "planning-submit")

        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launchEnvironment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"] = projectURL.path
        app.launch()
        selectWorkflowsMode(in: app)

        let runButton = workflowRunButton(
            in: app,
            id: "planning-review",
            title: "Planning Review Workflow"
        )
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForEnabled(runButton, timeout: 10))
        clickWorkflowRunButton(runButton)

        XCTAssertTrue(app.staticTexts["Interactive planning"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["workflow.timeline.row.planning-review-interactive-planning"]
                .waitForExistence(timeout: 10))
        scrollToPlanningInteraction(in: app)
        let messageInput = planningMessageInput(in: app)
        XCTAssertTrue(messageInput.waitForExistence(timeout: 10))
        messageInput.click()
        messageInput.typeText("Build the interactive planning phase")
        app.buttons["planning.sendButton"].click()

        reviewGeneratedDraft(in: app)

        let submitButton = app.buttons["planning.submitPlan"]
        XCTAssertTrue(waitForEnabled(submitButton, timeout: 20))
        submitButton.click()

        XCTAssertTrue(app.buttons["planning.acceptPlan"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["planning.anotherCycle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planning.continuePlanning"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["workflow.timeline.row.planning-review-interactive-user-review"]
                .waitForExistence(timeout: 10))
        assertPlanningReviewHandoffSummary(in: app)
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

    private func planningMessageInput(in app: XCUIApplication) -> XCUIElement {
        let textField = app.textFields["planning.messageInput"]
        if textField.exists {
            return textField
        }
        let anyElement = app.descendants(matching: .any)["planning.messageInput"]
        if anyElement.exists {
            return anyElement
        }
        return app.textViews["planning.messageInput"]
    }

    private func planningDraftPlan(in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews["planning.draftPlan"]
        if textView.exists {
            return textView
        }
        return app.descendants(matching: .any)["planning.draftPlan"]
    }

    private func reviewGeneratedDraft(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["planning.awaitingUserReview"].waitForExistence(timeout: 30))
        let draftPlan = planningDraftPlan(in: app)
        XCTAssertTrue(draftPlan.waitForExistence(timeout: 10))
    }

    private func assertPlanningReviewHandoffSummary(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["planning.reviewSummary"]
                .waitForExistence(timeout: 10)
        )
    }

    private func scrollToPlanningInteraction(in app: XCUIApplication) {
        let interaction = app.descendants(matching: .any)["planning.interaction"]
        let workflowScroll = app.scrollViews["workflow.contentScroll"]
        for _ in 0..<5 where !interaction.exists {
            if workflowScroll.exists {
                workflowScroll.swipeUp()
            } else {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
    }

    private func selectTasksMode(in app: XCUIApplication) {
        let tasksButton = app.buttons["Tasks"]
        if tasksButton.waitForExistence(timeout: 5) {
            tasksButton.click()
            return
        }
        XCTAssertTrue(app.staticTexts["Task Workspace"].waitForExistence(timeout: 5))
    }

    private func selectWorkflowsMode(in app: XCUIApplication) {
        let workflowsButton = app.buttons["Workflows"]
        if workflowsButton.waitForExistence(timeout: 5) {
            workflowsButton.click()
            return
        }
        XCTAssertTrue(app.staticTexts["Workflows"].waitForExistence(timeout: 5))
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForElement(containing text: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if match.exists {
                return true
            }
            let scroll = app.scrollViews["workflow.contentScroll"]
            if scroll.exists {
                scroll.swipeUp()
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return match.exists
    }

    private func workflowRunButton(in app: XCUIApplication, id: String, title: String) -> XCUIElement {
        let identifierButton = app.buttons["workflow.run.\(id)"]
        if identifierButton.waitForExistence(timeout: 2) {
            return identifierButton
        }
        let identifierElement = app.descendants(matching: .any)["workflow.run.\(id)"]
        if identifierElement.waitForExistence(timeout: 2) {
            return identifierElement
        }
        return app.buttons["Run \(title)"]
    }

    private func clickWorkflowRunButton(_ button: XCUIElement) {
        button.click()
    }

    private func repositoryRootURL() throws -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryURL =
            testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryURL.appendingPathComponent("Hephaestus.xcodeproj").path))
        return repositoryURL
    }

    private func temporaryWorkflowProjectURL(named name: String) throws -> URL {
        let url =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("h-ui", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
