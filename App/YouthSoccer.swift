import CoreGraphics
import Foundation

enum TeamFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case three = "3v3", four = "4v4", five = "5v5", seven = "7v7", nine = "9v9", eleven = "11v11"
    var id: String { rawValue }
    var playersPerTeam: Int {
        switch self { case .three: 3; case .four: 4; case .five: 5; case .seven: 7; case .nine: 9; case .eleven: 11 }
    }
    var hasGoalkeeper: Bool { playersPerTeam >= 5 }
    var fieldLength: CGFloat {
        switch self { case .three: 15; case .four: 27; case .five: 37; case .seven: 55; case .nine: 73; case .eleven: 105 }
    }
    var fieldWidth: CGFloat {
        switch self { case .three: 10; case .four: 18; case .five: 27; case .seven: 37; case .nine: 46; case .eleven: 68 }
    }
    var goalWidth: CGFloat {
        switch self {
        case .three: 1.2192
        case .four: 1.8288
        case .five, .seven: 3.6576
        case .nine: 4.8768
        case .eleven: 7.32
        }
    }
    var formations: [TeamFormation] {
        switch self {
        case .three: [.twoOne, .oneTwo]
        case .four, .five: [.oneTwoOne, .twoTwo]
        case .seven: [.twoThreeOne, .threeTwoOne]
        case .nine: [.threeThreeTwo, .fourThreeOne]
        case .eleven: [.fourThreeThree, .fourFourTwo]
        }
    }
    var ageContext: String {
        switch self {
        case .three: "England 2026-27: U7. Other leagues may use different introductory formats."
        case .four: "Common introductory U.S. format. This is a 27 x 18 m training illustration, not a local field-size mandate."
        case .five: "England 2026-27: U8-U9. Often also used for training elsewhere."
        case .seven: "Often U9-U10 in the U.S.; England 2026-27 uses U10-U11."
        case .nine: "Often U11-U12 in the U.S.; England 2026-27 uses U12-U13."
        case .eleven: "Full-size 105 x 68 m reference. England starts 11v11 at U14; younger 11v11 pitches may be smaller."
        }
    }
    var layoutNote: String {
        "\(playersPerTeam) players per side\(hasGoalkeeper ? ", including one goalkeeper" : ", no goalkeeper"). Formation numbers count outfield players only. Rotate roles and prioritize enjoyment and involvement."
    }
    var pitchNote: String {
        switch self {
        case .eleven: "Full-size reference, not a universal youth pitch."
        case .four: "Illustrative 27 x 18 m training pitch. Local dimensions vary. Boxes, retreat/build-out lines and offside are not simulated."
        default: "England Football reference size. Simplified youth markings omit boxes and retreat/build-out lines; offside is not simulated. Check local rules."
        }
    }
    var references: [PlayReference] {
        let url: String
        switch self {
        case .three:
            url = "https://www.englandfootball.com/play/youth-football/Youth-Club-Football/U7"
        case .four:
            url = "https://www.ussoccer.com/stories/2017/08/five-things-to-know-how-smallsided-standards-will-change-youth-soccer"
        default:
            url = "https://learn.englandfootball.com/articles-and-resources/coaching/resources/2025/How-to-play-and-manage-\(rawValue)-games"
        }
        return [PlayReference(title: self == .four ? "U.S. Soccer - Small-sided player development" : "England Football - \(rawValue) guidance",
                              url: URL(string: url)!)]
    }
}

enum TeamFormation: String, Codable, Identifiable, Sendable {
    case twoOne = "2-1", oneTwo = "1-2", oneTwoOne = "1-2-1", twoTwo = "2-2"
    case twoThreeOne = "2-3-1", threeTwoOne = "3-2-1"
    case threeThreeTwo = "3-3-2", fourThreeOne = "4-3-1"
    case fourThreeThree = "4-3-3", fourFourTwo = "4-4-2"
    var id: String { rawValue }
    var lines: [Int] {
        switch self {
        case .twoOne: [2, 1]
        case .oneTwo: [1, 2]
        case .oneTwoOne: [1, 2, 1]
        case .twoTwo: [2, 2]
        case .twoThreeOne: [2, 3, 1]
        case .threeTwoOne: [3, 2, 1]
        case .threeThreeTwo: [3, 3, 2]
        case .fourThreeOne: [4, 3, 1]
        case .fourThreeThree: [4, 3, 3]
        case .fourFourTwo: [4, 4, 2]
        }
    }
}

enum AnimationRole: String, Codable, Sendable {
    case outfield, goalkeeper
}

struct TeamSetup: Codable, Equatable, Sendable {
    var format: TeamFormat
    var formation: TeamFormation

    func validate() throws {
        guard format.formations.contains(formation),
              formation.lines.reduce(0, +) + (format.hasGoalkeeper ? 1 : 0) == format.playersPerTeam else {
            throw WorkbenchError.invalid("Choose a formation that matches the selected team format.")
        }
    }

    func players() throws -> [AnimationPlayer] {
        try validate()
        var players: [AnimationPlayer] = []
        for team in [AnimationTeam.home, .away] {
            let offset = team == .home ? 0 : 100
            var number = 1
            func point(_ depth: Double, _ width: Double) -> FieldPoint {
                team == .home ? FieldPoint(depth: depth, width: width) : FieldPoint(depth: 1 - depth, width: 1 - width)
            }
            if format.hasGoalkeeper {
                players.append(AnimationPlayer(id: offset + number, label: "GK", team: team, point: point(0.06, 0.5), role: .goalkeeper))
                number += 1
            }
            let lines = formation.lines
            for (row, count) in lines.enumerated() {
                let depth = 0.17 + Double(row) * (0.26 / Double(max(1, lines.count - 1)))
                for column in 0..<count {
                    let width = Double(column + 1) / Double(count + 1)
                    players.append(AnimationPlayer(id: offset + number, label: String(number), team: team,
                                                   point: point(depth, width), role: .outfield))
                    number += 1
                }
            }
        }
        return players
    }

    func animation() throws -> TacticalAnimation {
        let roster = try players()
        let start = AnimationFrame(time: 0, ball: FieldPoint(depth: 0.5, width: 0.5), players: roster,
                                   cue: "Find space, look for a teammate and enjoy playing. Rotate roles rather than fixing children in one position.")
        var next = start
        next.time = 2
        next.cue = "Move a player or the ball to show the next simple decision."
        return TacticalAnimation(category: "\(format.rawValue) youth", frames: [start, next],
                                 references: format.references, origin: .userCreated, teamSetup: self)
    }

    func newPlay(board: BoardSnapshot) throws -> SavedPlay {
        try board.validate()
        return SavedPlay(title: "\(format.rawValue) - \(formation.rawValue) starting shape",
                         notes: format.layoutNote + "\n" + format.ageContext + "\n" + format.pitchNote +
                            "\nIllustrative original layout; local league rules take precedence.",
                         board: board, animation: try animation())
    }
}
