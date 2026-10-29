import CoreGraphics
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class DeviceLayoutTests: XCTestCase {
    private var windows: [CGSize] {
        [
            CGSize(width: 320, height: 480), CGSize(width: 375, height: 603),
            CGSize(width: 390, height: 760), CGSize(width: 430, height: 850),
            CGSize(width: 560, height: 300), CGSize(width: 667, height: 320),
            CGSize(width: 756, height: 313), CGSize(width: 375, height: 1000),
            CGSize(width: 600, height: 1000), CGSize(width: 744, height: 1000),
            CGSize(width: 768, height: 1000), CGSize(width: 1194, height: 760),
            CGSize(width: 1366, height: 980),
        ]
    }

    func testRegularPhoneLandscapeGetsAFixedPitchAndRightSettings() throws {
        for size in windows where size.width >= 560 && size.width > size.height {
            let layout = CoachingLayout.resolve(size: size, division: nil)
            XCTAssertEqual(layout.mode, .desk)
            let settings = try XCTUnwrap(layout.coachPane)
            XCTAssertEqual(layout.pitchPane.minX, 0)
            XCTAssertEqual(layout.pitchPane.maxX, settings.minX)
            XCTAssertEqual(layout.pitchPane.height, size.height)
            XCTAssertEqual(settings.maxX, size.width)
            XCTAssertGreaterThanOrEqual(settings.width, 260)
        }
    }

    func testMediumIPadWindowDoesNotNeedFullTabletWidth() throws {
        let layout = CoachingLayout.resolve(size: CGSize(width: 744, height: 1000), division: nil)
        XCTAssertEqual(layout.mode, .desk)
        XCTAssertNotNil(layout.coachPane)
        XCTAssertEqual(try XCTUnwrap(layout.coachPane).height, 1000)
    }

    func testNarrowPortraitWindowsUseOneColumn() {
        for size in windows where size.width < 680 && size.width < size.height {
            let layout = CoachingLayout.resolve(size: size, division: nil)
            XCTAssertEqual(layout.mode, .compact)
            XCTAssertNil(layout.coachPane)
        }
    }

    func testAccessibilityTextRetainsSingleColumnOnOrdinaryDevices() {
        for size in windows {
            let layout = CoachingLayout.resolve(size: size, division: nil, largeText: true)
            XCTAssertEqual(layout.mode, .compact)
            XCTAssertNil(layout.coachPane)
        }
    }

    func testDuoKeepsItsExistingSidebarAllocationAndFoldPriority() throws {
        let size = CGSize(width: 650, height: 500)
        let flat = CoachingLayout.resolve(size: size, division: nil, largeText: true, duoDisplay: true)
        XCTAssertEqual(flat.mode, .desk)
        XCTAssertEqual(try XCTUnwrap(flat.coachPane).width, 247, accuracy: 0.000001)
        let fold = CGRect(x: 300, y: 0, width: 30, height: 500)
        let folded = CoachingLayout.resolve(size: size, division: fold, duoDisplay: true)
        XCTAssertEqual(folded.mode, .book)
        XCTAssertEqual(folded.pitchPane.maxX, 300)
        XCTAssertEqual(try XCTUnwrap(folded.coachPane).minX, 330)
    }

    func testWindowResizingNeverCreatesOverlappingOrOutOfBoundsPanes() throws {
        for width in stride(from: 320.0, through: 1400, by: 40) {
            for height in [300.0, 600, 1000] {
                let size = CGSize(width: width, height: height)
                let layout = CoachingLayout.resolve(size: size, division: nil)
                XCTAssertGreaterThan(layout.pitchPane.width, 0)
                XCTAssertEqual(layout.pitchPane.minY, 0)
                XCTAssertEqual(layout.pitchPane.height, size.height)
                if let settings = layout.coachPane {
                    XCTAssertGreaterThan(settings.width, 0)
                    XCTAssertEqual(layout.pitchPane.maxX, settings.minX)
                    XCTAssertEqual(settings.maxX, size.width)
                    XCTAssertFalse(layout.pitchPane.intersects(settings))
                } else {
                    XCTAssertEqual(layout.pitchPane.size, size)
                }
            }
        }
    }

    func testCompactPitchPreservesAspectAndFitsItsWindowBudget() {
        for size in windows {
            for largeText in [false, true] {
                let metrics = CompactPitchMetrics.resolve(size: size, largeText: largeText)
                XCTAssertGreaterThan(metrics.pitchSize.width, 0)
                XCTAssertGreaterThan(metrics.pitchSize.height, 0)
                XCTAssertLessThanOrEqual(metrics.pitchSize.width, max(0, size.width - metrics.padding * 2) + 0.000001)
                XCTAssertLessThanOrEqual(metrics.pitchSize.height, size.height * (largeText ? 0.42 : 0.60) + 0.000001)
                let projection = PitchProjection(size: metrics.pitchSize, horizontal: metrics.horizontal)
                XCTAssertEqual(projection.bounds.width / projection.bounds.height, PitchDimensions.aspectRatio(horizontal: metrics.horizontal), accuracy: 0.000001)
            }
        }
    }

    func testFlatDuoUsesDedicatedControlsBelowOrdinaryDeskBreakpoints() throws {
        let size = CGSize(width: 500, height: 800)
        let duo = CoachingLayout.resolve(size: size, division: nil, duoDisplay: true)
        XCTAssertEqual(duo.mode, .desk)
        XCTAssertTrue(duo.usesDuoControls)
        XCTAssertEqual(duo.pitchPane.height, size.height)
        XCTAssertEqual(try XCTUnwrap(duo.coachPane).minX, duo.pitchPane.maxX)
        XCTAssertEqual(duo.controlSections, [.routes, .ai, .role])
        XCTAssertEqual(duo.controlPanelPadding, 22)
        let regular = CoachingLayout.resolve(size: size, division: nil)
        XCTAssertEqual(regular.mode, .compact)
        XCTAssertFalse(regular.usesDuoControls)
    }

    func testSameWideWindowUsesDifferentDuoAndRegularControlPresentations() {
        let size = CGSize(width: 650, height: 500)
        let duo = CoachingLayout.resolve(size: size, division: nil, duoDisplay: true)
        let regular = CoachingLayout.resolve(size: size, division: nil)
        XCTAssertEqual(duo.mode, .desk)
        XCTAssertEqual(regular.mode, .desk)
        XCTAssertEqual(duo.controlSections, [.routes, .ai, .role])
        XCTAssertEqual(regular.controlSections, [.role, .routes, .ai])
        XCTAssertEqual(duo.controlPanelPadding, 22)
        XCTAssertEqual(regular.controlPanelPadding, 14)
    }

    func testActiveBookFoldSelectsDuoControlsEvenWithoutInactiveRegionDetection() {
        let layout = CoachingLayout.resolve(
            size: CGSize(width: 800, height: 700),
            division: CGRect(x: 380, y: 0, width: 40, height: 700)
        )
        XCTAssertEqual(layout.mode, .book)
        XCTAssertTrue(layout.usesDuoControls)
        XCTAssertEqual(layout.controlSections.first, .routes)
    }

    func testActiveTabletopFoldAlsoKeepsDedicatedDuoControls() {
        let layout = CoachingLayout.resolve(
            size: CGSize(width: 800, height: 700),
            division: CGRect(x: 0, y: 330, width: 800, height: 40)
        )
        XCTAssertEqual(layout.mode, .tabletop)
        XCTAssertTrue(layout.usesDuoControls)
        XCTAssertEqual(layout.controlSections, [.routes, .ai, .role])
    }

    func testAccessibilityTextDoesNotSwitchFlatDuoToRegularPhoneControls() {
        let layout = CoachingLayout.resolve(
            size: CGSize(width: 500, height: 800), division: nil, largeText: true, duoDisplay: true
        )
        XCTAssertEqual(layout.mode, .desk)
        XCTAssertTrue(layout.usesDuoControls)
    }

    func testClosedOrTooNarrowDuoViewDoesNotForceTwoUnusablePanes() throws {
        for width in [390.0, 479] {
            let layout = CoachingLayout.resolve(size: CGSize(width: width, height: 800), division: nil, duoDisplay: true)
            XCTAssertEqual(layout.mode, .compact)
            XCTAssertFalse(layout.usesDuoControls)
            XCTAssertNil(layout.coachPane)
        }
        let minimum = CoachingLayout.resolve(size: CGSize(width: 480, height: 800), division: nil, duoDisplay: true)
        XCTAssertEqual(minimum.mode, .desk)
        XCTAssertEqual(minimum.pitchPane.width, 240)
        XCTAssertEqual(try XCTUnwrap(minimum.coachPane).width, 240)
    }

    func testSmallPhonesUseTighterMarginsAndNoOversizedIntroduction() {
        let small = CompactPitchMetrics.resolve(size: CGSize(width: 320, height: 480), largeText: false)
        XCTAssertEqual(small.padding, 14)
        XCTAssertEqual(small.spacing, 14)
        XCTAssertFalse(small.showIntroduction)
        let regular = CompactPitchMetrics.resolve(size: CGSize(width: 430, height: 850), largeText: false)
        XCTAssertEqual(regular.padding, 20)
        XCTAssertFalse(regular.showIntroduction)
    }

    func testIntroductionOnlyAppearsWhenThereIsRoomAndNormalText() {
        XCTAssertTrue(CompactPitchMetrics.resolve(size: CGSize(width: 600, height: 1000), largeText: false).showIntroduction)
        XCTAssertFalse(CompactPitchMetrics.resolve(size: CGSize(width: 600, height: 1000), largeText: true).showIntroduction)
        XCTAssertFalse(CompactPitchMetrics.resolve(size: CGSize(width: 600, height: 800), largeText: false).showIntroduction)
    }

    func testLargeTextReservesMoreSpaceForReadableControls() {
        let size = CGSize(width: 390, height: 760)
        let normal = CompactPitchMetrics.resolve(size: size, largeText: false)
        let large = CompactPitchMetrics.resolve(size: size, largeText: true)
        XCTAssertLessThan(large.pitchSize.height, normal.pitchSize.height)
    }

    func testZeroSizeLayoutPassProducesNoNegativePitchDimensions() {
        let metrics = CompactPitchMetrics.resolve(size: .zero, largeText: false)
        XCTAssertEqual(metrics.pitchSize, .zero)
    }

    func testRouteAndPlayerCoordinatesSurviveAllCompactViewportSizes() {
        let point = FieldPoint(depth: 0.37, width: 0.82)
        for size in windows {
            let metrics = CompactPitchMetrics.resolve(size: size, largeText: false)
            let projection = PitchProjection(size: metrics.pitchSize, horizontal: metrics.horizontal)
            let restored = projection.fieldPoint(projection.location(point))
            XCTAssertEqual(restored.depth, point.depth, accuracy: 0.000001)
            XCTAssertEqual(restored.width, point.width, accuracy: 0.000001)
        }
    }
}
