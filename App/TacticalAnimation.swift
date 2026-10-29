import Foundation

enum AnimationTeam: String, Codable, Sendable {
    case home, away
}

enum AnimationOrigin: String, Codable, Sendable {
    case coachAIOriginal, userCreated, adapted
}

struct AnimationPlayer: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let label: String
    let team: AnimationTeam
    var point: FieldPoint
    var role: AnimationRole?
}

struct AnimationFrame: Codable, Equatable, Sendable {
    var time: Double
    var ball: FieldPoint
    var players: [AnimationPlayer]
    var cue: String

    var rosterSummary: String {
        "Lime \(players.filter { $0.team == .home }.count) - Red \(players.filter { $0.team == .away }.count)"
    }
}

struct PlayReference: Codable, Equatable, Sendable {
    var title: String
    var url: URL
}

struct TacticalAnimation: Codable, Equatable, Sendable {
    var category: String
    var frames: [AnimationFrame]
    var references: [PlayReference]
    var origin: AnimationOrigin?
    var teamSetup: TeamSetup?

    var needsYouthSchema: Bool { teamSetup != nil || frames.contains { $0.players.contains { $0.role != nil } } }

    var duration: Double { frames.last?.time ?? 0 }

    func validate() throws {
        try teamSetup?.validate()
        guard (2...24).contains(frames.count), frames.first?.time == 0,
              duration.isFinite, (0.25...120).contains(duration) else {
            throw WorkbenchError.invalid("An animated play needs 2 to 24 frames, starting at zero and ending within 120 seconds.")
        }
        guard !category.isEmpty, category.count <= 40, PlayText.isSafe(category),
              references.count <= 6 else {
            throw WorkbenchError.invalid("An animated play needs a category and supports up to 6 optional research references.")
        }
        for reference in references {
            guard !reference.title.isEmpty, reference.title.count <= 120, PlayText.isSafe(reference.title),
                  reference.url.absoluteString.utf8.count <= 2_048,
                  reference.url.scheme == "https", reference.url.host?.isEmpty == false,
                  reference.url.user == nil, reference.url.password == nil else {
                throw WorkbenchError.invalid("Research references must have a title and an HTTPS URL without embedded credentials.")
            }
        }
        let initial = frames[0].players
        guard (2...22).contains(initial.count) else {
            throw WorkbenchError.invalid("An animated play supports 2 to 22 players.")
        }
        let identities = Set(initial.map(\.id))
        var previousTime = -0.25
        for frame in frames {
            if let setup = teamSetup {
                for team in [AnimationTeam.home, .away] {
                    let players = frame.players.filter { $0.team == team }
                    guard players.count <= setup.format.playersPerTeam,
                          players.filter({ $0.role == .goalkeeper }).count <= (setup.format.hasGoalkeeper ? 1 : 0) else {
                        throw WorkbenchError.invalid("The roster or goalkeeper count exceeds the selected team format.")
                    }
                }
            }
            guard frame.time.isFinite, frame.time - previousTime >= 0.25 - 1e-9,
                  frame.ball.isInsideField, !frame.cue.isEmpty, frame.cue.count <= 400, PlayText.isSafe(frame.cue),
                  frame.players.count == initial.count, Set(frame.players.map(\.id)) == identities else {
                throw WorkbenchError.invalid("Animation frames need increasing times, valid coordinates, a cue and consistent unique players.")
            }
            guard Set(frame.players.map(\.id)).count == frame.players.count else {
                throw WorkbenchError.invalid("Animation player identities must be unique.")
            }
            for player in frame.players {
                guard (1...999).contains(player.id),
                      !player.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, player.label.count <= 6,
                      !player.label.contains("\n"), !player.label.contains("\r"),
                      PlayText.isSafe(player.label), player.point.isInsideField,
                      let original = initial.first(where: { $0.id == player.id }),
                      original.label == player.label, original.team == player.team, original.role == player.role else {
                    throw WorkbenchError.invalid("Animation players need stable labels, teams and valid field coordinates.")
                }
            }
            previousTime = frame.time
        }
    }

    func sample(at time: Double, reducedMotion: Bool = false) throws -> AnimationFrame {
        try validate()
        guard time.isFinite else { throw WorkbenchError.invalid("Animation time must be finite.") }
        return sampleValidated(at: time, reducedMotion: reducedMotion)
    }

    // Playback validates once before its display loop; imported data must not bypass validation.
    func sampleValidated(at time: Double, reducedMotion: Bool = false) -> AnimationFrame {
        let time = min(duration, max(0, time))
        guard let index = frames.indices.dropLast().first(where: { time < frames[$0 + 1].time }) else { return frames[frames.count - 1] }
        let first = frames[index]
        if reducedMotion { return first }
        let next = frames[index + 1]
        let progress = (time - first.time) / (next.time - first.time)
        let movement = progress * progress * (3 - 2 * progress)
        func mix(_ a: FieldPoint, _ b: FieldPoint, _ amount: Double) -> FieldPoint {
            FieldPoint(depth: a.depth + (b.depth - a.depth) * amount, width: a.width + (b.width - a.width) * amount)
        }
        let players = first.players.map { player in
            var result = player
            if let destination = next.players.first(where: { $0.id == player.id }) {
                result.point = mix(player.point, destination.point, movement)
            }
            return result
        }
        return AnimationFrame(time: time, ball: mix(first.ball, next.ball, progress), players: players, cue: first.cue)
    }
}

enum PlayText {
    static func isSafe(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            let value = $0.value
            return value == 9 || value == 10 || value == 13 ||
                (value >= 0x20 && value <= 0xD7FF) || (value >= 0xE000 && value <= 0xFFFD) || value >= 0x10000
        }
    }
}
