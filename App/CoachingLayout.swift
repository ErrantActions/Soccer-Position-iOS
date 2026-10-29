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
        let heightBudget = max(0, min(largeText ? 360 : 560, size.height * (largeText ? 0.42 : 0.60)))
        return CompactPitchMetrics(
            padding: padding, spacing: size.height < 700 ? 14 : 20,
            pitchSize: PitchDimensions.fittedViewport(in: CGSize(width: width, height: heightBudget), horizontal: horizontal),
            horizontal: horizontal,
            showIntroduction: size.width >= 600 && size.height >= 900 && !largeText
        )
    }
}

enum PitchDimensions {
    // A common professional reference; the laws permit other field dimensions.
    static let length: CGFloat = 105
    static let width: CGFloat = 68
    static let centerCircleRadius: CGFloat = 9.15
    static let goalWidth: CGFloat = 7.32
    static let goalAreaDepth: CGFloat = 5.5
    static let goalAreaWidth: CGFloat = goalWidth + goalAreaDepth * 2
    static let penaltyAreaDepth: CGFloat = 16.5
    static let penaltyAreaWidth: CGFloat = goalWidth + penaltyAreaDepth * 2
    static let penaltySpotDistance: CGFloat = 11
    static let canvasInset: CGFloat = 26

    static func aspectRatio(horizontal: Bool, format: TeamFormat? = nil) -> CGFloat {
        let length = format?.fieldLength ?? PitchDimensions.length
        let width = format?.fieldWidth ?? PitchDimensions.width
        return horizontal ? length / width : width / length
    }

    static func fittedPlayingSize(in available: CGSize, horizontal: Bool, format: TeamFormat? = nil) -> CGSize {
        let availableWidth = max(0, available.width)
        let availableHeight = max(0, available.height)
        guard availableWidth > 0, availableHeight > 0 else { return .zero }
        let ratio = aspectRatio(horizontal: horizontal, format: format)
        let fittedWidth = min(availableWidth, availableHeight * ratio)
        return CGSize(width: fittedWidth, height: fittedWidth / ratio)
    }

    static func inset(for size: CGSize) -> CGFloat {
        min(canvasInset, max(0, min(size.width, size.height)) / 2)
    }

    static func fittedViewport(in available: CGSize, horizontal: Bool) -> CGSize {
        let available = CGSize(width: max(0, available.width), height: max(0, available.height))
        let inset = inset(for: available)
        let field = fittedPlayingSize(
            in: CGSize(width: available.width - inset * 2, height: available.height - inset * 2),
            horizontal: horizontal
        )
        guard field.width > 0, field.height > 0 else { return available }
        return CGSize(width: field.width + inset * 2, height: field.height + inset * 2)
    }
}

struct PitchProjection {
    let bounds: CGRect
    let horizontal: Bool
    let format: TeamFormat?
    let presentation: TVMarkerSize?
    var isUsable: Bool { bounds.width > 0 && bounds.height > 0 }
    var interactionBounds: CGRect { isUsable ? bounds.insetBy(dx: -2, dy: -2) : bounds }
    var fieldLength: CGFloat { format?.fieldLength ?? PitchDimensions.length }
    var fieldWidth: CGFloat { format?.fieldWidth ?? PitchDimensions.width }
    var goalWidth: CGFloat { format?.goalWidth ?? PitchDimensions.goalWidth }
    var fullSizeMarkings: Bool { format == nil || format == .eleven }
    var metersToPoints: CGFloat { horizontal ? bounds.width / fieldLength : bounds.width / fieldWidth }

    init(size: CGSize, horizontal: Bool, format: TeamFormat? = nil, presentation: TVMarkerSize? = nil) {
        let size = CGSize(width: max(0, size.width), height: max(0, size.height))
        let inset = presentation?.canvasInset(for: size) ?? PitchDimensions.inset(for: size)
        let field = PitchDimensions.fittedPlayingSize(
            in: CGSize(width: size.width - inset * 2, height: size.height - inset * 2),
            horizontal: horizontal, format: format
        )
        self.bounds = CGRect(
            x: (size.width - field.width) / 2, y: (size.height - field.height) / 2,
            width: field.width, height: field.height
        )
        self.horizontal = horizontal
        self.format = format
        self.presentation = presentation
    }

    func location(_ point: FieldPoint) -> CGPoint {
        let point = point.bounded
        if horizontal {
            return CGPoint(x: bounds.minX + point.depth * bounds.width, y: bounds.minY + point.width * bounds.height)
        }
        return CGPoint(x: bounds.minX + point.width * bounds.width, y: bounds.maxY - point.depth * bounds.height)
    }

    func fieldPoint(_ location: CGPoint) -> FieldPoint {
        guard isUsable else { return FieldPoint(depth: 0.5, width: 0.5) }
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

    func meterLocation(depth: CGFloat, width: CGFloat) -> CGPoint {
        location(FieldPoint(depth: Double(depth / fieldLength), width: Double(width / fieldWidth)))
    }

    func meterRectangle(depth: ClosedRange<CGFloat>, width: ClosedRange<CGFloat>) -> CGRect {
        let first = meterLocation(depth: depth.lowerBound, width: width.lowerBound)
        let last = meterLocation(depth: depth.upperBound, width: width.upperBound)
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
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
