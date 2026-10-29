import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class WorkbenchTests: XCTestCase {
    private func play() -> SavedPlay {
        var play = SavedPlay.examples[0]
        play.title = "Shift and cover"
        play.notes = "Keep the middle connected."
        play.created = Date(timeIntervalSince1970: 1_800_000_000)
        play.updated = play.created
        play.board.routes = [[FieldPoint(depth: 0.1, width: 0.2), FieldPoint(depth: 0.6, width: 0.8)]]
        play.frames = [PlayFrame(board: play.board, duration: 2), PlayFrame(board: play.board, duration: 3)]
        return play
    }

    func testDocumentRoundTripPreservesAllEditableState() throws {
        let play = play()
        XCTAssertEqual(try PlayCodec.importDocument(PlayCodec.document(play)), play)
    }

    func testLibraryRoundTripAndEmptyLibrary() throws {
        let original = play()
        XCTAssertEqual(try PlayCodec.readLibrary(PlayCodec.library([original])), [original])
        XCTAssertEqual(try PlayCodec.readLibrary(PlayCodec.library([])), [])
    }

    func testAllExampleScenesAreValidAndHaveDistinctIDs() throws {
        XCTAssertEqual(Set(SavedPlay.examples.map(\.id)).count, FieldScenario.allCases.count)
        for play in SavedPlay.examples { try play.validate() }
    }

    func testUnknownVersionAndMalformedDataAreRejected() throws {
        let data = try PlayCodec.document(play())
        let changed = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 999")
        XCTAssertNotEqual(Data(changed.utf8), data)
        XCTAssertThrowsError(try PlayCodec.importDocument(Data(changed.utf8)))
        XCTAssertThrowsError(try PlayCodec.importDocument(Data("not JSON".utf8)))
        XCTAssertThrowsError(try PlayCodec.readLibrary(Data("{\"version\":999,\"plays\":[]}".utf8)))
    }

    func testImportRejectsUnknownRolesAndMissingRequiredFields() throws {
        let source = String(decoding: try PlayCodec.document(play()), as: UTF8.self)
        XCTAssertThrowsError(try PlayCodec.importDocument(Data(source.replacingOccurrences(of: "\"LB\"", with: "\"GK\"").utf8)))
        XCTAssertThrowsError(try PlayCodec.importDocument(Data("{\"version\":1,\"play\":{}}".utf8)))
    }

    func testImportAndLibraryHaveByteLimits() {
        XCTAssertThrowsError(try PlayCodec.importDocument(Data(repeating: 32, count: PlayCodec.maximumDocumentBytes + 1)))
        XCTAssertThrowsError(try PlayCodec.readLibrary(Data(repeating: 32, count: PlayCodec.maximumLibraryBytes + 1)))
    }

    func testOversizedOtherwiseValidExportIsRejected() {
        var play = play()
        play.board.routes = [Array(repeating: FieldPoint(depth: 0.5, width: 0.5), count: 20_000)]
        play.frames = (0..<4).map { _ in PlayFrame(board: play.board) }
        XCTAssertNoThrow(try play.validate())
        XCTAssertThrowsError(try PlayCodec.document(play))
    }

    func testTitleAndNotesLimitsAreEnforcedWithoutTruncation() throws {
        var play = play()
        play.title = String(repeating: "a", count: 80)
        play.notes = String(repeating: "b", count: 4_000)
        try play.validate()
        play.title += "a"
        XCTAssertThrowsError(try play.validate())
        play.title = " \n "
        XCTAssertThrowsError(try play.validate())
        play.title = "Valid"
        play.notes += "b"
        XCTAssertThrowsError(try play.validate())
    }

    func testUnsupportedTextAndDatesAreRejected() {
        var play = play()
        play.notes = "hidden\u{0001}control"
        XCTAssertThrowsError(try play.validate())
        play.notes = "Valid"
        play.created = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try play.validate())
    }

    func testMissingAndDuplicatePlayersAreRejected() {
        var play = play()
        let original = play.board.scene
        play.board.scene = TacticalScene(ball: original.ball, formation: original.formation,
                                         teammates: Array(original.teammates.dropLast()), opponents: original.opponents)
        XCTAssertThrowsError(try play.validate())
        play.board.scene = TacticalScene(ball: original.ball, formation: original.formation,
                                         teammates: Array(repeating: original.teammates[0], count: 5), opponents: original.opponents)
        XCTAssertThrowsError(try play.validate())
        play.board.scene = TacticalScene(ball: original.ball, formation: original.formation,
                                         teammates: original.teammates, opponents: [])
        XCTAssertThrowsError(try play.validate())
    }

    func testUnboundedOrNonfiniteCoordinatesAreRejectedNotRepaired() {
        var play = play()
        for point in [FieldPoint(depth: -0.01, width: 0.5), FieldPoint(depth: 0.5, width: 1.01),
                      FieldPoint(depth: .nan, width: 0.5), FieldPoint(depth: 0.5, width: .infinity)] {
            let original = play.board.scene
            play.board.scene = TacticalScene(ball: point, formation: original.formation, teammates: original.teammates, opponents: original.opponents)
            XCTAssertThrowsError(try play.validate())
        }
    }

    func testComparisonRequiresDifferentRolesOnlyWhenVisible() throws {
        var play = play()
        play.board.comparison = play.board.position
        play.board.comparing = false
        try play.validate()
        play.board.comparing = true
        XCTAssertThrowsError(try play.validate())
    }

    func testSequenceCountIDsAndDurationLimits() throws {
        var play = play()
        play.frames = (0..<24).map { _ in PlayFrame(board: play.board, duration: 10) }
        try play.validate()
        play.frames.append(PlayFrame(board: play.board))
        XCTAssertThrowsError(try play.validate())
        play.frames = [play.frames[0], play.frames[0]]
        XCTAssertThrowsError(try play.validate())
        for duration in [0.99, 10.01, .nan, .infinity] {
            play.frames = [PlayFrame(board: play.board, duration: duration)]
            XCTAssertThrowsError(try play.validate())
        }
    }

    func testLibraryCountAndIdentityLimits() throws {
        let play = play()
        XCTAssertThrowsError(try PlayCodec.library([play, play]))
        let plays = (0..<101).map { _ in var copy = play; copy.id = UUID(); return copy }
        XCTAssertThrowsError(try PlayCodec.library(plays))
        XCTAssertNoThrow(try PlayCodec.library(Array(plays.prefix(100))))
    }

    func testRouteLimitsAndInvalidValues() throws {
        let point = FieldPoint(depth: 0.5, width: 0.5)
        XCTAssertNoThrow(try RouteDrawing.validateSavedRoutes([Array(repeating: point, count: 20_000)]))
        XCTAssertThrowsError(try RouteDrawing.validateSavedRoutes([Array(repeating: point, count: 20_001)]))
        XCTAssertThrowsError(try RouteDrawing.validateSavedRoutes(Array(repeating: [point, point], count: 101)))
        XCTAssertThrowsError(try RouteDrawing.validateSavedRoutes([[point]]))
        XCTAssertThrowsError(try RouteDrawing.validateSavedRoutes([[point, FieldPoint(depth: .nan, width: 0.5)]]))
    }

    func testRestoringRoutesClearsRedoAndPreservesExistingStateOnInvalidRestore() throws {
        var drawing = RouteDrawing()
        let routes = play().board.routes
        try drawing.restore(routes)
        drawing.undo()
        XCTAssertTrue(drawing.canRedo)
        try drawing.restore(routes)
        XCTAssertEqual(drawing.routes, routes)
        XCTAssertFalse(drawing.canRedo)
        XCTAssertThrowsError(try drawing.restore([[FieldPoint(depth: 2, width: 2)]]))
        XCTAssertEqual(drawing.routes, routes)
    }

    func testPracticeRequiresGuessAndFreezesAfterReveal() throws {
        var round = PracticeRound(ball: TacticalScene.initialBall, role: .lb)
        XCTAssertThrowsError(try round.reveal())
        XCTAssertNil(round.guess)
        round.place(round.target.point)
        try round.reveal()
        XCTAssertTrue(round.revealed)
        XCTAssertTrue(round.insideZone)
        let previous = round.guess
        round.place(FieldPoint(depth: 1, width: 1))
        XCTAssertEqual(round.guess, previous)
    }

    func testPracticeDistanceUsesRealMetresForBothAxes() throws {
        var round = PracticeRound(ball: TacticalScene.initialBall, role: .cdm)
        round.place(FieldPoint(depth: round.target.point.depth + 3 / 105, width: round.target.point.width + 4 / 68))
        XCTAssertEqual(try XCTUnwrap(round.distanceMeters), 5, accuracy: 0.00001)
        XCTAssertTrue(round.insideZone)
        round.place(FieldPoint(depth: round.target.point.depth + 9 / 105, width: round.target.point.width))
        XCTAssertFalse(round.insideZone)
    }

    func testPracticeZoneBoundary() {
        var round = PracticeRound(ball: TacticalScene.initialBall, role: .cdm)
        round.place(FieldPoint(depth: round.target.point.depth, width: round.target.point.width + 7.999 / 68))
        XCTAssertTrue(round.insideZone)
        round.place(FieldPoint(depth: round.target.point.depth, width: round.target.point.width + 8 / 68))
        XCTAssertTrue(round.insideZone)
        round.place(FieldPoint(depth: round.target.point.depth, width: round.target.point.width + 8.001 / 68))
        XCTAssertFalse(round.insideZone)
    }

    func testSequenceTimelineBoundariesAndLastFrame() throws {
        let frames = play().frames + [PlayFrame(board: play().board, duration: 7)]
        XCTAssertEqual(PlaySequence.duration(frames), 5)
        XCTAssertEqual(try PlaySequence.index(at: -1, frames: frames), 0)
        XCTAssertEqual(try PlaySequence.index(at: 1.999, frames: frames), 0)
        XCTAssertEqual(try PlaySequence.index(at: 2, frames: frames), 1)
        XCTAssertEqual(try PlaySequence.index(at: 5, frames: frames), 2)
        XCTAssertEqual(try PlaySequence.index(at: 500, frames: frames), 2)
        XCTAssertNil(try PlaySequence.index(at: 0, frames: []))
        XCTAssertEqual(PlaySequence.duration([]), 0)
        XCTAssertEqual(PlaySequence.duration([frames[0]]), 0)
    }

    func testSequenceRejectsInvalidTimeAndAnyInvalidFrame() {
        XCTAssertThrowsError(try PlaySequence.index(at: .nan, frames: []))
        XCTAssertThrowsError(try PlaySequence.index(at: .infinity, frames: play().frames))
        var frames = play().frames
        frames[1].duration = .nan
        XCTAssertThrowsError(try PlaySequence.index(at: 0, frames: frames))
    }

    func testDiagramIsValidEscapedSelfContainedXMLWithFullMarkingsAndArrow() throws {
        var play = play()
        play.title = "<script> & \"quoted\""
        play.notes = "Use < & > safely.\nNo external resources."
        let data = try PlayDiagram.svg(play)
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "SVG XML did not parse")
        let svg = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(svg.contains("&lt;script&gt; &amp; &quot;quoted&quot;"))
        XCTAssertFalse(svg.contains("<script>"))
        XCTAssertFalse(svg.contains("<foreignObject"))
        XCTAssertFalse(svg.contains("xlink:href"))
        XCTAssertEqual(svg.components(separatedBy: "data-mark=\"penalty-spot\"").count - 1, 2)
        XCTAssertEqual(svg.components(separatedBy: "data-mark=\"goal\"").count - 1, 2)
        XCTAssertEqual(svg.components(separatedBy: "data-mark=\"route-arrow\"").count - 1, 1)
        XCTAssertTrue(svg.contains("105 x 68 m"))
    }

    func testDiagramLabelsNotesExcerptAndFilenameCannotEscapeDirectory() throws {
        var play = play()
        play.notes = String(repeating: "x", count: 241)
        let svg = String(decoding: try PlayDiagram.svg(play), as: UTF8.self)
        XCTAssertTrue(svg.contains("excerpt; full notes in play file"))
        let filename = PlayCodec.filename("../\\bad:play?*\n")
        for character in ["/", "\\", ":", "?", "*", "\n", "."] { XCTAssertFalse(filename.contains(character)) }
        XCTAssertEqual(PlayCodec.filename("   "), "CoachAI Play")
    }

    @MainActor func testRepositoryAtomicSaveLoadImportAndRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachAI-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let url = directory.appendingPathComponent("playbook.json")
        let repository = PlaybookRepository(url: url)
        let initially = try await repository.load()
        XCTAssertEqual(initially, [])
        let original = play()
        try await repository.save([original])
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, [original])
        let source = directory.appendingPathComponent("shared.json")
        try PlayCodec.document(original).write(to: source)
        let imported = try await repository.importPlay(at: source)
        XCTAssertEqual(imported, original)
        let bytes = try Data(contentsOf: url)
        do {
            var invalid = original
            invalid.title = ""
            try await repository.save([invalid])
            XCTFail("Invalid save should fail")
        } catch { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        try await repository.resetWithRecoveryCopy()
        let empty = try await repository.load()
        XCTAssertEqual(empty, [])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let recovery = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("playbook-recovery-") })
        XCTAssertEqual(try Data(contentsOf: recovery), bytes)
    }

    @MainActor func testCorruptLibraryIsNotTreatedAsEmptyOrOverwrittenOnRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachAI-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let url = directory.appendingPathComponent("playbook.json")
        let corrupt = Data("damaged library".utf8)
        try corrupt.write(to: url)
        let repository = PlaybookRepository(url: url)
        do { _ = try await repository.load(); XCTFail("Corrupt storage must fail explicitly") }
        catch { XCTAssertEqual(try Data(contentsOf: url), corrupt) }
        try await repository.resetWithRecoveryCopy()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let recovery = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("playbook-recovery-") })
        XCTAssertEqual(try Data(contentsOf: recovery), corrupt)
    }

    @MainActor func testRepositoryBoundsReadsBeforeDecoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachAI-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let url = directory.appendingPathComponent("too-large.json")
        try Data(repeating: 32, count: PlayCodec.maximumDocumentBytes + 1).write(to: url)
        let repository = PlaybookRepository(url: directory.appendingPathComponent("library.json"))
        do { _ = try await repository.importPlay(at: url); XCTFail("Oversized file must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("too large")) }
    }
}
