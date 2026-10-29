import CoreGraphics
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class RouteDrawingTests: XCTestCase {
    private let projection = PitchProjection(size: CGSize(width: 400, height: 600), horizontal: false)

    @discardableResult
    private func stroke(
        _ drawing: inout RouteDrawing, points: [FieldPoint], style: RouteStyle = .curve,
        anchors: [FieldPoint] = [], snap: Bool = false
    ) -> Bool {
        drawing.begin(at: points[0], style: style, projection: projection, anchors: anchors, snap: snap)
        for point in points.dropFirst() {
            drawing.update(at: point, projection: projection, anchors: anchors, snap: snap)
        }
        return drawing.finish(at: points[points.count - 1], projection: projection, anchors: anchors, snap: snap)
    }

    func testIgnoresTapsAndSmallJitterWithoutAddingHistory() {
        var drawing = RouteDrawing()
        let points = [100.0, 103, 100, 103, 100, 103, 100].map {
            projection.fieldPoint(CGPoint(x: $0, y: 300))
        }
        XCTAssertFalse(stroke(&drawing, points: points))
        XCTAssertFalse(drawing.canUndo)
        XCTAssertFalse(drawing.canRedo)
        XCTAssertTrue(drawing.preview.isEmpty)
    }

    func testStraightModeUsesOnlyStartAndEndEvenForACurvedGesture() throws {
        var drawing = RouteDrawing()
        let points = [
            FieldPoint(depth: 0.2, width: 0.2), FieldPoint(depth: 0.3, width: 0.8),
            FieldPoint(depth: 0.6, width: 0.1), FieldPoint(depth: 0.8, width: 0.7),
        ]
        XCTAssertTrue(stroke(&drawing, points: points, style: .straight))
        XCTAssertEqual(try XCTUnwrap(drawing.routes.first), [points[0], points[3]])
    }

    func testCurvePreservesMeaningfulCornersAndEndpoints() throws {
        var drawing = RouteDrawing()
        let points = [
            FieldPoint(depth: 0.2, width: 0.2), FieldPoint(depth: 0.4, width: 0.1),
            FieldPoint(depth: 0.6, width: 0.5), FieldPoint(depth: 0.8, width: 0.8),
        ]
        XCTAssertTrue(stroke(&drawing, points: points))
        let route = try XCTUnwrap(drawing.routes.first)
        XCTAssertGreaterThan(route.count, 2)
        XCTAssertEqual(route.first, points.first)
        XCTAssertEqual(route.last, points.last)
    }

    func testRemovesSmallFreehandWobbleFromANearlyStraightRoute() throws {
        var drawing = RouteDrawing()
        let points = (0...60).map { index in
            projection.fieldPoint(CGPoint(x: 100 + Double(index) * 2, y: 300 + (index.isMultiple(of: 2) ? 0.8 : -0.8)))
        }
        XCTAssertTrue(stroke(&drawing, points: points))
        XCTAssertEqual(try XCTUnwrap(drawing.routes.first), [points[0], points[60]])
    }

    func testSamplingDoesNotDropTheActualFinalEndpoint() throws {
        var drawing = RouteDrawing()
        let start = projection.fieldPoint(CGPoint(x: 100, y: 300))
        let middle = projection.fieldPoint(CGPoint(x: 130, y: 300))
        let end = projection.fieldPoint(CGPoint(x: 131, y: 300))
        drawing.begin(at: start, style: .curve, projection: projection, anchors: [], snap: false)
        drawing.update(at: middle, projection: projection, anchors: [], snap: false)
        XCTAssertTrue(drawing.finish(at: end, projection: projection, anchors: [], snap: false))
        XCTAssertEqual(try XCTUnwrap(drawing.routes.first).last, end)
    }

    func testSnapsOnlyToTheNearestAnchorWithinEighteenScreenPoints() {
        let anchor = FieldPoint(depth: 0.5, width: 0.5)
        let location = projection.location(anchor)
        let near = projection.fieldPoint(CGPoint(x: location.x + 17, y: location.y))
        let far = projection.fieldPoint(CGPoint(x: location.x + 19, y: location.y))
        XCTAssertEqual(RouteDrawing.nearestAnchor(to: near, anchors: [anchor], projection: projection), anchor)
        XCTAssertNil(RouteDrawing.nearestAnchor(to: far, anchors: [anchor], projection: projection))
        let closer = projection.fieldPoint(CGPoint(x: location.x + 15, y: location.y))
        XCTAssertEqual(RouteDrawing.nearestAnchor(to: near, anchors: [anchor, closer], projection: projection), closer)
    }

    func testSnapsStartAndEndAndClearsTargetAfterFinishing() throws {
        var drawing = RouteDrawing()
        let first = FieldPoint(depth: 0.2, width: 0.3)
        let last = FieldPoint(depth: 0.8, width: 0.7)
        let start = projection.location(first)
        let end = projection.location(last)
        let points = [
            projection.fieldPoint(CGPoint(x: start.x + 6, y: start.y)),
            FieldPoint(depth: 0.5, width: 0.5),
            projection.fieldPoint(CGPoint(x: end.x - 6, y: end.y)),
        ]
        XCTAssertTrue(stroke(&drawing, points: points, anchors: [first, last], snap: true))
        let route = try XCTUnwrap(drawing.routes.first)
        XCTAssertEqual(route.first, first)
        XCTAssertEqual(route.last, last)
        XCTAssertNil(drawing.snapTarget)
    }

    func testSnappingCanBeDisabled() throws {
        var drawing = RouteDrawing()
        let first = FieldPoint(depth: 0.2, width: 0.3)
        let end = FieldPoint(depth: 0.8, width: 0.7)
        let anchor = FieldPoint(depth: 0.8, width: 0.71)
        XCTAssertTrue(stroke(&drawing, points: [first, end], anchors: [anchor], snap: false))
        XCTAssertEqual(try XCTUnwrap(drawing.routes.first).last, end)
    }

    func testUndoAndRedoRestoreTheExactRoute() throws {
        var drawing = RouteDrawing()
        stroke(&drawing, points: [FieldPoint(depth: 0.2, width: 0.2), FieldPoint(depth: 0.8, width: 0.8)])
        let original = try XCTUnwrap(drawing.routes.first)
        drawing.undo()
        XCTAssertTrue(drawing.routes.isEmpty)
        XCTAssertTrue(drawing.canRedo)
        drawing.redo()
        XCTAssertEqual(drawing.routes, [original])
        XCTAssertFalse(drawing.canRedo)
    }

    func testNewRouteClearsRedoButAnIgnoredTapDoesNot() {
        var drawing = RouteDrawing()
        let first = FieldPoint(depth: 0.2, width: 0.2)
        let last = FieldPoint(depth: 0.8, width: 0.8)
        stroke(&drawing, points: [first, last])
        drawing.undo()
        XCTAssertFalse(stroke(&drawing, points: [first]))
        XCTAssertTrue(drawing.canRedo)
        XCTAssertTrue(stroke(&drawing, points: [first, FieldPoint(depth: 0.8, width: 0.2)]))
        XCTAssertFalse(drawing.canRedo)
    }

    func testCancellingAnInterruptedStrokePreservesFinishedRoutes() {
        var drawing = RouteDrawing()
        let first = FieldPoint(depth: 0.2, width: 0.2)
        let last = FieldPoint(depth: 0.8, width: 0.8)
        stroke(&drawing, points: [first, last])
        let saved = drawing.routes
        drawing.begin(at: first, style: .curve, projection: projection, anchors: [], snap: false)
        drawing.update(at: last, projection: projection, anchors: [], snap: false)
        drawing.cancelStroke()
        XCTAssertEqual(drawing.routes, saved)
        XCTAssertTrue(drawing.preview.isEmpty)
        drawing.clear()
        XCTAssertTrue(drawing.routes.isEmpty)
        XCTAssertFalse(drawing.canRedo)
        XCTAssertFalse(drawing.canUndo)
    }

    func testArrowUsesLastDistinctSegmentInsteadOfRepeatedTouchSamples() throws {
        let start = projection.fieldPoint(CGPoint(x: 200, y: 300))
        let end = projection.fieldPoint(CGPoint(x: 200, y: 100))
        let direction = try XCTUnwrap(RouteDrawing.arrowDirection(for: [start, end, end, end], projection: projection))
        XCTAssertEqual(direction.dx, 0, accuracy: 0.000001)
        XCTAssertEqual(direction.dy, -1, accuracy: 0.000001)
        XCTAssertNil(RouteDrawing.arrowDirection(for: [end, end, end], projection: projection))
    }

    func testRoutesStayNormalizedAcrossOrientationChanges() throws {
        var drawing = RouteDrawing()
        stroke(&drawing, points: [FieldPoint(depth: -1, width: 0.2), FieldPoint(depth: 2, width: 0.8)])
        let route = try XCTUnwrap(drawing.routes.first)
        let horizontal = PitchProjection(size: CGSize(width: 760, height: 320), horizontal: true)
        for point in route {
            XCTAssertEqual(point, point.bounded)
            let restored = horizontal.fieldPoint(horizontal.location(point))
            XCTAssertEqual(restored.depth, point.depth, accuracy: 0.000001)
            XCTAssertEqual(restored.width, point.width, accuracy: 0.000001)
        }
    }
}
