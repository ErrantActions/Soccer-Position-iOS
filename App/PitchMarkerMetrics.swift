import CoreGraphics

enum TVMarkerSize: String, CaseIterable, Identifiable, Sendable {
    case compact = "Compact", standard = "Standard", large = "Large", extraLarge = "Extra large"
    var id: String { rawValue }
    var multiplier: CGFloat {
        switch self { case .compact: 0.8; case .standard: 1; case .large: 1.25; case .extraLarge: 1.5 }
    }

    func canvasInset(for size: CGSize) -> CGFloat {
        let shortSide = max(0, min(size.width, size.height))
        return min(shortSide / 2, max(56, shortSide * 0.06) * multiplier)
    }
}

struct PitchMarkerMetrics {
    let scale: CGFloat
    let animationRadius: CGFloat
    var animationLabelFont: CGFloat { animationRadius * 0.85 }
    var animationBallFont: CGFloat { 24 * scale }
    var roleDiameter: CGFloat { 48 * scale }
    var routeWidth: CGFloat { 2.5 * scale }
    var arrowLength: CGFloat { 10 * scale }

    init(projection: PitchProjection) {
        if let presentation = projection.presentation {
            let shortSide = min(projection.bounds.width, projection.bounds.height)
            scale = max(2, shortSide / 450) * presentation.multiplier
        } else {
            scale = 1
        }
        animationRadius = min(20, max(11, projection.metersToPoints * 2.4)) * scale
    }
}
