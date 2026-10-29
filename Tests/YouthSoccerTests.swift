import CoreGraphics
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

final class YouthSoccerTests: XCTestCase {
    private func setup(_ format: TeamFormat = .seven) -> TeamSetup {
        TeamSetup(format: format, formation: format.formations[0])
    }

    func testEveryOfferedFormationHasTheCorrectFullTeamIncludingKeeper() throws {
        for format in TeamFormat.allCases {
            for formation in format.formations {
                let setup = TeamSetup(format: format, formation: formation)
                try setup.validate()
                let players = try setup.players()
                XCTAssertEqual(players.count, format.playersPerTeam * 2)
                XCTAssertEqual(Set(players.map(\.id)).count, players.count)
                for team in [AnimationTeam.home, .away] {
                    let roster = players.filter { $0.team == team }
                    XCTAssertEqual(roster.count, format.playersPerTeam)
                    XCTAssertEqual(roster.filter { $0.role == .goalkeeper }.count, format.hasGoalkeeper ? 1 : 0)
                    XCTAssertEqual(roster.filter { $0.role == .outfield }.count, formation.lines.reduce(0, +))
                }
                XCTAssertTrue(players.allSatisfy { $0.point.isInsideField })
                try setup.animation().validate()
            }
        }
    }

    func testInvalidFormatFormationCombinationFailsBeforeCreatingPlayers() {
        let invalid = TeamSetup(format: .three, formation: .fourThreeThree)
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertThrowsError(try invalid.players())
        XCTAssertThrowsError(try invalid.animation())
    }

    func testNoGoalkeepersInThreeOrFourAsideAndMirroredSides() throws {
        for format in [TeamFormat.three, .four] {
            let players = try setup(format).players()
            XCTAssertFalse(players.contains { $0.role == .goalkeeper })
            for home in players where home.team == .home {
                let away = try XCTUnwrap(players.first { $0.id == home.id + 100 })
                XCTAssertEqual(home.point.depth + away.point.depth, 1, accuracy: 1e-10)
                XCTAssertEqual(home.point.width + away.point.width, 1, accuracy: 1e-10)
            }
        }
    }

    func testFormatsUseVerifiedReferenceSizesAndSmallerGoals() {
        XCTAssertEqual(TeamFormat.three.fieldLength, 15)
        XCTAssertEqual(TeamFormat.three.fieldWidth, 10)
        XCTAssertEqual(TeamFormat.five.fieldLength, 37)
        XCTAssertEqual(TeamFormat.five.fieldWidth, 27)
        XCTAssertEqual(TeamFormat.seven.fieldLength, 55)
        XCTAssertEqual(TeamFormat.seven.fieldWidth, 37)
        XCTAssertEqual(TeamFormat.nine.fieldLength, 73)
        XCTAssertEqual(TeamFormat.nine.fieldWidth, 46)
        for format in TeamFormat.allCases {
            XCTAssertGreaterThan(format.goalWidth, 0)
            XCTAssertLessThan(format.goalWidth, format.fieldWidth)
            XCTAssertFalse(format.references.isEmpty)
            XCTAssertTrue(format.references.allSatisfy { $0.url.scheme == "https" })
        }
    }

    func testEveryFormatKeepsRealAspectAndUniformMetreScaleInEitherOrientation() {
        for format in TeamFormat.allCases {
            for horizontal in [false, true] {
                let projection = PitchProjection(size: CGSize(width: 720, height: 480), horizontal: horizontal, format: format)
                let ratio = horizontal ? format.fieldLength / format.fieldWidth : format.fieldWidth / format.fieldLength
                XCTAssertEqual(projection.bounds.width / projection.bounds.height, ratio, accuracy: 1e-9)
                let first = projection.meterLocation(depth: 2, width: 2)
                let depth = projection.meterLocation(depth: 3, width: 2)
                let width = projection.meterLocation(depth: 2, width: 3)
                XCTAssertEqual(hypot(first.x - depth.x, first.y - depth.y), projection.metersToPoints, accuracy: 1e-9)
                XCTAssertEqual(hypot(first.x - width.x, first.y - width.y), projection.metersToPoints, accuracy: 1e-9)
                let point = FieldPoint(depth: 0.63, width: 0.27)
                let roundTrip = projection.fieldPoint(projection.location(point))
                XCTAssertEqual(roundTrip.depth, point.depth, accuracy: 1e-9)
                XCTAssertEqual(roundTrip.width, point.width, accuracy: 1e-9)
            }
        }
    }

    func testLegacyProjectionAndFullSizeMarkingsStayUnchanged() {
        let legacy = PitchProjection(size: CGSize(width: 400, height: 600), horizontal: false)
        let eleven = PitchProjection(size: CGSize(width: 400, height: 600), horizontal: false, format: .eleven)
        XCTAssertEqual(legacy.bounds, eleven.bounds)
        XCTAssertEqual(legacy.fieldLength, 105)
        XCTAssertEqual(legacy.fieldWidth, 68)
        XCTAssertTrue(legacy.fullSizeMarkings)
        XCTAssertFalse(PitchProjection(size: CGSize(width: 400, height: 600), horizontal: false, format: .five).fullSizeMarkings)
    }

    func testApplyingLayoutResetsAllPhasesAndCanBeUndoneByRestoringValue() throws {
        var draft = try AnimationDraft(XCTUnwrap(AnimatedPlayLibrary.plays[0].animation))
        let before = draft
        try draft.applyTeamSetup(setup(.four))
        XCTAssertEqual(draft.phase, 0)
        XCTAssertEqual(draft.target, .ball)
        XCTAssertEqual(draft.animation.frames.count, 2)
        XCTAssertEqual(draft.frame.players.count, 8)
        XCTAssertEqual(draft.animation.teamSetup?.format, .four)
        XCTAssertEqual(draft.animation.origin, .adapted)
        try draft.animation.validate()
        draft = before
        XCTAssertEqual(draft, before)
    }

    func testPerTeamLimitsSupportSmallerUnevenTrainingGroups() throws {
        var draft = try AnimationDraft(setup(.three).animation())
        XCTAssertFalse(draft.canAddPlayer(team: .home))
        XCTAssertThrowsError(try draft.addPlayer(team: .home))
        let removed = try XCTUnwrap(draft.frame.players.first { $0.team == .home })
        try draft.select(.player(removed.id))
        try draft.removeSelectedPlayer()
        XCTAssertTrue(draft.canAddPlayer(team: .home))
        XCTAssertFalse(draft.canAddPlayer(team: .away))
        try draft.animation.validate()
        try draft.addPlayer(team: .home)
        XCTAssertFalse(draft.canAddPlayer(team: .home))
    }

    func testRosterOverLimitAndDuplicateOrForbiddenKeeperAreRejected() throws {
        var animation = try setup(.three).animation()
        for index in animation.frames.indices {
            animation.frames[index].players.append(AnimationPlayer(id: 99, label: "9", team: .home,
                                                                   point: FieldPoint(depth: 0.2, width: 0.5)))
        }
        XCTAssertThrowsError(try animation.validate())
        animation = try setup(.three).animation()
        for index in animation.frames.indices { animation.frames[index].players[0].role = .goalkeeper }
        XCTAssertThrowsError(try animation.validate())
        animation = try setup().animation()
        for index in animation.frames.indices { animation.frames[index].players[1].role = .goalkeeper }
        XCTAssertThrowsError(try animation.validate())
    }

    func testGoalkeeperRoleAndLabelsStayConsistentAcrossAllPhases() throws {
        var draft = try AnimationDraft(setup().animation())
        try draft.select(.player(1))
        try draft.renameSelectedPlayer("KEEP")
        XCTAssertTrue(draft.animation.frames.allSatisfy { $0.players[0].role == .goalkeeper })
        try draft.select(.player(2))
        XCTAssertThrowsError(try draft.setSelectedRole(.goalkeeper))
        try draft.select(.player(1))
        try draft.setSelectedRole(.outfield)
        try draft.select(.player(2))
        try draft.setSelectedRole(.goalkeeper)
        try draft.animation.validate()
        var invalid = draft.animation
        invalid.frames[1].players[1].role = .outfield
        XCTAssertThrowsError(try invalid.validate())
    }

    func testDetachKeepsTheDraftButRestoresFreeformLimits() throws {
        var draft = try AnimationDraft(setup(.four).animation())
        let frames = draft.animation.frames
        draft.detachTeamSetup()
        XCTAssertNil(draft.animation.teamSetup)
        XCTAssertEqual(draft.animation.frames, frames)
        XCTAssertTrue(draft.canAddPlayer(team: .home))
        try draft.animation.validate()
    }

    func testNewYouthPlayUsesSchemaThreeAndPreservesAllMetadata() throws {
        var play = try setup().newPlay(board: SavedPlay.examples[0].board)
        play.created = Date(timeIntervalSince1970: 1_800_000_000)
        play.updated = play.created
        let data = try PlayCodec.document(play)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 3)
        XCTAssertEqual(try PlayCodec.importDocument(data), play)
        envelope["version"] = 2
        XCTAssertThrowsError(try PlayCodec.importDocument(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testMixedLibraryRoundTripAndLegacyAnimationsNeedNoYouthMetadata() throws {
        var youth = try setup(.five).newPlay(board: SavedPlay.examples[0].board)
        youth.created = Date(timeIntervalSince1970: 1_800_000_000)
        youth.updated = youth.created
        var legacy = AnimatedPlayLibrary.plays[0]
        legacy.created = youth.created
        legacy.updated = youth.updated
        XCTAssertNil(legacy.animation?.teamSetup)
        XCTAssertFalse(try XCTUnwrap(legacy.animation).needsYouthSchema)
        let data = try PlayCodec.library([youth, legacy])
        XCTAssertEqual(try PlayCodec.readLibrary(data), [youth, legacy])
    }

    func testYouthSVGUsesSmallPitchAndDoesNotInventAdultBoxes() throws {
        for format in [TeamFormat.three, .four, .five, .seven, .nine] {
            let play = try setup(format).newPlay(board: SavedPlay.examples[0].board)
            let data = try PlayDiagram.svg(play)
            let parser = XMLParser(data: data)
            XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "Invalid youth SVG")
            let svg = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(svg.contains("\(Int(format.fieldLength)) x \(Int(format.fieldWidth)) m reference"))
            XCTAssertFalse(svg.contains("105 x 68"))
            XCTAssertFalse(svg.contains("data-mark=\"penalty-spot\""))
            XCTAssertEqual(svg.components(separatedBy: "data-mark=\"goalkeeper\"").count - 1, format.hasGoalkeeper ? 2 : 0)
        }
    }
}
