import Foundation

enum WorkbenchError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

struct BoardSnapshot: Codable, Equatable, Sendable {
    var scene: TacticalScene
    var position: Position
    var comparison: Position
    var comparing: Bool
    var showHeat: Bool
    var showGuides: Bool
    var routes: [[FieldPoint]]

    func validate() throws {
        let issues = AIPositionValidation.inputIssues(scene)
        guard issues.isEmpty else { throw WorkbenchError.invalid(issues.joined(separator: " ")) }
        guard !comparing || position != comparison else {
            throw WorkbenchError.invalid("Choose different roles for comparison.")
        }
        try RouteDrawing.validateSavedRoutes(routes)
    }
}

struct PlayFrame: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var board: BoardSnapshot
    var duration: Double = 2
}

struct SavedPlay: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var favorite = false
    var created = Date()
    var updated = Date()
    var board: BoardSnapshot
    var frames: [PlayFrame] = []

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80 else {
            throw WorkbenchError.invalid("Use a play title between 1 and 80 characters.")
        }
        guard notes.count <= 4_000 else { throw WorkbenchError.invalid("Keep coaching notes under 4,000 characters.") }
        let validDates = -62_135_596_800.0...253_402_300_799.0
        guard validDates.contains(created.timeIntervalSince1970), validDates.contains(updated.timeIntervalSince1970) else {
            throw WorkbenchError.invalid("The play has an unsupported date.")
        }
        guard (title + notes).unicodeScalars.allSatisfy({ scalar in
            let value = scalar.value
            return value == 9 || value == 10 || value == 13 ||
                (value >= 0x20 && value <= 0xD7FF) || (value >= 0xE000 && value <= 0xFFFD) || value >= 0x10000
        }) else { throw WorkbenchError.invalid("The play text contains unsupported control characters.") }
        try board.validate()
        guard frames.count <= 24, Set(frames.map(\.id)).count == frames.count else {
            throw WorkbenchError.invalid("A sequence supports up to 24 uniquely identified steps.")
        }
        for frame in frames {
            try frame.board.validate()
            guard frame.duration.isFinite, (1...10).contains(frame.duration) else {
                throw WorkbenchError.invalid("Each sequence step must last 1 to 10 seconds.")
            }
        }
    }

    static let examples: [SavedPlay] = FieldScenario.allCases.map { scenario in
        let team = Position.allCases.map { PlayerPlacement(role: $0, point: Positioning.recommend(ball: scenario.point, position: $0).point) }
        let scene = TacticalScene(ball: scenario.point, formation: .fourThreeThree, teammates: team, opponents: TacticalScene.defaultOpponents)
        return SavedPlay(
            title: scenario.rawValue, notes: "Example setup. Adjust the scene and review decisions with your coach.",
            board: BoardSnapshot(scene: scene, position: .lb, comparison: .lcb, comparing: false, showHeat: true, showGuides: true, routes: [])
        )
    }
}

enum PlayCodec {
    static let maximumDocumentBytes = 2_000_000
    static let maximumLibraryBytes = 20_000_000
    private struct Document: Codable {
        let version: Int
        let play: SavedPlay
    }
    private struct Library: Codable {
        let version: Int
        let plays: [SavedPlay]
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    static func document(_ play: SavedPlay) throws -> Data {
        try play.validate()
        let data = try encoder().encode(Document(version: 1, play: play))
        guard data.count <= maximumDocumentBytes else {
            throw WorkbenchError.invalid("This play is larger than the 2 MB share/import limit. Reduce its steps or routes.")
        }
        return data
    }
    static func importDocument(_ data: Data) throws -> SavedPlay {
        guard data.count <= maximumDocumentBytes else { throw WorkbenchError.invalid("The play file exceeds 2 MB.") }
        let document = try decoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw WorkbenchError.invalid("This play file uses an unsupported version.") }
        try document.play.validate()
        return document.play
    }
    static func library(_ plays: [SavedPlay]) throws -> Data {
        guard plays.count <= 100, Set(plays.map(\.id)).count == plays.count else {
            throw WorkbenchError.invalid("The local playbook supports up to 100 uniquely identified plays.")
        }
        for play in plays { _ = try document(play) }
        let data = try encoder().encode(Library(version: 1, plays: plays))
        guard data.count <= maximumLibraryBytes else { throw WorkbenchError.invalid("The local playbook exceeds 20 MB.") }
        return data
    }
    static func readLibrary(_ data: Data) throws -> [SavedPlay] {
        guard data.count <= maximumLibraryBytes else { throw WorkbenchError.invalid("The local playbook exceeds 20 MB.") }
        let library = try decoder().decode(Library.self, from: data)
        guard library.version == 1 else { throw WorkbenchError.invalid("The playbook uses an unsupported version.") }
        _ = try self.library(library.plays)
        return library.plays
    }
    static func filename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "CoachAI Play" : String(cleaned.prefix(80))
    }
}

actor PlaybookRepository {
    let url: URL
    init(url: URL) { self.url = url }

    func load() throws -> [SavedPlay] {
        do {
            return try PlayCodec.readLibrary(Self.readBounded(url, limit: PlayCodec.maximumLibraryBytes))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }
    func save(_ plays: [SavedPlay]) throws {
        let data = try PlayCodec.library(plays)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    func importPlay(at source: URL) throws -> SavedPlay {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        return try PlayCodec.importDocument(Self.readBounded(source, limit: PlayCodec.maximumDocumentBytes))
    }
    func resetWithRecoveryCopy() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let recovery = url.deletingLastPathComponent().appendingPathComponent("playbook-recovery-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: recovery)
        }
        try save([])
    }
    private static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        let data: Data
        do {
            var contents = Data()
            while contents.count <= limit {
                guard let chunk = try file.read(upToCount: min(65_536, limit + 1 - contents.count)), !chunk.isEmpty else { break }
                contents.append(chunk)
            }
            data = contents
        } catch {
            let readError = error
            do { try file.close() } catch {
                throw WorkbenchError.invalid("The play file could not be read or closed.")
            }
            throw readError
        }
        try file.close()
        guard data.count <= limit else { throw WorkbenchError.invalid("The selected play file is too large.") }
        return data
    }
}

struct PracticeRound: Equatable {
    let ball: FieldPoint
    let role: Position
    let target: Recommendation
    private(set) var guess: FieldPoint?
    private(set) var revealed = false
    let radiusMeters: Double = 8

    init(ball: FieldPoint, role: Position) {
        self.ball = ball
        self.role = role
        target = Positioning.recommend(ball: ball, position: role)
    }
    mutating func place(_ point: FieldPoint) {
        guard !revealed else { return }
        guess = point.bounded
    }
    mutating func reveal() throws {
        guard guess != nil else { throw WorkbenchError.invalid("Place your player on the pitch first.") }
        revealed = true
    }
    var distanceMeters: Double? {
        guess.map {
            let depth = ($0.depth - target.point.depth) * Double(PitchDimensions.length)
            let width = ($0.width - target.point.width) * Double(PitchDimensions.width)
            return (depth * depth + width * width).squareRoot()
        }
    }
    // Allow only floating-point roundoff at the normalized-coordinate boundary.
    var insideZone: Bool { distanceMeters.map { $0 <= radiusMeters + 1e-9 } ?? false }
}

enum PlaySequence {
    static func duration(_ frames: [PlayFrame]) -> Double { frames.dropLast().reduce(0) { $0 + $1.duration } }
    static func index(at elapsed: Double, frames: [PlayFrame]) throws -> Int? {
        guard elapsed.isFinite else { throw WorkbenchError.invalid("Sequence time must be finite.") }
        guard frames.allSatisfy({ $0.duration.isFinite && (1...10).contains($0.duration) }) else {
            throw WorkbenchError.invalid("Sequence step duration is invalid.")
        }
        guard !frames.isEmpty else { return nil }
        var remaining = max(0, elapsed)
        for index in frames.indices.dropLast() {
            if remaining < frames[index].duration { return index }
            remaining -= frames[index].duration
        }
        return frames.count - 1
    }
}
