import Foundation

struct CoachingLayout: Equatable {
    enum Mode: Equatable {
        case compact, desk, book, tabletop
    }

    let mode: Mode
    let pitchPane: CGRect
    let coachPane: CGRect?

    static func resolve(size: CGSize, division: CGRect?, largeText: Bool = false) -> CoachingLayout {
        let bounds = CGRect(origin: .zero, size: size)
        if let division {
            let fold = division.intersection(bounds)
            if !fold.isNull, fold.height > fold.width {
                let leading = CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
                let trailing = CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
                if min(leading.width, trailing.width) >= 160 {
                    return CoachingLayout(mode: .book, pitchPane: leading, coachPane: trailing)
                }
                return CoachingLayout(mode: .compact, pitchPane: leading.width > trailing.width ? leading : trailing, coachPane: nil)
            } else if !fold.isNull {
                let top = CGRect(x: 0, y: 0, width: size.width, height: fold.minY)
                let bottom = CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
                if min(top.height, bottom.height) >= 120 {
                    return CoachingLayout(mode: .tabletop, pitchPane: top, coachPane: bottom)
                }
                return CoachingLayout(mode: .compact, pitchPane: top.height > bottom.height ? top : bottom, coachPane: nil)
            }
        }
        if size.width >= 760, !largeText {
            let sidebar = min(390, size.width * 0.4)
            return CoachingLayout(
                mode: .desk,
                pitchPane: CGRect(x: 0, y: 0, width: size.width - sidebar, height: size.height),
                coachPane: CGRect(x: size.width - sidebar, y: 0, width: sidebar, height: size.height)
            )
        }
        return CoachingLayout(mode: .compact, pitchPane: bounds, coachPane: nil)
    }
}

struct PitchProjection {
    let bounds: CGRect
    let horizontal: Bool

    init(size: CGSize, horizontal: Bool) {
        let inset = min(26, min(size.width, size.height) / 4)
        self.bounds = CGRect(
            x: inset, y: inset,
            width: max(1, size.width - inset * 2), height: max(1, size.height - inset * 2)
        )
        self.horizontal = horizontal
    }

    func location(_ point: FieldPoint) -> CGPoint {
        let point = point.bounded
        if horizontal {
            return CGPoint(x: bounds.minX + point.depth * bounds.width, y: bounds.minY + point.width * bounds.height)
        }
        return CGPoint(x: bounds.minX + point.width * bounds.width, y: bounds.maxY - point.depth * bounds.height)
    }

    func fieldPoint(_ location: CGPoint) -> FieldPoint {
        if horizontal {
            return FieldPoint(
                depth: (location.x - bounds.minX) / bounds.width,
                width: (location.y - bounds.minY) / bounds.height
            ).bounded
        }
        return FieldPoint(
            depth: (bounds.maxY - location.y) / bounds.height,
            width: (location.x - bounds.minX) / bounds.width
        ).bounded
    }
}

enum FieldScenario: String, CaseIterable, Identifiable {
    case buildUp = "Build-up"
    case leftFlank = "Left flank"
    case rightFlank = "Right flank"
    case danger = "Danger zone"

    var id: String { rawValue }
    var point: FieldPoint {
        switch self {
        case .buildUp: FieldPoint(depth: 0.78, width: 0.5)
        case .leftFlank: FieldPoint(depth: 0.6, width: 0.12)
        case .rightFlank: FieldPoint(depth: 0.6, width: 0.88)
        case .danger: FieldPoint(depth: 0.25, width: 0.5)
        }
    }
    var symbol: String {
        switch self {
        case .buildUp: "arrow.up"
        case .leftFlank: "arrow.up.left"
        case .rightFlank: "arrow.up.right"
        case .danger: "shield.lefthalf.filled"
        }
    }
}
