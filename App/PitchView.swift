import SwiftUI

struct PitchView: View {
    @Binding var ball: FieldPoint
    @Binding var routeDrawing: RouteDrawing
    let role: Position
    let comparison: Position?
    let showHeat: Bool
    let showGuides: Bool
    let drawing: Bool
    let routeStyle: RouteStyle
    let snapRoutes: Bool
    let horizontal: Bool
    let recommendation: Recommendation
    let suggestions: [PlayerAdvice]
    let currentTeammates: [PlayerPlacement]
    let opponents: [OpponentPlacement]
    let aiSuggested: Bool
    let editTarget: SceneEditTarget
    let onMoveTarget: (SceneEditTarget, FieldPoint) -> Void
    let onEditingChanged: (Bool) -> Void
    let practice: PracticeRound?
    var displayRoutes: [[FieldPoint]]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.tvMarkerSize) private var tvMarkerSize
    @GestureState private var isDragging = false
    @State private var gestureContext: GestureContext?

    private struct GestureContext: Equatable {
        let frame: CGRect
        let horizontal: Bool
        let drawing: Bool
        let style: RouteStyle
        let snap: Bool
        let anchors: [FieldPoint]
        let routeCount: Int
        let editTarget: SceneEditTarget
    }

    private var anchors: [FieldPoint] {
        [ball] + suggestions.map(\.point) + currentTeammates.map(\.point) + opponents.map(\.point)
    }

    var body: some View {
        GeometryReader { geometry in
            let projection = PitchProjection(size: geometry.size, horizontal: horizontal, presentation: tvMarkerSize)
            let metrics = PitchMarkerMetrics(projection: projection)
            let frame = geometry.frame(in: .global)
            let context = GestureContext(
                frame: frame, horizontal: horizontal, drawing: drawing,
                style: routeStyle, snap: snapRoutes, anchors: drawing ? anchors : [],
                routeCount: routeDrawing.routes.count, editTarget: editTarget
            )
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(CoachPalette.surface)
                Canvas { context, size in
                    Self.drawField(context: &context, projection: projection, increasedContrast: contrast == .increased)
                    if showGuides {
                        var line = Path()
                        line.move(to: projection.location(ball))
                        line.addLine(to: projection.location(recommendation.point))
                        line.addLine(to: projection.location(FieldPoint(depth: 0, width: 0.5)))
                        context.stroke(line, with: .color(CoachPalette.lime.opacity(0.65)),
                                       style: StrokeStyle(lineWidth: 1.4 * metrics.scale, dash: [4 * metrics.scale, 6 * metrics.scale]))
                    }
                    if practice == nil {
                        for route in displayRoutes ?? (routeDrawing.routes + (routeDrawing.preview.isEmpty ? [] : [routeDrawing.preview])) {
                            drawRoute(route, context: &context, projection: projection)
                        }
                    }
                    if let round = practice, round.revealed {
                        let center = projection.location(round.target.point)
                        let radius = CGFloat(round.radiusMeters) * projection.metersToPoints
                        let zone = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(zone, with: .color(CoachPalette.lime.opacity(0.12)))
                        context.stroke(zone, with: .color(CoachPalette.lime),
                                       style: StrokeStyle(lineWidth: 2 * metrics.scale, dash: [4 * metrics.scale, 4 * metrics.scale]))
                    }
                }
                if drawing, let target = routeDrawing.snapTarget {
                    Circle()
                        .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 56, height: 56)
                        .position(projection.location(target))
                        .allowsHitTesting(false)
                }
                if showHeat {
                    Ellipse()
                        .fill(RadialGradient(colors: [CoachPalette.lime.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 75))
                        .frame(width: 155, height: 155)
                        .scaleEffect(metrics.scale)
                        .position(projection.location(recommendation.point))
                        .allowsHitTesting(false)
                }
                ForEach(currentTeammates) { player in
                    Text(player.role.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(CoachPalette.ink.opacity(0.8), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(editTarget == .teammate(player.role) ? 1 : 0.4), lineWidth: 1.5))
                        .scaleEffect(metrics.scale)
                        .position(projection.location(player.point))
                        .allowsHitTesting(false)
                }
                ForEach(opponents) { opponent in
                    Text(opponent.role.rawValue)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color(red: 0.65, green: 0.18, blue: 0.23), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(editTarget == .opponent(opponent.role) ? 1 : 0.25), lineWidth: 1.5))
                        .scaleEffect(metrics.scale)
                        .position(projection.location(opponent.point))
                        .allowsHitTesting(false)
                }
                ForEach(suggestions) { advice in
                    marker(advice.role, color: advice.role == role ? (aiSuggested ? CoachPalette.ai : CoachPalette.lime) :
                            advice.role == comparison ? CoachPalette.blue : CoachPalette.muted, secondary: advice.role != role)
                        .scaleEffect(metrics.scale * (advice.role == role ? 1 : 0.65))
                        .position(projection.location(advice.point))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: advice.point)
                }
                if let guess = practice?.guess {
                    marker(role, color: CoachPalette.blue, secondary: false)
                        .overlay(alignment: .top) {
                            Text("YOU").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).offset(y: -8)
                        }
                        .scaleEffect(metrics.scale)
                        .position(projection.location(guess))
                        .allowsHitTesting(false)
                }
                Image(systemName: "soccerball")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.white, Color.black.opacity(0.85))
                    .padding(7)
                    .background(.black.opacity(0.25), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    .scaleEffect(metrics.scale)
                    .position(projection.location(ball))
            }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .contentShape(PitchHitArea(bounds: projection.interactionBounds))
            .allowsHitTesting(projection.isUsable)
            .gesture(DragGesture(minimumDistance: drawing ? 3 : 0)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { value in
                    if gestureContext == nil {
                        guard projection.isUsable, projection.interactionBounds.contains(value.startLocation) else { return }
                        gestureContext = context
                        if !drawing { onEditingChanged(true) }
                    }
                    guard gestureContext == context else { return }
                    let point = projection.fieldPoint(value.location)
                    if drawing {
                        if routeDrawing.draft.isEmpty {
                            routeDrawing.begin(
                                at: projection.fieldPoint(value.startLocation), style: routeStyle,
                                projection: projection, anchors: anchors, snap: snapRoutes
                            )
                        }
                        routeDrawing.update(at: point, projection: projection, anchors: anchors, snap: snapRoutes)
                    } else {
                        if editTarget == .ball { ball = point } else { onMoveTarget(editTarget, point) }
                    }
                }
                .onEnded { value in
                    if drawing, gestureContext == context {
                        routeDrawing.finish(
                            at: projection.fieldPoint(value.location),
                            projection: projection, anchors: anchors, snap: snapRoutes
                        )
                    } else {
                        routeDrawing.cancelStroke()
                    }
                    gestureContext = nil
                    onEditingChanged(false)
                })
            .onChange(of: isDragging) {
                if !isDragging { routeDrawing.cancelStroke(); gestureContext = nil; onEditingChanged(false) }
            }
            .onChange(of: frame) { routeDrawing.cancelStroke() }
            .onChange(of: horizontal) { routeDrawing.cancelStroke() }
            .onDisappear { routeDrawing.cancelStroke(); onEditingChanged(false) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(practice?.revealed == false ? "Positioning practice. \(role.label). Answer hidden." :
                                "Soccer pitch. \(aiSuggested ? "AI suggestions" : "Instant guide"). \(role.label). \(recommendation.cue)")
            .accessibilityValue(practice?.revealed == false ? (practice?.guess == nil ? "Place your player, then check." : "Your player is placed. Check to reveal the guide.") :
                                "\(routeDrawing.routes.count) drawn routes. Suggested position \(Int((recommendation.point.depth * 100).rounded())) percent upfield and \(Int((recommendation.point.width * 100).rounded())) percent across.")
            .accessibilityHint(practice != nil ? "Use Your player coordinate controls in the practice panel with VoiceOver." :
                                "Use Ball controls in the settings panel to move the ball with VoiceOver.")
        }
    }

    private func marker(_ role: Position, color: Color, secondary: Bool) -> some View {
        Text(role.rawValue)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(secondary ? color : CoachPalette.ink)
            .frame(width: 38, height: 38)
            .background(secondary ? CoachPalette.ink : color, in: Circle())
            .overlay(Circle().strokeBorder(secondary ? color : .white.opacity(0.7), lineWidth: 2))
            .padding(5)
            .background(color.opacity(0.12), in: Circle())
            .shadow(color: color.opacity(0.25), radius: 12, y: 2)
            .allowsHitTesting(false)
    }

    static func drawField(context: inout GraphicsContext, projection: PitchProjection, increasedContrast: Bool) {
        guard projection.isUsable else { return }
        let field = projection.bounds
        context.fill(Path(field), with: .linearGradient(
            Gradient(colors: [Color(red: 0.09, green: 0.28, blue: 0.22), Color(red: 0.04, green: 0.17, blue: 0.14)]),
            startPoint: CGPoint(x: field.minX, y: field.minY), endPoint: CGPoint(x: field.maxX, y: field.maxY)
        ))
        for index in 0..<10 where index.isMultiple(of: 2) {
            let stripe = projection.horizontal
                ? CGRect(x: field.minX + CGFloat(index) * field.width / 10, y: field.minY, width: field.width / 10, height: field.height)
                : CGRect(x: field.minX, y: field.minY + CGFloat(index) * field.height / 10, width: field.width, height: field.height / 10)
            context.fill(Path(stripe), with: .color(.white.opacity(0.025)))
        }
        var lines = Path()
        lines.addRect(field)
        if projection.format != .three {
            lines.move(to: projection.location(FieldPoint(depth: 0.5, width: 0)))
            lines.addLine(to: projection.location(FieldPoint(depth: 0.5, width: 1)))
        }
        let center = projection.location(FieldPoint(depth: 0.5, width: 0.5))
        if projection.fullSizeMarkings {
            let radius = PitchDimensions.centerCircleRadius * projection.metersToPoints
            lines.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            for ownGoal in [true, false] {
                for (boxDepth, boxWidth) in [
                    (PitchDimensions.penaltyAreaDepth, PitchDimensions.penaltyAreaWidth),
                    (PitchDimensions.goalAreaDepth, PitchDimensions.goalAreaWidth),
                ] {
                    let depth: ClosedRange<CGFloat> = ownGoal ? (0...boxDepth) :
                        ((PitchDimensions.length - boxDepth)...PitchDimensions.length)
                    let width = ((PitchDimensions.width - boxWidth) / 2)...((PitchDimensions.width + boxWidth) / 2)
                    lines.addRect(projection.meterRectangle(depth: depth, width: width))
                }
                let spot = projection.meterLocation(
                    depth: ownGoal ? PitchDimensions.penaltySpotDistance : PitchDimensions.length - PitchDimensions.penaltySpotDistance,
                    width: PitchDimensions.width / 2
                )
                context.fill(Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.5)))
            }
        }
        context.stroke(lines, with: .color(.white.opacity(increasedContrast ? 0.65 : 0.37)), lineWidth: 1.2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.65)))
        for ownGoal in [true, false] {
            let depth: CGFloat = ownGoal ? 0 : projection.fieldLength
            var goal = Path()
            goal.move(to: projection.meterLocation(depth: depth, width: (projection.fieldWidth - projection.goalWidth) / 2))
            goal.addLine(to: projection.meterLocation(depth: depth, width: (projection.fieldWidth + projection.goalWidth) / 2))
            context.stroke(goal, with: .color(ownGoal ? CoachPalette.lime : .white.opacity(0.7)), lineWidth: 4)
        }
    }

    private struct PitchHitArea: Shape {
        let bounds: CGRect

        func path(in rect: CGRect) -> Path {
            Path(bounds.offsetBy(dx: rect.minX, dy: rect.minY))
        }
    }

    private func drawRoute(_ points: [FieldPoint], context: inout GraphicsContext, projection: PitchProjection) {
        guard let first = points.first, let last = points.last, points.count > 1 else { return }
        let metrics = PitchMarkerMetrics(projection: projection)
        var path = Path()
        path.move(to: projection.location(first))
        if points.count == 2 {
            path.addLine(to: projection.location(last))
        } else {
            for index in 1..<points.count {
                let previous = projection.location(points[index - 1])
                let current = projection.location(points[index])
                let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: midpoint, control: previous)
            }
            path.addLine(to: projection.location(last))
        }
        context.stroke(path, with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: metrics.routeWidth, lineCap: .round, lineJoin: .round))
        let end = projection.location(last)
        guard let direction = RouteDrawing.arrowDirection(for: points, projection: projection) else { return }
        let angle = atan2(direction.dy, direction.dx)
        var arrow = Path()
        arrow.move(to: CGPoint(x: end.x - metrics.arrowLength * cos(angle - 0.5), y: end.y - metrics.arrowLength * sin(angle - 0.5)))
        arrow.addLine(to: end)
        arrow.addLine(to: CGPoint(x: end.x - metrics.arrowLength * cos(angle + 0.5), y: end.y - metrics.arrowLength * sin(angle + 0.5)))
        context.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: metrics.routeWidth, lineCap: .round, lineJoin: .round))
    }
}
