import FoundationModels
import SwiftUI

enum CoachPalette {
    static let ink = Color(red: 0.035, green: 0.065, blue: 0.06)
    static let surface = Color(red: 0.075, green: 0.11, blue: 0.10)
    static let lime = Color(red: 0.78, green: 0.96, blue: 0.40)
    static let blue = Color(red: 0.46, green: 0.80, blue: 1)
    static let muted = Color(red: 0.66, green: 0.73, blue: 0.69)
}

struct CoachView: View {
    @State private var ball = FieldPoint(depth: 0.65, width: 0.35)
    @State private var position: Position = .lb
    @State private var comparison: Position = .lcb
    @State private var comparing = false
    @State private var showHeat = true
    @State private var showGuides = true
    @State private var drawing = false
    @State private var routes: [[FieldPoint]] = []
    @State private var draft: [FieldPoint] = []
    @State private var explanation: String?
    @State private var message: String?
    @State private var isGenerating = false
    @State private var generation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recommendation: Recommendation { Positioning.recommend(ball: ball, position: position) }

    var body: some View {
        GeometryReader { proxy in
            let division = activeDivision(proxy)
            let layout = CoachingLayout.resolve(size: proxy.size, division: division, largeText: typeSize.isAccessibilitySize)
            ZStack(alignment: .topLeading) {
                CoachPalette.ink.ignoresSafeArea()
                RadialGradient(colors: [CoachPalette.lime.opacity(0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 600)
                    .ignoresSafeArea().allowsHitTesting(false)
                Group {
                    if layout.mode == .tabletop {
                        tabletopPitch(size: layout.pitchPane.size)
                    } else {
                        pitchPane(layout: layout, duo: hasDuoDisplay(proxy))
                    }
                }
                    .frame(width: layout.pitchPane.width, height: layout.pitchPane.height)
                    .position(x: layout.pitchPane.midX, y: layout.pitchPane.midY)
                if let coach = layout.coachPane {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            sectionEyebrow(layout.mode == .tabletop ? "TOUCHLINE CONTROLS" : "THE COACH'S VIEW")
                            if layout.mode == .tabletop { pitchToolbar }
                            coachingControls
                        }
                        .padding(22)
                    }
                    .frame(width: coach.width, height: coach.height)
                    .position(x: coach.midX, y: coach.midY)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(CoachPalette.lime)
        .onChange(of: ball) { invalidateExplanation() }
        .onChange(of: position) {
            if comparison == position {
                comparison = Position.allCases.first { $0 != position } ?? .lb
            }
            invalidateExplanation()
        }
        .onChange(of: drawing) { draft = [] }
        .onChange(of: scenePhase) { if scenePhase != .active { invalidateExplanation() } }
        .onDisappear { invalidateExplanation() }
        .sensoryFeedback(.selection, trigger: position)
    }

    private func field(horizontal: Bool) -> some View {
        PitchView(
            ball: $ball, routes: $routes, draft: $draft, role: position,
            comparison: comparing ? comparison : nil,
            showHeat: showHeat, showGuides: showGuides,
            drawing: drawing, horizontal: horizontal
        )
    }

    private func tabletopPitch(size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label("Touchline stand", systemImage: "laptopcomputer")
                    .font(.caption.weight(.semibold))
                Spacer()
                Label("Defend left", systemImage: "arrow.left")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }
            field(horizontal: true)
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxWidth: max(1, min(size.width - 32, (size.height - 100) * 1.5)))
            HStack(spacing: 14) {
                legend(position.rawValue, color: CoachPalette.lime)
                if comparing { legend(comparison.rawValue, color: CoachPalette.blue) }
                Spacer(minLength: 0)
                Text(drawing ? "Draw your route" : "Drag to move the ball")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pitchPane(layout: CoachingLayout, duo: Bool) -> some View {
        let horizontal = layout.mode == .tabletop || layout.pitchPane.height < 500
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brand
                if layout.mode != .tabletop {
                    VStack(alignment: .leading, spacing: 7) {
                        sectionEyebrow("YOUR POSITION LAB")
                        Text("Read the game.\nOwn your space.")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .tracking(-1.3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("One ball. A better view of your next move.")
                            .font(.subheadline)
                            .foregroundStyle(CoachPalette.muted)
                    }
                }
                VStack(spacing: 14) {
                    HStack(alignment: .center) {
                        Label(horizontal ? "Defend left" : "Defend bottom", systemImage: horizontal ? "arrow.left" : "arrow.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CoachPalette.muted)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(CoachPalette.lime).frame(width: 5, height: 5)
                            Text(drawing ? "DRAW ROUTE" : "LIVE POSITION")
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundStyle(CoachPalette.lime)
                        }
                    }
                    field(horizontal: horizontal)
                    .aspectRatio(horizontal ? 1.5 : 0.76, contentMode: .fit)
                    .frame(maxWidth: horizontal ? 780 : 530)
                    pitchToolbar
                    HStack(spacing: 16) {
                        legend(position.rawValue, color: CoachPalette.lime)
                        if comparing { legend(comparison.rawValue, color: CoachPalette.blue) }
                        Label("Ball", systemImage: "soccerball").font(.caption).foregroundStyle(CoachPalette.muted)
                        Spacer(minLength: 0)
                    }
                    Text(drawing ? "Draw a route with your finger or Apple Pencil." : "Drag the ball anywhere. Your positioning updates instantly.")
                        .font(.caption)
                        .foregroundStyle(CoachPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if duo || layout.mode == .book || layout.mode == .tabletop {
                    duoBadge(layout.mode)
                }
                if layout.coachPane == nil { coachingControls }
            }
            .padding(layout.mode == .tabletop ? 16 : 22)
            .frame(maxWidth: layout.coachPane == nil ? 650 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.soccer")
                .font(.title3.weight(.bold))
                .foregroundStyle(CoachPalette.ink)
                .frame(width: 40, height: 40)
                .background(CoachPalette.lime.gradient, in: RoundedRectangle(cornerRadius: 13))
            Text("CoachAI")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .tracking(-0.5)
            Spacer()
            Text("DEFENDING")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .tracking(1)
                .foregroundStyle(CoachPalette.lime)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(CoachPalette.lime.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(CoachPalette.lime.opacity(0.2)))
        }
    }

    private var pitchToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { drawingTools; Spacer(minLength: 4); resetBall }
            VStack(alignment: .leading, spacing: 10) { drawingTools; resetBall }
        }
    }

    private var drawingTools: some View {
        HStack(spacing: 8) {
            Button {
                drawing.toggle()
            } label: {
                Label(drawing ? "Done drawing" : "Draw route", systemImage: drawing ? "checkmark" : "pencil.tip.crop.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .foregroundStyle(drawing ? CoachPalette.ink : .white)
                    .background(drawing ? CoachPalette.lime : .white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            if !routes.isEmpty {
                Button {
                    _ = routes.popLast()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last route")
            }
        }
    }

    private var resetBall: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                ball = FieldPoint(depth: 0.65, width: 0.35)
            }
        } label: {
            Label("Reset ball", systemImage: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .foregroundStyle(CoachPalette.muted)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var coachingControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionEyebrow("01  CHOOSE YOUR ROLE")
                    Spacer(minLength: 0)
                    Image(systemName: "person.crop.circle").foregroundStyle(CoachPalette.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Position.allCases) { role in
                            Button {
                                position = role
                            } label: {
                                Text(role.rawValue)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .frame(minWidth: 48, minHeight: 48)
                                    .foregroundStyle(position == role ? CoachPalette.ink : CoachPalette.muted)
                                    .background(position == role ? CoachPalette.lime : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(role.label)
                            .accessibilityAddTraits(position == role ? .isSelected : [])
                        }
                    }
                }
                Text(position.label).font(.subheadline.weight(.semibold))
            }
            .coachCard()
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("02  SET THE SCENE")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FieldScenario.allCases) { scenario in
                            Button {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { ball = scenario.point }
                            } label: {
                                Label(scenario.rawValue, systemImage: scenario.symbol)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 13)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(ball == scenario.point ? CoachPalette.lime : CoachPalette.muted)
                                    .background(ball == scenario.point ? CoachPalette.lime.opacity(0.10) : .white.opacity(0.04), in: Capsule())
                                    .overlay(Capsule().strokeBorder(ball == scenario.point ? CoachPalette.lime.opacity(0.4) : .clear))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(ball == scenario.point ? .isSelected : [])
                        }
                    }
                }
            }
            .coachCard()
            cueCard
            comparisonCard
            aiCard
            pitchSettings
            Label("A teaching guide, not match-specific advice.", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(CoachPalette.muted)
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
        }
    }

    private var cueCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("THE NEXT MOVE", systemImage: "scope")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .tracking(1)
                .foregroundStyle(CoachPalette.lime)
            Text(recommendation.cue)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(alignment: .top, spacing: 18) {
                metric("BALL SIDE", value: ball.width < 0.4 ? "Left channel" : ball.width > 0.6 ? "Right channel" : "Central")
                Spacer(minLength: 0)
                metric("FIELD ZONE", value: ball.depth < 0.33 ? "Defensive third" : ball.depth > 0.67 ? "Attacking third" : "Middle third")
            }
        }
        .coachCard(accent: true)
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $comparing) {
                Label("Compare roles", systemImage: "person.2")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint("Show two recommended player positions using the same ball.")
            if comparing {
                HStack {
                    legend(position.rawValue, color: CoachPalette.lime)
                    Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(CoachPalette.muted)
                    Picker("Compare with", selection: $comparison) {
                        ForEach(Position.allCases.filter { $0 != position }) { Text($0.label).tag($0) }
                    }
                    .tint(CoachPalette.blue)
                }
                Text(Positioning.recommend(ball: ball, position: comparison).cue)
                    .font(.subheadline)
                    .foregroundStyle(CoachPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Same ball. Two responsibilities.")
                    .font(.caption).foregroundStyle(CoachPalette.blue)
            } else {
                Text("See how a teammate's responsibility changes alongside yours.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
            }
        }
        .coachCard()
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles").foregroundStyle(CoachPalette.lime)
                Text("A little more insight.").font(.system(.headline, design: .rounded))
            }
            Text("An on-device explanation of your coaching cue. Your field stays on your device.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: explain) {
                HStack(spacing: 9) {
                    if isGenerating { ProgressView().tint(CoachPalette.ink) }
                    Text(isGenerating ? "Thinking on your device..." : "Explain the why")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if !isGenerating { Image(systemName: "arrow.up.right").font(.caption.weight(.bold)) }
                }
                .foregroundStyle(CoachPalette.ink)
                .padding(14)
                .frame(minHeight: 48)
                .background(CoachPalette.lime.gradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            if let explanation {
                Text(explanation).font(.subheadline).textSelection(.enabled)
                Text("AI-generated. Check with your coach.").font(.caption2).foregroundStyle(CoachPalette.muted)
            }
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                    .accessibilityIdentifier("coachAIStatus")
            }
            Label("Apple Intelligence required. No cloud fallback.", systemImage: "lock.shield")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }
        .coachCard()
    }

    private var pitchSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup {
                VStack(spacing: 14) {
                    Toggle("Position glow", isOn: $showHeat)
                    Toggle("Goal-side guide", isOn: $showGuides)
                    if !routes.isEmpty {
                        Button("Clear drawn routes", role: .destructive) { routes = []; draft = [] }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .font(.subheadline)
                .padding(.top, 14)
            } label: {
                Label("Pitch layers", systemImage: "square.3.layers.3d")
                    .font(.subheadline.weight(.medium))
            }
            Divider().overlay(.white.opacity(0.05))
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Distance from your goal").font(.caption).foregroundStyle(CoachPalette.muted)
                    Slider(value: $ball.depth, in: 0...1) { Text("Ball distance from your goal") }
                    Text("Left to right").font(.caption).foregroundStyle(CoachPalette.muted)
                    Slider(value: $ball.width, in: 0...1) { Text("Ball left to right") }
                }
                .padding(.top, 14)
            } label: {
                Label("Ball controls", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
            }
        }
        .coachCard()
    }

    private func duoBadge(_ mode: CoachingLayout.Mode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode == .tabletop ? "laptopcomputer" : "rectangle.split.2x1")
                .foregroundStyle(CoachPalette.lime)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .tabletop ? "Touchline stand" : mode == .book ? "Book-fold coaching" : "Made for a bigger view")
                    .font(.caption.weight(.semibold))
                Text(mode == .tabletop ? "Pitch above. Controls below. Nothing across the fold." : "One session, with space for the pitch and your coaching desk.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.caption2, design: .monospaced)).foregroundStyle(CoachPalette.muted)
            Text(value).font(.caption.weight(.semibold))
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(color)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .tracking(1.7)
            .foregroundStyle(CoachPalette.muted)
    }

    private func activeDivision(_ geometry: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).first?.frame
        }
        return nil
    }

    private func hasDuoDisplay(_ geometry: GeometryProxy) -> Bool {
        if #available(iOS 27.1, *) {
            return !geometry.reservedRegions(kind: .division, options: .includeInactive).isEmpty
        }
        return false
    }

    private func invalidateExplanation() {
        generation?.cancel()
        generation = nil
        isGenerating = false
        explanation = nil
        message = nil
    }

    private func explain() {
        guard case .available = SystemLanguageModel.default.availability else {
            message = "On-device AI is unavailable. Use a supported device with Apple Intelligence enabled and its model downloaded. The positioning guide still works."
            return
        }
        isGenerating = true
        message = nil
        let cue = recommendation.cue
        let role = position.label
        generation = Task { @MainActor in
            do {
                let session = LanguageModelSession(instructions: """
                    Explain only the supplied soccer teaching cue in two short, encouraging sentences.
                    Do not invent player coordinates or claim this is professional match analysis.
                    """)
                let result = try await session.respond(to: "Role: \(role). Coaching cue: \(cue)")
                try Task.checkCancellation()
                explanation = result.content
                isGenerating = false
            } catch is CancellationError {
                // A field change invalidated this response; do not overwrite newer state.
            } catch {
                guard !Task.isCancelled else { return }
                message = "The on-device explanation failed. Try again; the positioning guide is still available."
                isGenerating = false
            }
        }
    }
}

private struct CoachCard: ViewModifier {
    var accent = false

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent ? CoachPalette.lime.opacity(0.055) : CoachPalette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(accent ? CoachPalette.lime.opacity(0.2) : .white.opacity(0.065)))
    }
}

private extension View {
    func coachCard(accent: Bool = false) -> some View { modifier(CoachCard(accent: accent)) }
}

#Preview("Compact") {
    CoachView()
}

#Preview("Coaching desk", traits: .fixedLayout(width: 1000, height: 760)) {
    CoachView()
}
