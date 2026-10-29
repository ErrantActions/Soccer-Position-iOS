import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class AIPositioningTests: XCTestCase {
    private var scene: TacticalScene {
        TacticalScene(
            ball: TacticalScene.initialBall, formation: .fourThreeThree,
            teammates: TacticalScene.defaultTeammates, opponents: TacticalScene.defaultOpponents
        )
    }

    private var validPlan: AIPositionPlan {
        AIPositionPlan(players: [
            PlayerAdvice(role: .lb, point: FieldPoint(depth: 0.3, width: 0.18), reason: "Cover the left channel."),
            PlayerAdvice(role: .lcb, point: FieldPoint(depth: 0.25, width: 0.4), reason: "Protect the central goal corridor."),
            PlayerAdvice(role: .rcb, point: FieldPoint(depth: 0.25, width: 0.6), reason: "Cover the right center channel."),
            PlayerAdvice(role: .rb, point: FieldPoint(depth: 0.3, width: 0.82), reason: "Maintain right-side balance."),
            PlayerAdvice(role: .cdm, point: FieldPoint(depth: 0.4, width: 0.5), reason: "Screen the middle."),
        ], summary: "Cover the central goal corridor while balancing both sides.")
    }

    private func replacing(
        _ role: Position, point: FieldPoint? = nil, reason: String? = nil, plan: AIPositionPlan? = nil
    ) -> AIPositionPlan {
        let original = plan ?? validPlan
        return AIPositionPlan(players: original.players.map {
            $0.role == role ? PlayerAdvice(role: role, point: point ?? $0.point, reason: reason ?? $0.reason) : $0
        }, summary: original.summary)
    }

    func testAcceptsACompleteCoordinatedDefensiveUnit() {
        XCTAssertTrue(AIPositionValidation.inputIssues(scene).isEmpty)
        XCTAssertTrue(AIPositionValidation.issues(validPlan, scene: scene).isEmpty)
    }

    func testDoesNotClampOrApplyNonfiniteOrOutOfBoundsOutput() {
        for value in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            for point in [FieldPoint(depth: value, width: 0.4), FieldPoint(depth: 0.25, width: value)] {
                let plan = replacing(.lcb, point: point)
                XCTAssertFalse(AIPositionValidation.issues(plan, scene: scene).isEmpty)
                var analysis = PositioningAnalysis()
                let request = analysis.begin(scene: scene, scheduled: false)
                XCTAssertFalse(analysis.finish(plan, request: request, currentScene: scene))
                XCTAssertNil(analysis.acceptedPlan(for: scene))
                XCTAssertTrue(analysis.status.contains("rejected"))
            }
        }
    }

    func testRejectsMissingAndDuplicateRoles() {
        let missing = AIPositionPlan(players: Array(validPlan.players.dropLast()), summary: validPlan.summary)
        XCTAssertFalse(AIPositionValidation.issues(missing, scene: scene).isEmpty)
        var players = validPlan.players
        players[4] = players[0]
        XCTAssertFalse(AIPositionValidation.issues(AIPositionPlan(players: players, summary: validPlan.summary), scene: scene).isEmpty)
    }

    func testRejectsRolesOutsideTheirChannels() {
        let plan = replacing(.lb, point: FieldPoint(depth: 0.3, width: 0.5))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("channel") })
    }

    func testRejectsTeammatesTooCloseTogether() {
        let plan = replacing(.rcb, point: FieldPoint(depth: 0.25, width: 0.42))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("too close") })
    }

    func testRejectsCrossedBackLineEvenWhenIndividualChannelsOverlap() {
        let plan = replacing(.rcb, point: FieldPoint(depth: 0.25, width: 0.45),
                             plan: replacing(.lcb, point: FieldPoint(depth: 0.25, width: 0.56)))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("crosses") })
    }

    func testRejectsAStretchedDefensiveLine() {
        let plan = replacing(.lb, point: FieldPoint(depth: 0.6, width: 0.18))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("stretched") })
    }

    func testRequiresCentralGoalCoverage() {
        let plan = replacing(.rcb, point: FieldPoint(depth: 0.25, width: 0.75),
                             plan: replacing(.lcb, point: FieldPoint(depth: 0.25, width: 0.25)))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("goal corridor") })
    }

    func testRejectsPositionBeyondGoalSideLimit() {
        let plan = replacing(.rb, point: FieldPoint(depth: 0.69, width: 0.82))
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: scene).contains { $0.contains("goal-side") })
    }

    func testAllowsRecoveryPositionsWhenTheBallIsCloseToGoal() {
        let danger = TacticalScene(
            ball: FieldPoint(depth: 0.05, width: 0.5), formation: .fourFourTwo,
            teammates: scene.teammates, opponents: scene.opponents
        )
        let plan = AIPositionPlan(players: validPlan.players.map {
            PlayerAdvice(role: $0.role, point: FieldPoint(depth: $0.role == .cdm ? 0.12 : 0.06, width: $0.point.width), reason: $0.reason)
        }, summary: validPlan.summary)
        XCTAssertTrue(AIPositionValidation.issues(plan, scene: danger).isEmpty)
    }

    func testRejectsCollisionsWithVisibleOpponents() {
        var opponents = scene.opponents
        opponents[0].point = validPlan.players[0].point
        let crowded = TacticalScene(ball: scene.ball, formation: scene.formation, teammates: scene.teammates, opponents: opponents)
        XCTAssertTrue(AIPositionValidation.issues(validPlan, scene: crowded).contains { $0.contains("overlaps an opponent") })
    }

    func testRequiresConciseReasonsAndSummary() {
        for reason in ["  \n", String(repeating: "x", count: 281)] {
            XCTAssertFalse(AIPositionValidation.issues(replacing(.lb, reason: reason), scene: scene).isEmpty)
        }
        for summary in ["", String(repeating: "x", count: 401)] {
            XCTAssertFalse(AIPositionValidation.issues(AIPositionPlan(players: validPlan.players, summary: summary), scene: scene).isEmpty)
        }
    }

    func testValidatesCurrentSceneBeforeRequestingAI() {
        let badBall = TacticalScene(ball: FieldPoint(depth: .nan, width: 0.5), formation: scene.formation, teammates: scene.teammates, opponents: scene.opponents)
        XCTAssertFalse(AIPositionValidation.inputIssues(badBall).isEmpty)
        let missingTeam = TacticalScene(ball: scene.ball, formation: scene.formation, teammates: Array(scene.teammates.dropLast()), opponents: scene.opponents)
        XCTAssertFalse(AIPositionValidation.inputIssues(missingTeam).isEmpty)
        let missingOpponent = TacticalScene(ball: scene.ball, formation: scene.formation, teammates: scene.teammates, opponents: Array(scene.opponents.dropLast()))
        XCTAssertFalse(AIPositionValidation.inputIssues(missingOpponent).isEmpty)
        var invalidPlayers = scene.teammates
        invalidPlayers[0].point = FieldPoint(depth: 1.2, width: 0.5)
        let outside = TacticalScene(ball: scene.ball, formation: scene.formation, teammates: invalidPlayers, opponents: scene.opponents)
        XCTAssertFalse(AIPositionValidation.inputIssues(outside).isEmpty)
    }

    func testScenePromptContainsActualFormationBallTeamAndOpposition() {
        XCTAssertTrue(scene.promptContext.contains("Formation: 4-3-3"))
        XCTAssertTrue(scene.promptContext.contains("depth=0.650 width=0.350"))
        XCTAssertTrue(scene.promptContext.contains("Own goal: depth=0, width=0.5"))
        XCTAssertTrue(scene.promptContext.contains("Current teammates:"))
        XCTAssertTrue(scene.promptContext.contains("CDM:"))
        XCTAssertTrue(scene.promptContext.contains("Opponents:"))
        XCTAssertTrue(scene.promptContext.contains("9:"))
        XCTAssertTrue(scene.promptContext.contains("Opposition has possession"))
    }

    func testAcceptedCoordinatesAndReasonsAreTheModelsActualProposal() throws {
        var analysis = PositioningAnalysis()
        let request = analysis.begin(scene: scene, scheduled: false)
        XCTAssertTrue(analysis.isBusy)
        XCTAssertTrue(analysis.finish(validPlan, request: request, currentScene: scene))
        let accepted = try XCTUnwrap(analysis.acceptedPlan(for: scene))
        XCTAssertEqual(accepted, validPlan)
        XCTAssertEqual(accepted.recommendation(for: .lb)?.point, validPlan.players[0].point)
        XCTAssertEqual(accepted.recommendation(for: .lb)?.cue, validPlan.players[0].reason)
        XCTAssertFalse(analysis.isBusy)
        XCTAssertNotEqual(accepted.recommendation(for: .lb)?.point, Positioning.recommend(ball: scene.ball, position: .lb).point)
    }

    func testAChangedSceneCannotDisplayAnEarlierAcceptedPlan() {
        var analysis = PositioningAnalysis()
        let request = analysis.begin(scene: scene, scheduled: false)
        analysis.finish(validPlan, request: request, currentScene: scene)
        let changed = TacticalScene(ball: FieldPoint(depth: 0.6, width: 0.9), formation: scene.formation, teammates: scene.teammates, opponents: scene.opponents)
        XCTAssertNil(analysis.acceptedPlan(for: changed))
        let formation = TacticalScene(ball: scene.ball, formation: .fourFourTwo, teammates: scene.teammates, opponents: scene.opponents)
        XCTAssertNil(analysis.acceptedPlan(for: formation))
        var opponents = scene.opponents
        opponents[0].point.width = 0.2
        XCTAssertNil(analysis.acceptedPlan(for: TacticalScene(ball: scene.ball, formation: scene.formation, teammates: scene.teammates, opponents: opponents)))
    }

    func testSupersededRequestsCannotOverwriteNewAnalysisEvenForTheSameScene() {
        var analysis = PositioningAnalysis()
        let old = analysis.begin(scene: scene, scheduled: false)
        let current = analysis.begin(scene: scene, scheduled: true)
        XCTAssertNotEqual(old.id, current.id)
        XCTAssertFalse(analysis.finish(validPlan, request: old, currentScene: scene))
        XCTAssertEqual(analysis.request, current)
        XCTAssertTrue(analysis.isBusy)
        XCTAssertTrue(analysis.finish(validPlan, request: current, currentScene: scene))
    }

    func testCancelledOrTimedOutRequestsCannotLaterApplyAPlan() {
        var analysis = PositioningAnalysis()
        let request = analysis.begin(scene: scene, scheduled: false)
        analysis.fail("Timed out. Showing the instant guide.", request: request)
        XCTAssertFalse(analysis.finish(validPlan, request: request, currentScene: scene))
        XCTAssertNil(analysis.plan)
        XCTAssertTrue(analysis.status.contains("Timed out"))
    }

    func testLateFailureCannotClearANewerRequest() {
        var analysis = PositioningAnalysis()
        let old = analysis.begin(scene: scene, scheduled: false)
        let current = analysis.begin(scene: scene, scheduled: false)
        analysis.fail("Old request failed", request: old)
        XCTAssertEqual(analysis.request, current)
        XCTAssertFalse(analysis.status.contains("Old request"))
    }

    func testStaleSceneCompletionStopsThinkingWithoutApplyingThePlan() {
        var analysis = PositioningAnalysis()
        let request = analysis.begin(scene: scene, scheduled: false)
        let changed = TacticalScene(ball: FieldPoint(depth: 0.3, width: 0.5), formation: scene.formation, teammates: scene.teammates, opponents: scene.opponents)
        XCTAssertFalse(analysis.finish(validPlan, request: request, currentScene: changed))
        XCTAssertFalse(analysis.isBusy)
        XCTAssertNil(analysis.plan)
        XCTAssertTrue(analysis.status.contains("Scene changed"))
    }

    func testRejectedOutputDoesNotRetainAFormerValidSuggestion() {
        var analysis = PositioningAnalysis()
        let first = analysis.begin(scene: scene, scheduled: false)
        analysis.finish(validPlan, request: first, currentScene: scene)
        let retry = analysis.begin(scene: scene, scheduled: false)
        XCTAssertNil(analysis.plan)
        let invalid = replacing(.lb, point: FieldPoint(depth: -1, width: 0.2))
        XCTAssertFalse(analysis.finish(invalid, request: retry, currentScene: scene))
        XCTAssertNil(analysis.plan)
        XCTAssertFalse(analysis.isBusy)
        XCTAssertTrue(analysis.status.contains("AI suggestion rejected"))
    }
}
