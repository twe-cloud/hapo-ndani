import XCTest

final class NdaniMobileLayoutUITests: XCTestCase {
    @MainActor
    func testHomeFirstScreenFitsPhoneBounds() {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["Hapo Ndani"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        assertElementFitsVisibleWindow(title, in: app)
        assertElementFitsVisibleWindow(
            firstExistingButton(in: app, labels: ["Set up recommended AI", "Recommended AI downloaded"]),
            in: app
        )
    }

    @MainActor
    func testTabOrderIsHomeChatJournal() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let buttons = tabBar.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Array(buttons.prefix(3)), ["Home", "Chat", "Journal"])
    }

    @MainActor
    func testChatFirstScreenUsesMobileLayout() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Chat"].tap()

        let emptyState = app.staticTexts["Start a private chat"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 3))
        assertElementFitsVisibleWindow(emptyState, in: app)
        assertElementFitsVisibleWindow(
            firstExistingButton(in: app, labels: ["Set up recommended AI", "Recommended AI downloaded"]),
            in: app
        )
        assertElementFitsVisibleWindow(app.textFields["Message"], in: app)
    }

    @MainActor
    private func assertElementFitsVisibleWindow(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)

        let windowFrame = app.windows.element(boundBy: 0).frame
        let elementFrame = element.frame

        XCTAssertGreaterThanOrEqual(elementFrame.minX, windowFrame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(elementFrame.minY, windowFrame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(elementFrame.maxX, windowFrame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(elementFrame.maxY, windowFrame.maxY, file: file, line: line)
    }

    @MainActor
    private func firstExistingButton(in app: XCUIApplication, labels: [String]) -> XCUIElement {
        let predicate = NSPredicate(format: "label IN %@", labels)
        return app.buttons.matching(predicate).firstMatch
    }
}
