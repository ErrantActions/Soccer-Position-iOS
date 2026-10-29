import UIKit
import XCTest

final class ToolbarSmokeTests: XCTestCase {
    @MainActor func testNativeToolbarIsPopulatedAndDrawingActionWorks() {
        continueAfterFailure = true
        let app = XCUIApplication()
        defer {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Duo toolbar final state"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for name in ["position", "draw", "analyze", "more"] {
                let button = app.buttons["coach.toolbar.\(name)"]
                guard button.waitForExistence(timeout: 15) else {
                    XCTFail("Missing native toolbar action: \(name)")
                    return
                }
                let visible = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: button)
                guard XCTWaiter.wait(for: [visible], timeout: 15) == .completed else {
                    XCTFail("Native toolbar action is not tappable: \(name)")
                    return
                }
            }
            let draw = app.buttons["coach.toolbar.draw"]
            draw.tap()
            let drawing = expectation(for: NSPredicate(format: "value == %@", "Drawing routes"), evaluatedWith: draw)
            guard XCTWaiter.wait(for: [drawing], timeout: 5) == .completed else {
                XCTFail("The native Draw action did not enable route drawing.")
                return
            }
            draw.tap()
            let moving = expectation(for: NSPredicate(format: "value == %@", "Moving players"), evaluatedWith: draw)
            guard XCTWaiter.wait(for: [moving], timeout: 5) == .completed else {
                XCTFail("The native Draw action did not restore player movement.")
                return
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = orientation == .portrait ? "Duo toolbar portrait" : "Duo toolbar landscape"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
