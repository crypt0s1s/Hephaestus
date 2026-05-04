import XCTest

final class HephaestusUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HEPHAESTUS_PROVIDER"] = "mock"
        app.launch()
        openWindowIfNeeded(in: app)

        XCTAssertTrue(app.staticTexts["Task Workspace"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openWindowIfNeeded(in app: XCUIApplication) {
        if app.staticTexts["Task Workspace"].waitForExistence(timeout: 2) {
            return
        }
        app.typeKey("n", modifierFlags: .command)
    }
}
