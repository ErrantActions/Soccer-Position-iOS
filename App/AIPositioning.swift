import Foundation

enum DefensiveFormation: String, Codable, CaseIterable, Identifiable, Sendable {
    case fourThreeThree = "4-3-3"
    case fourFourTwo = "4-4-2"
    var id: String { rawValue }
}

enum OpponentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case left = "7", striker = "9", right = "11"
    var id: String { rawValue }
}

struct PlayerPlacement: Codable, Equatable, Sendable, Identifiable {
    let role: Position
    var point: FieldPoint
    var id: Position { role }
}

struct OpponentPlacement: Codable, Equatable, Sendable, Identifiable {
    let role: OpponentRole
    var point: FieldPoint
    var id: OpponentRole { role }
}

enum SceneEditTarget: Hashable {
    case ball
    case teammate(Position)
    case opponent(OpponentRole)
    case practice

    var label: String {
        switch self {
        case .ball: "Move ball"
        case .teammate(let role): "Move teammate \(role.rawValue)"
        case .opponent(let role): "Move opponent \(role.rawValue)"
        case .practice: "Place your player"
        }
    }
}

struct TacticalScene: Codable, Equatable, Sendable {
    let ball: FieldPoint
    let formation: DefensiveFormation
    let teammates: [PlayerPlacement]
    let opponents: [OpponentPlacement]

    static let initialBall = FieldPoint(depth: 0.65, width: 0.35)
    static var defaultTeammates: [PlayerPlacement] {
        Position.allCases.map { PlayerPlacement(role: $0, point: Positioning.recommend(ball: initialBall, position: $0).point) }
    }
    static let defaultOpponents = [
        OpponentPlacement(role: .left, point: FieldPoint(depth: 0.55, width: 0.15)),
        OpponentPlacement(role: .striker, point: FieldPoint(depth: 0.48, width: 0.5)),
        OpponentPlacement(role: .right, point: FieldPoint(depth: 0.7, width: 0.85)),
    ]

    var promptContext: String {
        func coordinates(_ point: FieldPoint) -> String {
            String(format: "depth=%.3f width=%.3f", locale: Locale(identifier: "en_US_POSIX"), point.depth, point.width)
        }
        return """
        Formation: \(formation.rawValue). Analyze only the five-player defensive unit shown.
        Opposition has possession. Own goal: depth=0, width=0.5.
        Depth increases toward the opposition goal; width=0 is left, width=1 is right.
        Ball: \(coordinates(ball)).
        Current teammates:
        \(teammates.map { "\($0.role.rawValue): \(coordinates($0.point))" }.joined(separator: "\n"))
        Opponents:
        \(opponents.map { "\($0.role.rawValue): \(coordinates($0.point))" }.joined(separator: "\n"))
        """
    }
}

struct PlayerAdvice: Equatable, Sendable, Identifiable {
    let role: Position
    let point: FieldPoint
    let reason: String
    var id: Position { role }
}

struct AIPositionPlan: Equatable, Sendable {
    let players: [PlayerAdvice]
    let summary: String

    func recommendation(for role: Position) -> Recommendation? {
        players.first { $0.role == role }.map { Recommendation(point: $0.point, cue: $0.reason) }
    }
}

enum AIPositionValidation {
    static let minimumSpacing = 0.055
    static let opponentClearance = 0.04

    static func inputIssues(_ scene: TacticalScene) -> [String] {
        var issues: [String] = []
        if !insideField(scene.ball) { issues.append("The ball is outside the field.") }
        if scene.teammates.count != Position.allCases.count ||
            Set(scene.teammates.map(\.role)) != Set(Position.allCases) {
            issues.append("The scene must contain each of the five defensive roles exactly once.")
        }
        if scene.opponents.count != OpponentRole.allCases.count ||
            Set(scene.opponents.map(\.role)) != Set(OpponentRole.allCases) {
            issues.append("The scene must contain all three opponents exactly once.")
        }
        if scene.teammates.contains(where: { !insideField($0.point) }) ||
            scene.opponents.contains(where: { !insideField($0.point) }) {
            issues.append("Every current player must be inside the field.")
        }
        return issues
    }

    static func issues(_ plan: AIPositionPlan, scene: TacticalScene) -> [String] {
        var issues = inputIssues(scene)
        guard issues.isEmpty else { return issues }
        guard plan.players.count == Position.allCases.count,
              Set(plan.players.map(\.role)) == Set(Position.allCases) else {
            return ["AI must return each defensive role exactly once."]
        }
        if plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan.summary.count > 400 {
            issues.append("AI must provide a concise team explanation.")
        }
        for player in plan.players {
            guard insideField(player.point) else {
                issues.append("\(player.role.rawValue) has invalid coordinates.")
                continue
            }
            if !player.role.widthRange.contains(player.point.width) {
                issues.append("\(player.role.rawValue) is outside its role's channel.")
            }
            let maximumDepth = max(0.12, scene.ball.depth + (player.role == .cdm ? 0.08 : 0.03))
            if player.point.depth > maximumDepth {
                issues.append("\(player.role.rawValue) is not sufficiently goal-side.")
            }
            if player.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || player.reason.count > 280 {
                issues.append("\(player.role.rawValue) needs a concise positioning reason.")
            }
            if scene.opponents.contains(where: { distance(player.point, $0.point) < opponentClearance }) {
                issues.append("\(player.role.rawValue) overlaps an opponent.")
            }
        }
        guard plan.players.allSatisfy({ insideField($0.point) }) else { return issues }
        for first in plan.players.indices {
            for second in plan.players.indices where second > first {
                if distance(plan.players[first].point, plan.players[second].point) < minimumSpacing {
                    issues.append("Suggested teammates are too close together.")
                }
            }
        }
        let backs = [Position.lb, .lcb, .rcb, .rb].compactMap { role in plan.players.first { $0.role == role } }
        if zip(backs, backs.dropFirst()).contains(where: { $0.0.point.width + 0.035 > $0.1.point.width }) {
            issues.append("The back line crosses role channels.")
        }
        if let nearest = backs.map(\.point.depth).min(), let farthest = backs.map(\.point.depth).max(),
           farthest - nearest > 0.25 {
            issues.append("The defensive line is too stretched.")
        }
        let coverageDepth = max(0.12, min(0.58, scene.ball.depth * 0.8))
        if !plan.players.contains(where: {
            $0.role.centerBack && (0.32...0.68).contains($0.point.width) && $0.point.depth <= coverageDepth
        }) {
            issues.append("No center back protects the central goal corridor.")
        }
        return issues
    }

    private static func insideField(_ point: FieldPoint) -> Bool {
        point.isInsideField
    }

    private static func distance(_ first: FieldPoint, _ second: FieldPoint) -> Double {
        let depth = first.depth - second.depth
        let width = first.width - second.width
        return (depth * depth + width * width).squareRoot()
    }
}

struct PositioningRequest: Equatable, Sendable {
    let id = UUID()
    let scene: TacticalScene
}

struct PositioningAnalysis {
    private(set) var request: PositioningRequest?
    private(set) var plan: AIPositionPlan?
    private(set) var context: TacticalScene?
    private(set) var status = "Instant guide active."
    var isBusy: Bool { request != nil }

    mutating func begin(scene: TacticalScene, scheduled: Bool) -> PositioningRequest {
        reset()
        let request = PositioningRequest(scene: scene)
        self.request = request
        status = scheduled ? "Analysis queued after your edit. Showing the instant guide." : "AI is positioning the defensive unit. Showing the instant guide."
        return request
    }

    mutating func markThinking(_ request: PositioningRequest) {
        guard self.request == request else { return }
        status = "AI is positioning the defensive unit. Showing the instant guide."
    }

    @discardableResult
    mutating func finish(_ plan: AIPositionPlan, request: PositioningRequest, currentScene: TacticalScene) -> Bool {
        guard self.request == request else { return false }
        guard request.scene == currentScene else {
            reset(message: "Scene changed during analysis. Showing the instant guide.")
            return false
        }
        let issues = AIPositionValidation.issues(plan, scene: currentScene)
        self.request = nil
        guard issues.isEmpty else {
            self.plan = nil
            context = nil
            status = "AI suggestion rejected: \(issues.prefix(2).joined(separator: " ")) Showing the instant guide."
            return false
        }
        self.plan = plan
        context = currentScene
        status = "AI suggestions applied. Geometry checks passed; this is experimental coaching, not verified match analysis."
        return true
    }

    mutating func fail(_ message: String, request: PositioningRequest) {
        guard self.request == request else { return }
        reset(message: message)
    }

    mutating func reset(message: String = "Instant guide active.") {
        request = nil
        plan = nil
        context = nil
        status = message
    }

    func acceptedPlan(for scene: TacticalScene) -> AIPositionPlan? {
        context == scene ? plan : nil
    }
}
