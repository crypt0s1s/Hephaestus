import XCTest

final class HephaestusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsChatAffordances() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launch()
        openWindowIfNeeded(in: app)

        XCTAssertTrue(app.staticTexts["Hephaestus Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["chat.transcript"].exists)
        XCTAssertTrue(messageInput(in: app).exists)
        XCTAssertTrue(app.buttons["chat.sendButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chat.emptyState"].exists)
    }

    @MainActor
    func testInspectorDismissesWhenClickingOutside() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launch()
        openWindowIfNeeded(in: app)

        let input = messageInput(in: app)
        XCTAssertTrue(app.staticTexts["Hephaestus Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("manual qa dismissal check")
        app.buttons["chat.sendButton"].click()

        let inspectorButton = app.buttons["chat.inspector.open"]
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
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func messageInput(in app: XCUIApplication) -> XCUIElement {
        let textField = app.textFields["chat.messageInput"]
        if textField.exists {
            return textField
        }
        let anyElement = app.descendants(matching: .any)["chat.messageInput"]
        if anyElement.exists {
            return anyElement
        }
        return app.textViews["chat.messageInput"]
    }

    private func openWindowIfNeeded(in app: XCUIApplication) {
        if app.staticTexts["Hephaestus Chat"].waitForExistence(timeout: 2) {
            return
        }
        app.typeKey("n", modifierFlags: .command)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
