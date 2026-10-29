import Foundation

struct FieldPoint: Codable, Equatable, Sendable {
    var depth: Double
    var width: Double

    var isInsideField: Bool {
        depth.isFinite && width.isFinite && (0...1).contains(depth) && (0...1).contains(width)
    }

    var bounded: FieldPoint {
        FieldPoint(depth: min(1, max(0, depth)), width: min(1, max(0, width)))
    }
}

enum Position: String, Codable, CaseIterable, Identifiable, Sendable {
    case lb = "LB", lcb = "LCB", rcb = "RCB", rb = "RB", cdm = "CDM"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lb: "Left back"
        case .lcb: "Left center back"
        case .rcb: "Right center back"
        case .rb: "Right back"
        case .cdm: "Defensive midfielder"
        }
    }
    var baseWidth: Double {
        switch self {
        case .lb: 0.21
        case .lcb: 0.39
        case .rcb: 0.61
        case .rb: 0.79
        case .cdm: 0.5
        }
    }
    var centerBack: Bool { self == .lcb || self == .rcb }
    var widthRange: ClosedRange<Double> {
        switch self {
        case .lb: 0.05...0.46
        case .lcb: 0.2...0.58
        case .rcb: 0.42...0.8
        case .rb: 0.54...0.95
        case .cdm: 0.3...0.7
        }
    }
}

struct Recommendation: Equatable, Sendable {
    let point: FieldPoint
    let cue: String
}

enum Positioning {
    // A deliberately small goal-side teaching model, not the web app's full team simulation.
    static func recommend(ball input: FieldPoint, position: Position) -> Recommendation {
        let ball = input.bounded
        let depthRatio = position.centerBack ? 0.38 : position == .cdm ? 0.54 : 0.46
        let minDepth = position == .cdm ? 0.2 : position.centerBack ? 0.05 : 0.08
        let maxDepth = position == .cdm ? 0.7 : position.centerBack ? 0.5 : 0.55
        let offset = position == .cdm ? 0.08 : position.centerBack ? 0.045 : 0.06
        let depth = min(maxDepth, max(minDepth, min(ball.depth * depthRatio, ball.depth - offset)))
        let width = position.baseWidth + (ball.width - position.baseWidth) * (position == .cdm ? 0.55 : 0.68)
        let point = FieldPoint(
            depth: depth,
            width: min(position.widthRange.upperBound, max(position.widthRange.lowerBound, width))
        )
        let cue = position == .cdm
            ? "Screen the middle and stay connected to your defenders."
            : position.centerBack
                ? "Protect the goal and cover the space behind your teammate."
                : "Shift toward the ball while protecting the inside channel."
        return Recommendation(point: point, cue: cue)
    }
}
