import CoreGraphics
import Foundation

enum PlayDiagram {
    static func svg(_ play: SavedPlay) throws -> Data {
        try play.validate()
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        func number(_ value: CGFloat) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(value)) }
        func lines(_ text: String, count: Int) -> [String] {
            let characters = Array(text.replacingOccurrences(of: "\n", with: " "))
            return stride(from: 0, to: characters.count, by: count).map {
                String(characters[$0..<min($0 + count, characters.count)])
            }
        }
        let titles = lines(play.title, count: 32)
        let opening = play.animation?.frames.first
        let format = play.animation?.teamSetup?.format
        let notes = lines(String(play.notes.prefix(240)), count: 50)
        let header = CGFloat(60 + titles.count * 28)
        let totalHeight = header + 1160 + CGFloat(notes.count * 18 + 85)
        let projection = PitchProjection(size: CGSize(width: 760, height: 1160), horizontal: false, format: format)
        let field = projection.bounds
        func point(_ point: FieldPoint) -> String {
            let location = projection.location(point)
            return "\(number(location.x)),\(number(location.y))"
        }
        func rectangle(_ rectangle: CGRect) -> String {
            "<rect x=\"\(number(rectangle.minX))\" y=\"\(number(rectangle.minY))\" width=\"\(number(rectangle.width))\" height=\"\(number(rectangle.height))\"/>"
        }
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="800" height="\(number(totalHeight))" viewBox="0 0 800 \(number(totalHeight))">
        <title>\(escape(play.title))</title><rect width="100%" height="100%" fill="#09110f"/>
        <g fill="#eaf3ec" font-family="sans-serif" font-size="24" font-weight="700">
        """
        for (index, line) in titles.enumerated() {
            svg += "<text x=\"40\" y=\"\(44 + index * 28)\">\(escape(line))</text>"
        }
        svg += """
        </g><text x="40" y="\(number(header - 10))" fill="#b9c9bf" font-family="sans-serif" font-size="12">
        CoachAI - \(opening == nil ? escape(play.board.scene.formation.rawValue) + " - saved editable positions" : "animation opening frame - static diagram") - \(format.map { "\($0.rawValue) - " } ?? "")\(Int(projection.fieldLength)) x \(Int(projection.fieldWidth)) m\(format == nil ? "" : " reference")
        </text><g transform="translate(20 \(number(header)))">
        <g fill="#124b37" stroke="#92b6a1" stroke-width="2">\(rectangle(field))</g>
        <g fill="none" stroke="#92b6a1" stroke-width="2">
        """
        if format != .three {
            svg += "<path d=\"M \(point(FieldPoint(depth: 0.5, width: 0))) L \(point(FieldPoint(depth: 0.5, width: 1)))\"/>"
        }
        if projection.fullSizeMarkings {
            svg += "<circle cx=\"\(number(field.midX))\" cy=\"\(number(field.midY))\" r=\"\(number(PitchDimensions.centerCircleRadius * projection.metersToPoints))\"/>"
            for own in [true, false] {
                for (depth, width) in [(PitchDimensions.penaltyAreaDepth, PitchDimensions.penaltyAreaWidth),
                                       (PitchDimensions.goalAreaDepth, PitchDimensions.goalAreaWidth)] {
                    let depthRange: ClosedRange<CGFloat> = own ? 0...depth : (PitchDimensions.length - depth)...PitchDimensions.length
                    svg += rectangle(projection.meterRectangle(depth: depthRange, width: ((PitchDimensions.width - width) / 2)...((PitchDimensions.width + width) / 2)))
                }
                let spot = projection.meterLocation(depth: own ? PitchDimensions.penaltySpotDistance : PitchDimensions.length - PitchDimensions.penaltySpotDistance,
                                                   width: PitchDimensions.width / 2)
                svg += "<circle data-mark=\"penalty-spot\" cx=\"\(number(spot.x))\" cy=\"\(number(spot.y))\" r=\"2\" fill=\"#92b6a1\"/>"
            }
        }
        for own in [true, false] {
            let start = projection.meterLocation(depth: own ? 0 : projection.fieldLength, width: (projection.fieldWidth - projection.goalWidth) / 2)
            let end = projection.meterLocation(depth: own ? 0 : projection.fieldLength, width: (projection.fieldWidth + projection.goalWidth) / 2)
            svg += "<path data-mark=\"goal\" d=\"M \(number(start.x)),\(number(start.y)) L \(number(end.x)),\(number(end.y))\" stroke-width=\"4\"/>"
        }
        svg += "<circle cx=\"\(number(field.midX))\" cy=\"\(number(field.midY))\" r=\"2\" fill=\"#92b6a1\"/>"
        svg += "</g><g fill=\"none\" stroke=\"white\" stroke-width=\"3\" stroke-linecap=\"round\">"
        for route in (opening == nil ? play.board.routes : []) {
            guard let first = route.first, let last = route.last else { continue }
            var path = "M \(point(first))"
            for index in 1..<route.count {
                let previous = projection.location(route[index - 1])
                let current = projection.location(route[index])
                path += " Q \(number(previous.x)),\(number(previous.y)) \(number((previous.x + current.x) / 2)),\(number((previous.y + current.y) / 2))"
            }
            path += " L \(point(last))"
            svg += "<path d=\"\(path)\"/>"
            if let direction = RouteDrawing.arrowDirection(for: route, projection: projection) {
                let end = projection.location(last)
                let angle = atan2(direction.dy, direction.dx)
                svg += "<path data-mark=\"route-arrow\" d=\"M \(number(end.x - 12 * cos(angle - 0.5))),\(number(end.y - 12 * sin(angle - 0.5))) L \(point(last)) L \(number(end.x - 12 * cos(angle + 0.5))),\(number(end.y - 12 * sin(angle + 0.5)))\"/>"
            }
        }
        svg += "</g>"
        if let opening {
            for player in opening.players {
                let location = projection.location(player.point)
                let color = player.team == .home ? "#c7f567" : "#ac3945"
                svg += "<circle cx=\"\(number(location.x))\" cy=\"\(number(location.y))\" r=\"18\" fill=\"\(color)\"/>"
                if player.role == .goalkeeper {
                    svg += "<circle data-mark=\"goalkeeper\" cx=\"\(number(location.x))\" cy=\"\(number(location.y))\" r=\"14\" fill=\"none\" stroke=\"white\"/>"
                }
                svg += "<text x=\"\(number(location.x))\" y=\"\(number(location.y + 4))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\" fill=\"#09110f\">\(escape(player.label))</text>"
            }
        } else {
            for player in play.board.scene.teammates {
                let location = projection.location(player.point)
                let color = player.role == play.board.position ? "#c7f567" : "#75ccff"
                svg += "<circle cx=\"\(number(location.x))\" cy=\"\(number(location.y))\" r=\"18\" fill=\"\(color)\"/>"
                svg += "<text x=\"\(number(location.x))\" y=\"\(number(location.y + 4))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\" fill=\"#09110f\">\(player.role.rawValue)</text>"
            }
            for player in play.board.scene.opponents {
                let location = projection.location(player.point)
                svg += "<circle cx=\"\(number(location.x))\" cy=\"\(number(location.y))\" r=\"15\" fill=\"#ac3945\"/>"
                svg += "<text x=\"\(number(location.x))\" y=\"\(number(location.y + 4))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\" fill=\"white\">\(player.role.rawValue)</text>"
            }
        }
        let ball = projection.location(opening?.ball ?? play.board.scene.ball)
        svg += "<circle cx=\"\(number(ball.x))\" cy=\"\(number(ball.y))\" r=\"12\" fill=\"white\" stroke=\"#09110f\" stroke-width=\"3\"/></g>"
        let footer = header + 1160
        svg += "<g font-family=\"sans-serif\" font-size=\"12\" fill=\"#b9c9bf\"><text x=\"40\" y=\"\(number(footer + 20))\">Coaching notes\(play.notes.count > 240 ? " (excerpt; full notes in play file)" : "")</text>"
        for (index, line) in notes.enumerated() {
            svg += "<text x=\"40\" y=\"\(number(footer + 44 + CGFloat(index * 18)))\">\(escape(line))</text>"
        }
        svg += "</g></svg>"
        return Data(svg.utf8)
    }
}
