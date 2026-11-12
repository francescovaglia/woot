import XCTest

/// Signs in to a real Chatwoot with `WOOT_LIVE_SERVER` and `WOOT_LIVE_TOKEN`
/// (pass them to `xcodebuild test` with the `TEST_RUNNER_` prefix) and checks that
/// navigating away and back keeps what the agent was doing.
/// Only reads and opens conversations, and types in note mode so no typing indicator is sent.
@MainActor
final class NavigationStateTests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    override func setUp() async throws {
        try XCTSkipIf(environment["WOOT_LIVE_TOKEN"] == nil, "Needs WOOT_LIVE_SERVER and WOOT_LIVE_TOKEN")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        signInIfNeeded()
    }

    func testSearchSurvivesOpeningAResult() throws {
        let query = environment["WOOT_UI_QUERY"] ?? "export"
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        dismissSavePasswordPrompt()
        snapshot("Inbox")

        search.tap()
        search.typeText(query)
        let result = app.buttons.matching(identifier: "searchResult").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "no results for \(query)")
        let resultLabel = result.label
        snapshot("Search")

        result.tap()
        let composer = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        switchToNote()
        composer.tap()
        composer.typeText("Draft kept")
        snapshot("Conversation")

        goBack()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, query, "the query was cleared")
        XCTAssertTrue(result.waitForExistence(timeout: 2))
        XCTAssertEqual(result.label, resultLabel, "the results changed")
        snapshot("Back to search")

        result.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Draft kept", "the draft was lost")
    }

    private func signInIfNeeded() {
        let server = app.textFields["server"]
        guard server.waitForExistence(timeout: 3) else { return }
        server.tap()
        // The field remembers the last server, so clear it first.
        let previous = (server.value as? String) ?? ""
        server.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        server.typeText(environment["WOOT_LIVE_SERVER"] ?? "")
        app.buttons["useToken"].tap()
        let token = app.secureTextFields["token"]
        token.tap()
        token.typeText(environment["WOOT_LIVE_TOKEN"] ?? "")
        app.buttons["signIn"].tap()
        dismissSavePasswordPrompt()
    }

    /// iOS may offer to save the credential in Passwords; it runs in another process.
    private func dismissSavePasswordPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Non ora"] where springboard.buttons[label].waitForExistence(timeout: 2) {
            springboard.buttons[label].tap()
        }
    }

    private func switchToNote() {
        app.descendants(matching: .any)["composerMenu"].tap()
        app.buttons["Private Note"].tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        // Real inbox data: kept only to debug a failure, deleted when the test passes.
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }
}
