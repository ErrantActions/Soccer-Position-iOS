import CoreGraphics
import Foundation

struct CoachingLayout: Equatable {
    enum Mode: Equatable {
        case compact, desk, book, tabletop
    }

    enum ControlSection: Hashable {
        case role, routes, ai
    }

    let mode: Mode
    let pitchPane: CGRect
    let coachPane: CGRect?
    let usesDuoControls: Bool

    var controlSections: [ControlSection] {
        usesDuoControls ? [.routes, .ai, .role] : [.role, .routes, .ai]
    }

    var controlPanelPadding: CGFloat {
        guard let coachPane else { return 0 }
        return usesDuoControls || coachPane.width >= 300 ? 22 : 14
    }

    static func resolve(
        size: CGSize, division: CGRect?, largeText: Bool = false, duoDisplay: Bool = false
    ) -> CoachingLayout {
        let bounds = CGRect(origin: .zero, size: size)
        if let division {
            let fold = division.intersection(bounds)
            if !fold.isNull, fold.height > fold.width {
                let leading = CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
                let trailing = CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
                if min(leading.width, trailing.width) >= 160 {
                    return CoachingLayout(mode: .book, pitchPane: leading, coachPane: trailing, usesDuoControls: true)
                }
                return CoachingLayout(mode: .compact, pitchPane: leading.width > trailing.width ? leading : trailing, coachPane: nil, usesDuoControls: false)
            } else if !fold.isNull {
                let top = CGRect(x: 0, y: 0, width: size.width, height: fold.minY)
                let bottom = CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
                if min(top.height, bottom.height) >= 120 {
                    return CoachingLayout(mode: .tabletop, pitchPane: top, coachPane: bottom, usesDuoControls: true)
                }
                return CoachingLayout(mode: .compact, pitchPane: top.height > bottom.height ? top : bottom, coachPane: nil, usesDuoControls: false)
            }
        }
        let duoDesk = duoDisplay && size.width >= 480
        let landscapePhone = size.width >= 560 && size.width > size.height
        let regularDesk = size.width >= 680 || landscapePhone
        if (regularDesk || duoDesk), (!largeText || duoDesk) {
            let sidebar = duoDesk
                ? min(390, max(240, size.width * 0.38))
                : min(400, max(260, size.width * 0.36))
            return CoachingLayout(
                mode: .desk,
                pitchPane: CGRect(x: 0, y: 0, width: size.width - sidebar, height: size.height),
                coachPane: CGRect(x: size.width - sidebar, y: 0, width: sidebar, height: size.height),
                usesDuoControls: duoDesk
            )
        }
        return CoachingLayout(mode: .compact, pitchPane: bounds, coachPane: nil, usesDuoControls: false)
    }
}

struct CompactPitchMetrics: Equatable {
    let padding: CGFloat
    let spacing: CGFloat
    let pitchSize: CGSize
    let horizontal: Bool
    let showIntroduction: Bool

    static func resolve(size: CGSize, largeText: Bool) -> CompactPitchMetrics {
        let padding: CGFloat = size.width < 360 ? 14 : 20
        let width = max(0, min(600, size.width - padding * 2))
        let horizontal = size.width > size.height
        let ratio: CGFloat = horizontal ? 1.5 : 0.76
        let heightBudget = max(0, min(largeText ? 360 : 560, size.height * (largeText ? 0.42 : 0.60)))
        let pitchWidth = min(width, heightBudget * ratio)
        return CompactPitchMetrics(
            padding: padding, spacing: size.height < 700 ? 14 : 20,
            pitchSize: CGSize(width: pitchWidth, height: pitchWidth / ratio),
            horizontal: horizontal,
            showIntroduction: size.width >= 600 && size.height >= 900 && !largeText
        )
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
