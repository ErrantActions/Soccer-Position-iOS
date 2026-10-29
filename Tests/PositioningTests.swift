import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class PositioningTests: XCTestCase {
    func testEveryPositionStaysInsideItsBounds() {
        for position in Position.allCases {
            for depth in stride(from: -0.1, through: 1.1, by: 0.05) {
                for width in stride(from: -0.1, through: 1.1, by: 0.05) {
                    let result = Positioning.recommend(ball: FieldPoint(depth: depth, width: width), position: position)
                    XCTAssertTrue((0...1).contains(result.point.depth))
                    XCTAssertTrue(position.widthRange.contains(result.point.width))
                    XCTAssertFalse(result.cue.isEmpty)
                    XCTAssertEqual(result, Positioning.recommend(ball: FieldPoint(depth: depth, width: width), position: position))
                }
            }
        }
    }

    func testLeftAndRightRolesMirror() {
        for pair in [(Position.lb, Position.rb), (.lcb, .rcb)] {
            let left = Positioning.recommend(ball: FieldPoint(depth: 0.6, width: 0.2), position: pair.0)
            let right = Positioning.recommend(ball: FieldPoint(depth: 0.6, width: 0.8), position: pair.1)
            XCTAssertEqual(left.point.depth, right.point.depth, accuracy: 0.00001)
            XCTAssertEqual(left.point.width, 1 - right.point.width, accuracy: 0.00001)
        }
    }

    func testGoalSideWhenSpaceAllows() {
        for position in Position.allCases {
            let result = Positioning.recommend(ball: FieldPoint(depth: 0.6, width: 0.5), position: position)
            XCTAssertLessThan(result.point.depth, 0.6)
        }
    }
}
