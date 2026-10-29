import CoreGraphics
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class PitchMarkerMetricsTests: XCTestCase {
    func testPhoneAndTabletKeepTheirOriginalMetrics() {
        for size in [CGSize(width: 390, height: 600), CGSize(width: 1024, height: 768), CGSize(width: 1920, height: 1080)] {
            let projection = PitchProjection(size: size, horizontal: size.width > size.height)
            let metrics = PitchMarkerMetrics(projection: projection)
            XCTAssertEqual(metrics.scale, 1)
            XCTAssertEqual(metrics.animationRadius, min(20, max(11, projection.metersToPoints * 2.4)))
            XCTAssertEqual(metrics.animationBallFont, 24)
            XCTAssertEqual(metrics.roleDiameter, 48)
            XCTAssertEqual(metrics.routeWidth, 2.5)
            XCTAssertEqual(metrics.arrowLength, 10)
        }
    }

    func testDefaultTVMarkersAreAtLeastTwiceThePreviousFixedMaximum() {
        for size in [CGSize(width: 1280, height: 720), CGSize(width: 1920, height: 1080), CGSize(width: 3840, height: 2160)] {
            let projection = PitchProjection(size: size, horizontal: true, presentation: .standard)
            let metrics = PitchMarkerMetrics(projection: projection)
            XCTAssertGreaterThanOrEqual(metrics.animationRadius * 2, 80)
            XCTAssertGreaterThanOrEqual(metrics.animationBallFont, 48)
            XCTAssertGreaterThanOrEqual(metrics.roleDiameter, 96)
            XCTAssertGreaterThanOrEqual(metrics.animationLabelFont, 34)
            XCTAssertGreaterThanOrEqual(metrics.routeWidth, 5)
        }
    }

    func testLogicalPhoneSizedExternalSceneStillGetsLargerMarkers() {
        let projection = PitchProjection(size: CGSize(width: 390, height: 844), horizontal: false, presentation: .standard)
        let metrics = PitchMarkerMetrics(projection: projection)
        XCTAssertGreaterThanOrEqual(metrics.scale, 2)
        XCTAssertGreaterThanOrEqual(metrics.roleDiameter, 96)
        XCTAssertGreaterThanOrEqual(metrics.animationBallFont, 48)
    }

    func testHigherResolutionExternalFieldsScaleProportionallyInsteadOfCappingAtTwentyPoints() {
        let small = PitchMarkerMetrics(projection: PitchProjection(size: CGSize(width: 1920, height: 1080), horizontal: true, presentation: .standard))
        let large = PitchMarkerMetrics(projection: PitchProjection(size: CGSize(width: 3840, height: 2160), horizontal: true, presentation: .standard))
        XCTAssertEqual(large.animationRadius / small.animationRadius, 2, accuracy: 1e-9)
        XCTAssertEqual(large.animationBallFont / small.animationBallFont, 2, accuracy: 1e-9)
        XCTAssertEqual(large.animationLabelFont / small.animationLabelFont, 2, accuracy: 1e-9)
    }

    func testEveryTVSizeKeepsEdgeMarkersInsideTheCanvas() {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 960, height: 540), CGSize(width: 1920, height: 1080), CGSize(width: 3840, height: 2160)] {
            for setting in TVMarkerSize.allCases {
                for format in TeamFormat.allCases {
                    let projection = PitchProjection(size: size, horizontal: size.width > size.height, format: format, presentation: setting)
                    let metrics = PitchMarkerMetrics(projection: projection)
                    let radius = metrics.roleDiameter / 2
                    XCTAssertGreaterThanOrEqual(projection.bounds.minX, radius)
                    XCTAssertGreaterThanOrEqual(projection.bounds.minY, radius)
                    XCTAssertLessThanOrEqual(projection.bounds.maxX + radius, size.width)
                    XCTAssertLessThanOrEqual(projection.bounds.maxY + radius, size.height)
                    XCTAssertGreaterThanOrEqual(radius, metrics.animationRadius)
                }
            }
        }
    }

    func testSizeChoicesIncreasePlayersLabelsBallAndRoutes() {
        let size = CGSize(width: 1920, height: 1080)
        var previous: PitchMarkerMetrics?
        for setting in TVMarkerSize.allCases {
            let metrics = PitchMarkerMetrics(projection: PitchProjection(size: size, horizontal: true, presentation: setting))
            if let previous {
                XCTAssertGreaterThan(metrics.roleDiameter, previous.roleDiameter)
                XCTAssertGreaterThan(metrics.animationRadius, previous.animationRadius)
                XCTAssertGreaterThan(metrics.animationLabelFont, previous.animationLabelFont)
                XCTAssertGreaterThan(metrics.animationBallFont, previous.animationBallFont)
                XCTAssertGreaterThan(metrics.routeWidth, previous.routeWidth)
                XCTAssertGreaterThan(metrics.arrowLength, previous.arrowLength)
            }
            previous = metrics
        }
    }

    func testTVPaddingPreservesPitchAspectAndCoordinateRoundTrips() {
        for format in TeamFormat.allCases {
            for setting in TVMarkerSize.allCases {
                let projection = PitchProjection(size: CGSize(width: 1920, height: 1080), horizontal: true, format: format, presentation: setting)
                XCTAssertEqual(projection.bounds.width / projection.bounds.height, format.fieldLength / format.fieldWidth, accuracy: 1e-9)
                let point = FieldPoint(depth: 0.83, width: 0.17)
                let actual = projection.fieldPoint(projection.location(point))
                XCTAssertEqual(actual.depth, point.depth, accuracy: 1e-9)
                XCTAssertEqual(actual.width, point.width, accuracy: 1e-9)
            }
        }
    }

    func testSizingDoesNotChangePhysicalPracticeDistances() {
        let projection = PitchProjection(size: CGSize(width: 1920, height: 1080), horizontal: true, presentation: .extraLarge)
        let first = projection.meterLocation(depth: 30, width: 30)
        let second = projection.meterLocation(depth: 38, width: 30)
        XCTAssertEqual(hypot(second.x - first.x, second.y - first.y), 8 * projection.metersToPoints, accuracy: 1e-9)
    }

    func testEmptyExternalViewportHasFiniteMetricsAndNoUsablePitch() {
        for setting in TVMarkerSize.allCases {
            let projection = PitchProjection(size: .zero, horizontal: true, presentation: setting)
            let metrics = PitchMarkerMetrics(projection: projection)
            XCTAssertFalse(projection.isUsable)
            XCTAssertTrue(metrics.scale.isFinite)
            XCTAssertTrue(metrics.animationRadius.isFinite)
        }
    }
}
