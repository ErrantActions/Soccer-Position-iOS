import CoreGraphics
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class CoachingLayoutTests: XCTestCase {
    func testCompactAndExpandedLayouts() {
        let compact = CoachingLayout.resolve(size: CGSize(width: 390, height: 780), division: nil)
        XCTAssertEqual(compact.mode, .compact)
        XCTAssertNil(compact.coachPane)
        let expanded = CoachingLayout.resolve(size: CGSize(width: 1000, height: 760), division: nil)
        XCTAssertEqual(expanded.mode, .desk)
        XCTAssertEqual(expanded.pitchPane.maxX, expanded.coachPane?.minX)
        XCTAssertEqual(expanded.coachPane?.maxX, 1000)
    }

    func testLargeTextUsesSingleScrollableColumnWhenFlat() {
        let layout = CoachingLayout.resolve(size: CGSize(width: 1000, height: 760), division: nil, largeText: true)
        XCTAssertEqual(layout.mode, .compact)
        XCTAssertNil(layout.coachPane)
    }

    func testBookFoldUsesActualOffCenterDivisionNotScreenMidpoint() throws {
        let fold = CGRect(x: 350, y: 0, width: 44, height: 760)
        let layout = CoachingLayout.resolve(size: CGSize(width: 900, height: 760), division: fold)
        XCTAssertEqual(layout.mode, .book)
        XCTAssertEqual(layout.pitchPane.maxX, fold.minX)
        XCTAssertEqual(layout.coachPane?.minX, fold.maxX)
        XCTAssertFalse(layout.pitchPane.intersects(fold))
        XCTAssertFalse(try XCTUnwrap(layout.coachPane).intersects(fold))
    }

    func testTabletopKeepsPitchAndControlsOnOppositeSides() throws {
        let fold = CGRect(x: 0, y: 280, width: 900, height: 36)
        let layout = CoachingLayout.resolve(size: CGSize(width: 900, height: 650), division: fold)
        XCTAssertEqual(layout.mode, .tabletop)
        XCTAssertEqual(layout.pitchPane.maxY, 280)
        XCTAssertEqual(try XCTUnwrap(layout.coachPane).minY, 316)
        XCTAssertEqual(try XCTUnwrap(layout.coachPane).maxY, 650)
    }

    func testNarrowPaneAndPartialDivisionDoNotPutContentAcrossFold() {
        let fold = CGRect(x: -10, y: 0, width: 40, height: 760)
        let layout = CoachingLayout.resolve(size: CGSize(width: 500, height: 760), division: fold)
        XCTAssertEqual(layout.mode, .compact)
        XCTAssertEqual(layout.pitchPane.minX, 30)
        XCTAssertEqual(layout.pitchPane.maxX, 500)
        XCTAssertNil(layout.coachPane)
    }

    func testDivisionOutsideViewDoesNotChangeNormalLayout() {
        let layout = CoachingLayout.resolve(
            size: CGSize(width: 390, height: 780),
            division: CGRect(x: 500, y: 0, width: 20, height: 780)
        )
        XCTAssertEqual(layout.pitchPane, CGRect(x: 0, y: 0, width: 390, height: 780))
    }

    func testLargeTextStillRespectsActiveFold() throws {
        let fold = CGRect(x: 420, y: 0, width: 30, height: 760)
        let layout = CoachingLayout.resolve(size: CGSize(width: 900, height: 760), division: fold, largeText: true)
        XCTAssertEqual(layout.mode, .book)
        XCTAssertEqual(try XCTUnwrap(layout.coachPane).minX, fold.maxX)
    }

    func testCoordinatesRoundTripInBothOrientations() {
        for horizontal in [false, true] {
            let projection = PitchProjection(size: CGSize(width: 460, height: 600), horizontal: horizontal)
            for depth in stride(from: 0.0, through: 1, by: 0.1) {
                for width in stride(from: 0.0, through: 1, by: 0.1) {
                    let point = FieldPoint(depth: depth, width: width)
                    let result = projection.fieldPoint(projection.location(point))
                    XCTAssertEqual(result.depth, depth, accuracy: 0.000001)
                    XCTAssertEqual(result.width, width, accuracy: 0.000001)
                }
            }
        }
    }

    func testTouchCoordinatesAreClampedToPitch() {
        for horizontal in [false, true] {
            let projection = PitchProjection(size: CGSize(width: 390, height: 500), horizontal: horizontal)
            let point = projection.fieldPoint(CGPoint(x: -500, y: 5000))
            XCTAssertTrue((0...1).contains(point.depth))
            XCTAssertTrue((0...1).contains(point.width))
        }
    }

    func testOrientationKeepsOwnGoalAtBottomOrLeft() {
        let size = CGSize(width: 400, height: 600)
        let goal = FieldPoint(depth: 0, width: 0.5)
        let portrait = PitchProjection(size: size, horizontal: false)
        XCTAssertEqual(portrait.location(goal).y, portrait.bounds.maxY)
        let landscape = PitchProjection(size: size, horizontal: true)
        XCTAssertEqual(landscape.location(goal).x, landscape.bounds.minX)
    }

    func testNormalizedRoutesSurviveSizeAndOrientationChanges() {
        let route = [FieldPoint(depth: 0.2, width: 0.1), FieldPoint(depth: 0.7, width: 0.8)]
        for size in [CGSize(width: 350, height: 500), CGSize(width: 700, height: 250)] {
            for horizontal in [false, true] {
                let projection = PitchProjection(size: size, horizontal: horizontal)
                for point in route {
                    let restored = projection.fieldPoint(projection.location(point))
                    XCTAssertEqual(restored.depth, point.depth, accuracy: 0.000001)
                    XCTAssertEqual(restored.width, point.width, accuracy: 0.000001)
                }
            }
        }
    }

    func testPresetsRemainInBoundsAndFlanksMirror() {
        for scenario in FieldScenario.allCases {
            XCTAssertEqual(scenario.point, scenario.point.bounded)
        }
        XCTAssertEqual(FieldScenario.leftFlank.point.depth, FieldScenario.rightFlank.point.depth)
        XCTAssertEqual(FieldScenario.leftFlank.point.width, 1 - FieldScenario.rightFlank.point.width, accuracy: 0.000001)
    }
}
