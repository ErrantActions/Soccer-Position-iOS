import Foundation

enum AnimationEditTarget: Hashable, Sendable {
    case ball
    case player(Int)
}

struct AnimationDraft: Equatable, Sendable {
    private(set) var animation: TacticalAnimation
    private(set) var phase = 0
    private(set) var target: AnimationEditTarget = .ball

    init(_ animation: TacticalAnimation) throws {
        try animation.validate()
        self.animation = animation
    }

    var frame: AnimationFrame { animation.frames[phase] }
    var previousFrame: AnimationFrame? { phase > 0 ? animation.frames[phase - 1] : nil }
    var selectedPlayer: AnimationPlayer? {
        if case .player(let id) = target { return frame.players.first { $0.id == id } }
        return nil
    }
    var selectedPoint: FieldPoint { selectedPlayer?.point ?? frame.ball }
    var travelTime: Double? {
        phase + 1 < animation.frames.count ? animation.frames[phase + 1].time - frame.time : nil
    }

    // Text may be incomplete while typing; preview and persistence require full validation.
    var cue: String {
        get { frame.cue }
        set {
            guard newValue != frame.cue else { return }
            animation.frames[phase].cue = newValue
            markEdited()
        }
    }
    var category: String {
        get { animation.category }
        set {
            guard newValue != animation.category else { return }
            animation.category = newValue
            markEdited()
        }
    }

    mutating func selectPhase(_ index: Int) throws {
        guard animation.frames.indices.contains(index) else { throw WorkbenchError.invalid("Choose an existing phase.") }
        phase = index
    }

    mutating func select(_ target: AnimationEditTarget) throws {
        if case .player(let id) = target, !frame.players.contains(where: { $0.id == id }) {
            throw WorkbenchError.invalid("The selected player is not in this play.")
        }
        self.target = target
    }

    mutating func move(to point: FieldPoint) throws {
        guard point.isInsideField else { throw WorkbenchError.invalid("Place the selected item inside the field.") }
        switch target {
        case .ball:
            guard frame.ball != point else { return }
            animation.frames[phase].ball = point
        case .player(let id):
            guard let index = frame.players.firstIndex(where: { $0.id == id }) else {
                throw WorkbenchError.invalid("The selected player is not in this phase.")
            }
            guard frame.players[index].point != point else { return }
            animation.frames[phase].players[index].point = point
        }
        markEdited()
    }

    mutating func passToSelectedPlayer() throws {
        guard let player = selectedPlayer else { throw WorkbenchError.invalid("Select the receiving player first.") }
        animation.frames[phase].ball = player.point
        markEdited()
    }

    mutating func insertPhase(duration: Double = 2) throws {
        guard animation.frames.count < 24 else { throw WorkbenchError.invalid("A play supports up to 24 phases.") }
        guard duration.isFinite, duration >= 0.25, animation.duration + duration <= 120 else {
            throw WorkbenchError.invalid("Choose at least 0.25 seconds and keep the whole play within 120 seconds.")
        }
        var next = frame
        next.time += duration
        next.cue = "Describe the next decision."
        for index in (phase + 1)..<animation.frames.count { animation.frames[index].time += duration }
        animation.frames.insert(next, at: phase + 1)
        phase += 1
        markEdited()
    }

    mutating func removePhase() throws {
        guard animation.frames.count > 2 else { throw WorkbenchError.invalid("Keep at least two phases in an animation.") }
        if phase == 0 {
            let shift = animation.frames[1].time
            animation.frames.removeFirst()
            for index in animation.frames.indices { animation.frames[index].time -= shift }
        } else {
            let shift = frame.time - animation.frames[phase - 1].time
            animation.frames.remove(at: phase)
            for index in phase..<animation.frames.count { animation.frames[index].time -= shift }
        }
        phase = min(phase, animation.frames.count - 1)
        markEdited()
    }

    mutating func setTravelTime(_ seconds: Double) throws {
        guard let previous = travelTime else { throw WorkbenchError.invalid("The final phase has no outgoing movement.") }
        let shift = seconds - previous
        guard seconds.isFinite, seconds >= 0.25, animation.duration + shift <= 120 else {
            throw WorkbenchError.invalid("Use at least 0.25 seconds and keep the whole play within 120 seconds.")
        }
        for index in (phase + 1)..<animation.frames.count { animation.frames[index].time += shift }
        markEdited()
    }

    mutating func addPlayer(team: AnimationTeam) throws {
        guard frame.players.count < 22 else { throw WorkbenchError.invalid("A play supports up to 22 players.") }
        let range = team == .home ? 1...99 : 101...199
        let ids = Set(frame.players.map(\.id))
        let labels = Set(frame.players.filter { $0.team == team }.map(\.label))
        guard let id = range.first(where: { !ids.contains($0) }),
              let number = (1...99).first(where: { !labels.contains(String($0)) }) else {
            throw WorkbenchError.invalid("A unique player identity could not be allocated.")
        }
        let count = frame.players.filter { $0.team == team }.count
        let point = FieldPoint(depth: team == .home ? 0.3 : 0.65, width: Double(count + 1) / Double(count + 2))
        let player = AnimationPlayer(id: id, label: String(number), team: team, point: point)
        for index in animation.frames.indices { animation.frames[index].players.append(player) }
        target = .player(id)
        markEdited()
    }

    mutating func removeSelectedPlayer() throws {
        guard let player = selectedPlayer else { throw WorkbenchError.invalid("Select a player to remove.") }
        guard frame.players.count > 2 else { throw WorkbenchError.invalid("Keep at least two players in the play.") }
        for index in animation.frames.indices { animation.frames[index].players.removeAll { $0.id == player.id } }
        target = .ball
        markEdited()
    }

    mutating func renameSelectedPlayer(_ label: String) throws {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 6, PlayText.isSafe(label) else {
            throw WorkbenchError.invalid("Use a player label of 1 to 6 characters without control characters.")
        }
        try editSelectedLabel(label)
    }

    mutating func editSelectedLabel(_ label: String) throws {
        guard let player = selectedPlayer else { throw WorkbenchError.invalid("Select a player to rename.") }
        guard label.count <= 6, PlayText.isSafe(label), !label.contains("\n"), !label.contains("\r") else {
            throw WorkbenchError.invalid("Keep the player label on one line with at most 6 characters.")
        }
        for index in animation.frames.indices {
            guard let playerIndex = animation.frames[index].players.firstIndex(where: { $0.id == player.id }) else {
                throw WorkbenchError.invalid("The play's player roster is inconsistent.")
            }
            let old = animation.frames[index].players[playerIndex]
            animation.frames[index].players[playerIndex] = AnimationPlayer(id: old.id, label: label, team: old.team, point: old.point)
        }
        markEdited()
    }

    static func newPlay(board: BoardSnapshot) throws -> SavedPlay {
        try board.validate()
        let team = board.scene.teammates.enumerated().map {
            AnimationPlayer(id: $0.offset + 1, label: $0.element.role.rawValue, team: .home, point: $0.element.point)
        }
        let opponents = board.scene.opponents.enumerated().map {
            AnimationPlayer(id: $0.offset + 101, label: $0.element.role.rawValue, team: .away, point: $0.element.point)
        }
        let start = AnimationFrame(time: 0, ball: board.scene.ball, players: team + opponents,
                                   cue: "Set the starting positions and prepare the next pass.")
        var end = start
        end.time = 2
        end.cue = "Describe the next decision."
        return SavedPlay(title: "New animated play", board: board,
                         animation: TacticalAnimation(category: "Custom", frames: [start, end], references: [], origin: .userCreated))
    }

    private mutating func markEdited() {
        if animation.origin != .userCreated { animation.origin = .adapted }
    }
}
