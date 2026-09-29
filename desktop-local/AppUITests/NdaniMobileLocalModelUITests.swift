import XCTest

final class NdaniMobileLocalModelUITests: XCTestCase {
    @MainActor
    func testDownloadedLocalModelRespondsInChat() throws {
        guard ProcessInfo.processInfo.environment["NDANI_RUN_LOCAL_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set NDANI_RUN_LOCAL_MODEL_TESTS=1 after seeding a local model in the simulator app container.")
        }

        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Chat"].tap()

        let newConversation = app.buttons.matching(identifier: "mobileChatEmpty")
            .matching(NSPredicate(format: "label == %@", "New conversation"))
            .firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 5))
        newConversation.tap()

        let input = app.textFields["Message"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Reply with exactly OK.")

        app.buttons["Send message"].tap()

        let timeout = Date().addingTimeInterval(420)
        var sawAssistantResponse = false
        var sawNoModelMessage = false

        while Date() < timeout {
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
            sawAssistantResponse = labels.contains { label in
                label.localizedCaseInsensitiveContains("OK") &&
                    !label.localizedCaseInsensitiveContains("Reply with exactly")
            }
            sawNoModelMessage = labels.contains {
                $0.localizedCaseInsensitiveContains("No model loaded")
            }

            if sawAssistantResponse || sawNoModelMessage {
                break
            }

            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }

        XCTAssertFalse(sawNoModelMessage)
        XCTAssertTrue(sawAssistantResponse)
    }
}
