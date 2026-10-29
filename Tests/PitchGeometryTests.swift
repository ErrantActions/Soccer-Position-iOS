import CoreGraphics
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class PitchGeometryTests: XCTestCase {
    private let sizes = [
        CGSize(width: 240, height: 800), CGSize(width: 800, height: 240),
        CGSize(width: 800, height: 800), CGSize(width: 390, height: 600),
        CGSize(width: 650, height: 500), CGSize(width: 200, height: 150),
    ]

    func testActualTouchlineBoundsHaveRealFieldAspectInEveryPane() {
        for size in sizes {
            for horizontal in [false, true] {
                let projection = PitchProjection(size: size, horizontal: horizontal)
                XCTAssertTrue(projection.isUsable)
                XCTAssertEqual(
                    projection.bounds.width / projection.bounds.height,
                    horizontal ? 105.0 / 68.0 : 68.0 / 105.0,
                    accuracy: 0.000001
                )
                XCTAssertEqual(projection.bounds.midX, size.width / 2, accuracy: 0.000001)
                XCTAssertEqual(projection.bounds.midY, size.height / 2, accuracy: 0.000001)
                XCTAssertGreaterThanOrEqual(projection.bounds.minX, 26 - 0.000001)
                XCTAssertGreaterThanOrEqual(projection.bounds.minY, 26 - 0.000001)
                XCTAssertLessThanOrEqual(projection.bounds.maxX, size.width - 26 + 0.000001)
                XCTAssertLessThanOrEqual(projection.bounds.maxY, size.height - 26 + 0.000001)
            }
        }
    }

    func testOneMetreHasTheSamePixelLengthInBothAxes() {
        for size in sizes {
            for horizontal in [false, true] {
                let projection = PitchProjection(size: size, horizontal: horizontal)
                let origin = projection.meterLocation(depth: 30, width: 20)
                let depth = projection.meterLocation(depth: 31, width: 20)
                let width = projection.meterLocation(depth: 30, width: 21)
                XCTAssertEqual(hypot(depth.x - origin.x, depth.y - origin.y), projection.metersToPoints, accuracy: 0.000001)
                XCTAssertEqual(hypot(width.x - origin.x, width.y - origin.y), projection.metersToPoints, accuracy: 0.000001)
            }
        }
    }

    func testFittedCanvasNeverOverflowsItsPaneOrStretchesItsPlayingArea() {
        for size in sizes {
            for horizontal in [false, true] {
                let viewport = PitchDimensions.fittedViewport(in: size, horizontal: horizontal)
                XCTAssertLessThanOrEqual(viewport.width, size.width + 0.000001)
                XCTAssertLessThanOrEqual(viewport.height, size.height + 0.000001)
                let projection = PitchProjection(size: viewport, horizontal: horizontal)
                XCTAssertEqual(projection.bounds.width / projection.bounds.height, PitchDimensions.aspectRatio(horizontal: horizontal), accuracy: 0.000001)
                XCTAssertEqual(projection.bounds.width + 52, viewport.width, accuracy: 0.000001)
                XCTAssertEqual(projection.bounds.height + 52, viewport.height, accuracy: 0.000001)
            }
        }
    }

    func testLetterboxingRatherThanStretchingWhenPaneIsSquare() {
        let portrait = PitchProjection(size: CGSize(width: 800, height: 800), horizontal: false)
        XCTAssertGreaterThan(portrait.bounds.minX, portrait.bounds.minY)
        let landscape = PitchProjection(size: CGSize(width: 800, height: 800), horizontal: true)
        XCTAssertGreaterThan(landscape.bounds.minY, landscape.bounds.minX)
    }

    func testChangingAvailableHeightNeverChangesFieldAspect() {
        for height in [300.0, 400, 500, 700] {
            let projection = PitchProjection(size: CGSize(width: 400, height: height), horizontal: false)
            XCTAssertEqual(projection.bounds.width / projection.bounds.height, 68.0 / 105.0, accuracy: 0.000001)
        }
    }

    func testCenterCircleUsesEqualPhysicalRadiiNotAStretchedEllipse() {
        for horizontal in [false, true] {
            let projection = PitchProjection(size: CGSize(width: 720, height: 500), horizontal: horizontal)
            let center = projection.meterLocation(depth: 52.5, width: 34)
            let upfield = projection.meterLocation(depth: 52.5 + PitchDimensions.centerCircleRadius, width: 34)
            let across = projection.meterLocation(depth: 52.5, width: 34 + PitchDimensions.centerCircleRadius)
            XCTAssertEqual(hypot(upfield.x - center.x, upfield.y - center.y), 9.15 * projection.metersToPoints, accuracy: 0.000001)
            XCTAssertEqual(hypot(across.x - center.x, across.y - center.y), 9.15 * projection.metersToPoints, accuracy: 0.000001)
        }
    }

    func testPenaltyAndGoalAreasUseRealMetres() {
        XCTAssertEqual(PitchDimensions.penaltyAreaWidth, 40.32, accuracy: 0.000001)
        XCTAssertEqual(PitchDimensions.goalAreaWidth, 18.32, accuracy: 0.000001)
        for horizontal in [false, true] {
            let projection = PitchProjection(size: CGSize(width: 800, height: 600), horizontal: horizontal)
            for (depth, width) in [
                (PitchDimensions.penaltyAreaDepth, PitchDimensions.penaltyAreaWidth),
                (PitchDimensions.goalAreaDepth, PitchDimensions.goalAreaWidth),
            ] {
                let rectangle = projection.meterRectangle(depth: 0...depth, width: ((68 - width) / 2)...((68 + width) / 2))
                XCTAssertEqual(horizontal ? rectangle.width : rectangle.height, depth * projection.metersToPoints, accuracy: 0.000001)
                XCTAssertEqual(horizontal ? rectangle.height : rectangle.width, width * projection.metersToPoints, accuracy: 0.000001)
            }
        }
    }

    func testPenaltySpotIsElevenMetresFromGoalAndGoalIsSevenPointThreeTwoWide() {
        for horizontal in [false, true] {
            let projection = PitchProjection(size: CGSize(width: 650, height: 500), horizontal: horizontal)
            let goal = projection.meterLocation(depth: 0, width: 34)
            let spot = projection.meterLocation(depth: PitchDimensions.penaltySpotDistance, width: 34)
            XCTAssertEqual(hypot(spot.x - goal.x, spot.y - goal.y), 11 * projection.metersToPoints, accuracy: 0.000001)
            let firstPost = projection.meterLocation(depth: 0, width: (68 - PitchDimensions.goalWidth) / 2)
            let secondPost = projection.meterLocation(depth: 0, width: (68 + PitchDimensions.goalWidth) / 2)
            XCTAssertEqual(hypot(firstPost.x - secondPost.x, firstPost.y - secondPost.y), 7.32 * projection.metersToPoints, accuracy: 0.000001)
        }
    }

    func testNormalizedPlayersAndRoutesRoundTripAfterFittingAndRotating() {
        let points = [
            FieldPoint(depth: 0, width: 0), FieldPoint(depth: 1, width: 1),
            FieldPoint(depth: 0.37, width: 0.82), FieldPoint(depth: 0.5, width: 0.5),
        ]
        for size in sizes {
            for horizontal in [false, true] {
                let viewport = PitchDimensions.fittedViewport(in: size, horizontal: horizontal)
                let projection = PitchProjection(size: viewport, horizontal: horizontal)
                for point in points {
                    let restored = projection.fieldPoint(projection.location(point))
                    XCTAssertEqual(restored.depth, point.depth, accuracy: 0.000001)
                    XCTAssertEqual(restored.width, point.width, accuracy: 0.000001)
                }
            }
        }
    }

    func testPaddingIsNotAnInteractiveFieldButBoundaryMarkersRemainGrabbable() {
        let projection = PitchProjection(size: CGSize(width: 400, height: 600), horizontal: false)
        XCTAssertFalse(projection.interactionBounds.contains(CGPoint(x: 0, y: 300)))
        XCTAssertFalse(projection.interactionBounds.contains(CGPoint(x: 200, y: 0)))
        XCTAssertTrue(projection.interactionBounds.contains(projection.location(FieldPoint(depth: 0, width: 0.5))))
        XCTAssertTrue(projection.interactionBounds.contains(projection.location(FieldPoint(depth: 1, width: 0.5))))
    }

    func testEmptyAndTinyLayoutPassesStayNoninteractiveAndFinite() {
        for size in [CGSize.zero, CGSize(width: 30, height: 200), CGSize(width: 200, height: 30)] {
            let projection = PitchProjection(size: size, horizontal: false)
            XCTAssertFalse(projection.isUsable)
            let point = projection.fieldPoint(.zero)
            XCTAssertTrue(point.depth.isFinite)
            XCTAssertTrue(point.width.isFinite)
            let viewport = PitchDimensions.fittedViewport(in: size, horizontal: false)
            XCTAssertLessThanOrEqual(viewport.width, size.width)
            XCTAssertLessThanOrEqual(viewport.height, size.height)
        }
    }
}
