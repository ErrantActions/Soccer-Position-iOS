import Foundation
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class AnimationDraftTests: XCTestCase {
    private func starter() throws -> SavedPlay { try AnimationDraft.newPlay(board: SavedPlay.examples[0].board) }
    private func draft() throws -> AnimationDraft { try AnimationDraft(XCTUnwrap(starter().animation)) }

    func testNewPlayStartsWithCurrentSceneAndTwoValidPhases() throws {
        let board = SavedPlay.examples[1].board
        let play = try AnimationDraft.newPlay(board: board)
        try play.validate()
        let clip = try XCTUnwrap(play.animation)
        XCTAssertEqual(clip.frames.count, 2)
        XCTAssertEqual(clip.frames[0].ball, board.scene.ball)
        XCTAssertEqual(clip.frames[0].players.count, 8)
        XCTAssertEqual(clip.origin, .userCreated)
        XCTAssertTrue(clip.references.isEmpty)
        XCTAssertEqual(clip.frames.map(\.time), [0, 2])
    }

    func testInvalidStartingBoardIsRejected() {
        var board = SavedPlay.examples[0].board
        board.routes = [[FieldPoint(depth: 2, width: 0.5)]]
        XCTAssertThrowsError(try AnimationDraft.newPlay(board: board))
    }

    func testMoveAffectsOnlyTheSelectedPhaseAndItem() throws {
        var draft = try draft()
        let before = draft.animation
        try draft.selectPhase(1)
        try draft.select(.player(1))
        let destination = FieldPoint(depth: 0.7, width: 0.25)
        try draft.move(to: destination)
        XCTAssertEqual(draft.frame.players.first { $0.id == 1 }?.point, destination)
        XCTAssertEqual(draft.animation.frames[0], before.frames[0])
        XCTAssertEqual(draft.frame.ball, before.frames[1].ball)
        XCTAssertNotNil(draft.previousFrame)
        try draft.animation.validate()
    }

    func testBallMovementAndPassToReceiver() throws {
        var draft = try draft()
        let point = FieldPoint(depth: 0.6, width: 0.7)
        try draft.move(to: point)
        XCTAssertEqual(draft.frame.ball, point)
        try draft.select(.player(2))
        let receiver = try XCTUnwrap(draft.selectedPlayer)
        try draft.passToSelectedPlayer()
        XCTAssertEqual(draft.frame.ball, receiver.point)
    }

    func testInvalidTargetsAndCoordinatesDoNotMutateDraft() throws {
        var draft = try draft()
        let before = draft
        XCTAssertThrowsError(try draft.select(.player(999)))
        XCTAssertThrowsError(try draft.selectPhase(-1))
        XCTAssertThrowsError(try draft.selectPhase(10))
        XCTAssertThrowsError(try draft.move(to: FieldPoint(depth: .nan, width: 0.5)))
        XCTAssertThrowsError(try draft.move(to: FieldPoint(depth: 0.5, width: 1.01)))
        XCTAssertThrowsError(try draft.passToSelectedPlayer())
        XCTAssertEqual(draft, before)
    }

    func testInsertCopiesCurrentPositionsAndShiftsLaterTimes() throws {
        var draft = try draft()
        let original = draft.frame
        try draft.insertPhase(duration: 1.5)
        XCTAssertEqual(draft.phase, 1)
        XCTAssertEqual(draft.frame.players, original.players)
        XCTAssertEqual(draft.frame.ball, original.ball)
        XCTAssertEqual(draft.animation.frames.map(\.time), [0, 1.5, 3.5])
        try draft.animation.validate()
    }

    func testAppendingAfterFinalPhaseAndRemovingFirstMiddleAndLast() throws {
        var original = try draft()
        try original.selectPhase(1)
        try original.insertPhase()
        XCTAssertEqual(original.animation.frames.map(\.time), [0, 2, 4])
        for index in 0...2 {
            var edited = original
            try edited.selectPhase(index)
            try edited.removePhase()
            XCTAssertEqual(edited.animation.frames.count, 2)
            XCTAssertEqual(edited.animation.frames.map(\.time), [0, 2])
            XCTAssertTrue(edited.animation.frames.indices.contains(edited.phase))
            try edited.animation.validate()
        }
    }

    func testCannotRemoveBelowTwoPhasesOrAddPastTwentyFour() throws {
        var draft = try draft()
        XCTAssertThrowsError(try draft.removePhase())
        for _ in 2..<24 { try draft.insertPhase() }
        let full = draft
        XCTAssertThrowsError(try draft.insertPhase())
        XCTAssertEqual(draft, full)
        XCTAssertEqual(draft.animation.frames.count, 24)
    }

    func testTravelTimeShiftsAllLaterPhasesWithoutChangingPositions() throws {
        var draft = try draft()
        try draft.insertPhase()
        try draft.selectPhase(0)
        let players = draft.animation.frames.map(\.players)
        try draft.setTravelTime(0.25)
        XCTAssertEqual(draft.animation.frames.map(\.time), [0, 0.25, 2.25])
        XCTAssertEqual(draft.animation.frames.map(\.players), players)
        try draft.animation.validate()
    }

    func testDurationLimitsFailWithoutPartialChanges() throws {
        var draft = try draft()
        for time in [0.0, 0.24, .nan, .infinity, 121] {
            let before = draft
            XCTAssertThrowsError(try draft.setTravelTime(time))
            XCTAssertEqual(draft, before)
            XCTAssertThrowsError(try draft.insertPhase(duration: time))
            XCTAssertEqual(draft, before)
        }
        try draft.setTravelTime(120)
        XCTAssertEqual(draft.animation.duration, 120)
        let full = draft
        XCTAssertThrowsError(try draft.insertPhase())
        XCTAssertEqual(draft, full)
        try draft.selectPhase(1)
        XCTAssertNil(draft.travelTime)
        XCTAssertThrowsError(try draft.setTravelTime(1))
    }

    func testAddingPlayersCreatesStableIdentitiesAcrossEveryPhase() throws {
        var draft = try draft()
        try draft.addPlayer(team: .home)
        let home = try XCTUnwrap(draft.selectedPlayer)
        XCTAssertEqual(home.team, .home)
        try draft.addPlayer(team: .away)
        let away = try XCTUnwrap(draft.selectedPlayer)
        XCTAssertEqual(away.team, .away)
        XCTAssertNotEqual(home.id, away.id)
        for frame in draft.animation.frames {
            XCTAssertEqual(frame.players.first { $0.id == home.id }, home)
            XCTAssertEqual(frame.players.first { $0.id == away.id }, away)
            XCTAssertEqual(Set(frame.players.map(\.id)).count, frame.players.count)
        }
        try draft.animation.validate()
    }

    func testRosterMaximumAndMinimumAreEnforced() throws {
        var draft = try draft()
        while draft.frame.players.count < 22 { try draft.addPlayer(team: .home) }
        XCTAssertThrowsError(try draft.addPlayer(team: .away))
        while draft.frame.players.count > 2 {
            try draft.select(.player(draft.frame.players[0].id))
            try draft.removeSelectedPlayer()
        }
        try draft.select(.player(draft.frame.players[0].id))
        let minimum = draft
        XCTAssertThrowsError(try draft.removeSelectedPlayer())
        XCTAssertEqual(draft, minimum)
        try draft.animation.validate()
    }

    func testRenameAndRemoveApplyToAllPhasesAndRetainCoordinates() throws {
        var draft = try draft()
        try draft.select(.player(1))
        let positions = draft.animation.frames.map { $0.players[0].point }
        try draft.renameSelectedPlayer(" LW ")
        XCTAssertTrue(draft.animation.frames.allSatisfy { $0.players[0].label == "LW" })
        XCTAssertEqual(draft.animation.frames.map { $0.players[0].point }, positions)
        let before = draft
        XCTAssertThrowsError(try draft.renameSelectedPlayer("TOO LONG"))
        XCTAssertThrowsError(try draft.renameSelectedPlayer("\u{0001}"))
        XCTAssertEqual(draft, before)
        try draft.removeSelectedPlayer()
        XCTAssertEqual(draft.target, .ball)
        XCTAssertTrue(draft.animation.frames.allSatisfy { !$0.players.contains { $0.id == 1 } })
    }

    func testIncompleteCueAndCategoryStayEditableButCannotBeExported() throws {
        var draft = try draft()
        draft.cue = ""
        draft.category = ""
        try draft.move(to: FieldPoint(depth: 0.5, width: 0.5))
        XCTAssertThrowsError(try draft.animation.validate())
        draft.cue = "Wait for the runner."
        draft.category = "Combination"
        try draft.animation.validate()
    }

    func testPlayerLabelsCanBeReplacedWithoutLosingEditsAcrossPhases() throws {
        var draft = try draft()
        try draft.select(.player(1))
        try draft.editSelectedLabel("")
        XCTAssertThrowsError(try draft.animation.validate())
        try draft.move(to: FieldPoint(depth: 0.6, width: 0.4))
        try draft.editSelectedLabel("WIDE")
        XCTAssertTrue(draft.animation.frames.allSatisfy { $0.players[0].label == "WIDE" })
        try draft.animation.validate()
    }

    func testCustomizingResearchedPatternRetainsReferencesAndMarksAdaptation() throws {
        let source = try XCTUnwrap(AnimatedPlayLibrary.plays[0].animation)
        var draft = try AnimationDraft(source)
        XCTAssertEqual(draft.animation.origin, .coachAIOriginal)
        try draft.move(to: FieldPoint(depth: 0.45, width: 0.45))
        XCTAssertEqual(draft.animation.origin, .adapted)
        XCTAssertEqual(draft.animation.references, source.references)
        XCTAssertEqual(AnimatedPlayLibrary.plays[0].animation, source)
    }

    func testDraftValueCopiesCanRestoreWholeEditsForUndoAndRedo() throws {
        var draft = try draft()
        let undo = draft
        try draft.insertPhase()
        try draft.addPlayer(team: .away)
        try draft.move(to: FieldPoint(depth: 0.4, width: 0.9))
        let redo = draft
        draft = undo
        XCTAssertEqual(draft.animation.frames.count, 2)
        XCTAssertEqual(draft.frame.players.count, 8)
        draft = redo
        XCTAssertEqual(draft.animation.frames.count, 3)
        XCTAssertEqual(draft.frame.players.count, 9)
        XCTAssertEqual(draft.selectedPoint, FieldPoint(depth: 0.4, width: 0.9))
    }

    func testCustomPlayWithoutReferencesRoundTripsWithAuthorship() throws {
        var play = try starter()
        var draft = try AnimationDraft(XCTUnwrap(play.animation))
        try draft.selectPhase(1)
        try draft.select(.player(1))
        try draft.move(to: FieldPoint(depth: 0.7, width: 0.2))
        try draft.passToSelectedPlayer()
        play.animation = draft.animation
        play.created = Date(timeIntervalSince1970: 1_800_000_000)
        play.updated = play.created
        XCTAssertEqual(try PlayCodec.importDocument(PlayCodec.document(play)), play)
    }
}
