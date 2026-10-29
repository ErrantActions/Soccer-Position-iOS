import UIKit
import XCTest

final class ToolbarSmokeTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Duo toolbar final state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testNativeToolbarIsPopulatedAndDrawingActionWorks() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for name in ["position", "draw", "analyze", "more"] {
                let button = app.buttons["coach.toolbar.\(name)"]
                XCTAssertTrue(button.waitForExistence(timeout: 15), "Missing native toolbar action: \(name)")
                let visible = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: button)
                wait(for: [visible], timeout: 15)
            }
            let draw = app.buttons["coach.toolbar.draw"]
            draw.tap()
            let drawing = expectation(for: NSPredicate(format: "value == %@", "Drawing routes"), evaluatedWith: draw)
            wait(for: [drawing], timeout: 5)
            draw.tap()
            let moving = expectation(for: NSPredicate(format: "value == %@", "Moving players"), evaluatedWith: draw)
            wait(for: [moving], timeout: 5)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = orientation == .portrait ? "Duo toolbar portrait" : "Duo toolbar landscape"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
