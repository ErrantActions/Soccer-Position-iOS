import CoreGraphics
import Foundation

enum RouteStyle: String, CaseIterable, Identifiable {
    case curve = "Curve"
    case straight = "Straight"

    var id: String { rawValue }
}

struct RouteDrawing {
    private(set) var routes: [[FieldPoint]] = []
    private(set) var draft: [FieldPoint] = []
    private(set) var snapTarget: FieldPoint?
    private var undone: [[FieldPoint]] = []
    private var endpoint: FieldPoint?
    private var style: RouteStyle = .curve

    var canUndo: Bool { !routes.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    var preview: [FieldPoint] {
        guard let start = draft.first, let end = snapTarget ?? endpoint else { return [] }
        if style == .straight { return [start, end] }
        return draft.last == end ? draft : draft + [end]
    }

    mutating func begin(
        at point: FieldPoint, style: RouteStyle, projection: PitchProjection,
        anchors: [FieldPoint], snap: Bool
    ) {
        self.style = style
        let point = point.bounded
        snapTarget = snap ? Self.nearestAnchor(to: point, anchors: anchors, projection: projection) : nil
        draft = [snapTarget ?? point]
        endpoint = draft.first
    }

    mutating func update(at point: FieldPoint, projection: PitchProjection, anchors: [FieldPoint], snap: Bool) {
        guard let last = draft.last else { return }
        let point = point.bounded
        endpoint = point
        snapTarget = snap ? Self.nearestAnchor(to: point, anchors: anchors, projection: projection) : nil
        if style == .curve, Self.distance(last, point, projection: projection) >= 2.5 {
            draft.append(point)
        }
    }

    @discardableResult
    mutating func finish(at point: FieldPoint, projection: PitchProjection, anchors: [FieldPoint], snap: Bool) -> Bool {
        update(at: point, projection: projection, anchors: anchors, snap: snap)
        defer { cancelStroke() }
        let points = preview
        guard let start = points.first, points.count > 1 else { return false }
        let extent = points.map { Self.distance(start, $0, projection: projection) }.max() ?? 0
        let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) {
            $0 + Self.distance($1.0, $1.1, projection: projection)
        }
        guard extent >= 8, length >= 12 else { return false }
        let route = Self.simplify(points, projection: projection, tolerance: 3)
        guard route.count > 1 else { return false }
        routes.append(route)
        undone = []
        return true
    }

    mutating func cancelStroke() {
        draft = []
        endpoint = nil
        snapTarget = nil
    }

    mutating func undo() {
        cancelStroke()
        if let route = routes.popLast() { undone.append(route) }
    }

    mutating func redo() {
        cancelStroke()
        if let route = undone.popLast() { routes.append(route) }
    }

    mutating func clear() {
        cancelStroke()
        routes = []
        undone = []
    }

    static func validateSavedRoutes(_ routes: [[FieldPoint]]) throws {
        guard routes.count <= 100, routes.reduce(0, { $0 + $1.count }) <= 20_000 else {
            throw WorkbenchError.invalid("This board has too many route points to save safely.")
        }
        guard routes.allSatisfy({ route in
            route.count >= 2 && route.allSatisfy {
                $0.depth.isFinite && $0.width.isFinite && (0...1).contains($0.depth) && (0...1).contains($0.width)
            }
        }) else { throw WorkbenchError.invalid("A saved route has invalid coordinates.") }
    }

    mutating func restore(_ routes: [[FieldPoint]]) throws {
        try Self.validateSavedRoutes(routes)
        cancelStroke()
        self.routes = routes
        undone = []
    }

    static func nearestAnchor(to point: FieldPoint, anchors: [FieldPoint], projection: PitchProjection) -> FieldPoint? {
        let nearest = anchors.min {
            distance(point, $0, projection: projection) < distance(point, $1, projection: projection)
        }
        guard let nearest, distance(point, nearest, projection: projection) <= 18 else { return nil }
        return nearest.bounded
    }

    static func arrowDirection(for points: [FieldPoint], projection: PitchProjection) -> CGVector? {
        guard let last = points.last else { return nil }
        let end = projection.location(last)
        for point in points.dropLast().reversed() {
            let previous = projection.location(point)
            let length = hypot(end.x - previous.x, end.y - previous.y)
            if length >= 1 {
                return CGVector(dx: (end.x - previous.x) / length, dy: (end.y - previous.y) / length)
            }
        }
        return nil
    }

    private static func distance(_ first: FieldPoint, _ second: FieldPoint, projection: PitchProjection) -> CGFloat {
        let first = projection.location(first)
        let second = projection.location(second)
        return hypot(first.x - second.x, first.y - second.y)
    }

    private static func simplify(_ points: [FieldPoint], projection: PitchProjection, tolerance: CGFloat) -> [FieldPoint] {
        guard points.count > 2 else { return points }
        let locations = points.map(projection.location)
        var keep: Set<Int> = [0, points.count - 1]
        var segments = [(0, points.count - 1)]
        while let (start, end) = segments.popLast() {
            guard end - start > 1 else { continue }
            let first = locations[start]
            let last = locations[end]
            let dx = last.x - first.x
            let dy = last.y - first.y
            let squaredLength = dx * dx + dy * dy
            var farthest: Int?
            var maximum = tolerance
            for index in (start + 1)..<end {
                let point = locations[index]
                let ratio = squaredLength == 0 ? 0 : min(1, max(0, ((point.x - first.x) * dx + (point.y - first.y) * dy) / squaredLength))
                let distance = hypot(point.x - first.x - ratio * dx, point.y - first.y - ratio * dy)
                if distance > maximum {
                    maximum = distance
                    farthest = index
                }
            }
            if let farthest {
                keep.insert(farthest)
                segments.append((start, farthest))
                segments.append((farthest, end))
            }
        }
        return keep.sorted().map { points[$0] }
    }
}
