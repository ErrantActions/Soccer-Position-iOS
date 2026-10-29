import Foundation
import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class TacticalAnimationTests: XCTestCase {
    private func play() -> SavedPlay {
        var play = AnimatedPlayLibrary.plays[0]
        play.created = Date(timeIntervalSince1970: 1_800_000_000)
        play.updated = play.created
        return play
    }

    private func clip() throws -> TacticalAnimation { try XCTUnwrap(play().animation) }

    func testSixOriginalPatternsHaveVerifiedReferencesAndValidData() throws {
        XCTAssertEqual(AnimatedPlayLibrary.plays.count, 6)
        XCTAssertEqual(Set(AnimatedPlayLibrary.plays.map(\.title)).count, 6)
        XCTAssertEqual(Set(AnimatedPlayLibrary.plays.map(\.id)).count, 6)
        for play in AnimatedPlayLibrary.plays {
            try play.validate()
            let clip = try XCTUnwrap(play.animation)
            XCTAssertFalse(clip.references.isEmpty)
            XCTAssertTrue(clip.references.allSatisfy { $0.url.host == "learning.coachesvoice.com" })
            XCTAssertTrue(play.notes.contains("Original CoachAI"))
        }
    }

    func testAllInterpolatedFramesStayFiniteAndInsideThePitch() throws {
        for play in AnimatedPlayLibrary.plays {
            let clip = try XCTUnwrap(play.animation)
            for step in 0...100 {
                let frame = try clip.sample(at: clip.duration * Double(step) / 100)
                XCTAssertTrue(frame.ball.isInsideField)
                XCTAssertTrue(frame.players.allSatisfy { $0.point.isInsideField })
            }
        }
    }

    func testBallAndPlayersReallyMoveBetweenKeyframes() throws {
        let clip = try clip()
        let first = clip.frames[0]
        let second = clip.frames[1]
        let halfway = try clip.sample(at: second.time / 2)
        XCTAssertEqual(halfway.ball.depth, (first.ball.depth + second.ball.depth) / 2, accuracy: 1e-10)
        XCTAssertEqual(halfway.ball.width, (first.ball.width + second.ball.width) / 2, accuracy: 1e-10)
        XCTAssertNotEqual(halfway.ball, first.ball)
        XCTAssertNotEqual(halfway.ball, second.ball)
        XCTAssertNotEqual(halfway.players, first.players)
        XCTAssertNotEqual(halfway.players, second.players)
        XCTAssertEqual(halfway.cue, first.cue)
    }

    func testInterpolationMatchesPlayersByIdentityNotArrayOrder() throws {
        var clip = try clip()
        let expected = try clip.sample(at: 1)
        clip.frames[1].players.reverse()
        XCTAssertEqual(try clip.sample(at: 1), expected)
    }

    func testEndpointsAndOutOfRangeFiniteTimes() throws {
        let clip = try clip()
        XCTAssertEqual(try clip.sample(at: -50), clip.frames[0])
        XCTAssertEqual(try clip.sample(at: 0), clip.frames[0])
        XCTAssertEqual(try clip.sample(at: clip.duration), clip.frames.last)
        XCTAssertEqual(try clip.sample(at: 1_000), clip.frames.last)
        XCTAssertEqual(try clip.sample(at: clip.frames[1].time), clip.frames[1])
    }

    func testReducedMotionAdvancesByDecisionStepsNotContinuousMovement() throws {
        let clip = try clip()
        XCTAssertEqual(try clip.sample(at: 1, reducedMotion: true), clip.frames[0])
        XCTAssertEqual(try clip.sample(at: clip.frames[1].time, reducedMotion: true), clip.frames[1])
        XCTAssertEqual(try clip.sample(at: clip.duration, reducedMotion: true), clip.frames.last)
    }

    func testInvalidSampleTimesAreRejected() throws {
        let clip = try clip()
        XCTAssertThrowsError(try clip.sample(at: .nan))
        XCTAssertThrowsError(try clip.sample(at: .infinity))
    }

    func testFrameCountAndStartingTimeLimits() throws {
        var clip = try clip()
        clip.frames = []
        XCTAssertThrowsError(try clip.sample(at: 0))
        clip = try self.clip()
        clip.frames = [clip.frames[0]]
        XCTAssertThrowsError(try clip.validate())
        clip = try self.clip()
        clip.frames[0].time = 0.1
        XCTAssertThrowsError(try clip.validate())
        clip = try self.clip()
        let frame = clip.frames[0]
        clip.frames = (0..<25).map { var copy = frame; copy.time = Double($0); return copy }
        XCTAssertThrowsError(try clip.validate())
    }

    func testTimesMustBeFiniteIncreasingAndBounded() throws {
        for time in [-1.0, 0, 0.1, .nan, .infinity] {
            var clip = try clip()
            clip.frames[1].time = time
            XCTAssertThrowsError(try clip.validate())
        }
        var clip = try clip()
        clip.frames[clip.frames.count - 1].time = 120.01
        XCTAssertThrowsError(try clip.validate())
    }

    func testDurationAndCountExactUpperBoundsAreAccepted() throws {
        var clip = try clip()
        let frame = clip.frames[0]
        clip.frames = (0..<24).map { var copy = frame; copy.time = 120 * Double($0) / 23; return copy }
        XCTAssertNoThrow(try clip.validate())
    }

    func testDuplicateOrMissingPlayersAreRejected() throws {
        var clip = try clip()
        clip.frames[0].players[1] = clip.frames[0].players[0]
        XCTAssertThrowsError(try clip.validate())
        clip = try self.clip()
        clip.frames[1].players.removeLast()
        XCTAssertThrowsError(try clip.validate())
    }

    func testPlayerTeamAndLabelCannotChangeBetweenFrames() throws {
        var clip = try clip()
        let original = clip.frames[1].players[0]
        clip.frames[1].players[0] = AnimationPlayer(id: original.id, label: original.label, team: .away, point: original.point)
        XCTAssertThrowsError(try clip.validate())
        clip.frames[1].players[0] = AnimationPlayer(id: original.id, label: "NEW", team: original.team, point: original.point)
        XCTAssertThrowsError(try clip.validate())
    }

    func testSupportsUpToTwentyTwoPlayersButNotTwentyThree() throws {
        var clip = try clip()
        for index in clip.frames.indices {
            clip.frames[index].players = (1...22).map {
                AnimationPlayer(id: $0, label: String($0), team: $0 <= 11 ? .home : .away, point: FieldPoint(depth: 0.5, width: 0.5))
            }
        }
        XCTAssertNoThrow(try clip.validate())
        for index in clip.frames.indices {
            clip.frames[index].players.append(AnimationPlayer(id: 23, label: "23", team: .away, point: FieldPoint(depth: 0.5, width: 0.5)))
        }
        XCTAssertThrowsError(try clip.validate())
    }

    func testInvalidBallAndPlayerCoordinatesAreRejectedNotClamped() throws {
        var clip = try clip()
        clip.frames[1].ball.width = 1.01
        XCTAssertThrowsError(try clip.validate())
        clip = try self.clip()
        clip.frames[1].players[0].point.depth = .nan
        XCTAssertThrowsError(try clip.validate())
    }

    func testCuesAndLabelsAreBoundedAndXMLSafe() throws {
        var clip = try clip()
        clip.frames[0].cue = ""
        XCTAssertThrowsError(try clip.validate())
        clip.frames[0].cue = String(repeating: "a", count: 401)
        XCTAssertThrowsError(try clip.validate())
        clip.frames[0].cue = "Invalid\u{0001}cue"
        XCTAssertThrowsError(try clip.validate())
        clip = try self.clip()
        let original = clip.frames[0].players[0]
        clip.frames[0].players[0] = AnimationPlayer(id: original.id, label: "TOO LONG", team: original.team, point: original.point)
        XCTAssertThrowsError(try clip.validate())
    }

    func testReferencesRequireHTTPSWithoutCredentials() throws {
        for address in ["http://example.org", "javascript:alert(1)", "https://user:password@example.org"] {
            var clip = try clip()
            clip.references[0].url = try XCTUnwrap(URL(string: address))
            XCTAssertThrowsError(try clip.validate())
        }
        var clip = try clip()
        clip.references = []
        XCTAssertThrowsError(try clip.validate())
    }

    func testAnimatedDocumentAndMixedLibraryRoundTrip() throws {
        let play = play()
        let data = try PlayCodec.document(play)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 2)
        XCTAssertEqual(try PlayCodec.importDocument(data), play)
        var legacy = SavedPlay.examples[0]
        legacy.created = play.created
        legacy.updated = play.updated
        XCTAssertEqual(try PlayCodec.readLibrary(PlayCodec.library([legacy, play])), [legacy, play])
    }

    func testLegacyFilesRemainVersionOneAndDoNotAcquireAnAnimation() throws {
        var legacy = play()
        legacy.animation = nil
        let data = try PlayCodec.document(legacy)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertNil(try PlayCodec.importDocument(data).animation)
    }

    func testAnimationCannotBeSmuggledIntoVersionOne() throws {
        let data = try PlayCodec.document(play())
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        envelope["version"] = 1
        XCTAssertThrowsError(try PlayCodec.importDocument(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testCannotCombineTwoDifferentSequenceFormats() {
        var play = play()
        play.frames = [PlayFrame(board: play.board)]
        XCTAssertThrowsError(try play.validate())
    }

    func testAnimatedSVGShowsOpeningPlayersAndEscapesLabels() throws {
        var play = play()
        var clip = try XCTUnwrap(play.animation)
        let original = clip.frames[0].players[0]
        for index in clip.frames.indices {
            clip.frames[index].players[0] = AnimationPlayer(id: original.id, label: "2<&", team: original.team,
                                                          point: clip.frames[index].players[0].point)
        }
        play.animation = clip
        let data = try PlayDiagram.svg(play)
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "SVG XML did not parse")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("animation opening frame - static diagram"))
        XCTAssertTrue(text.contains("2&lt;&amp;"))
        XCTAssertFalse(text.contains(">LB</text>"))
    }

    func testDefensiveSlideMovesTheUnitRatherThanOnlyTheBall() throws {
        let clip = try XCTUnwrap(AnimatedPlayLibrary.plays.last?.animation)
        let first = clip.frames[0]
        let last = try XCTUnwrap(clip.frames.last)
        XCTAssertGreaterThan(last.ball.width, first.ball.width)
        for player in first.players where player.team == .home {
            let destination = try XCTUnwrap(last.players.first { $0.id == player.id })
            XCTAssertGreaterThan(destination.point.width, player.point.width)
        }
    }
}
