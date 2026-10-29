import FoundationModels
import SwiftUI

enum CoachPalette {
    static let ink = Color(red: 0.035, green: 0.065, blue: 0.06)
    static let surface = Color(red: 0.075, green: 0.11, blue: 0.10)
    static let lime = Color(red: 0.78, green: 0.96, blue: 0.40)
    static let blue = Color(red: 0.46, green: 0.80, blue: 1)
    static let ai = Color(red: 0.78, green: 0.67, blue: 1)
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
    @State private var routeDrawing = RouteDrawing()
    @State private var routeStyle: RouteStyle = .curve
    @State private var snapRoutes = true
    @State private var aiPositioning = false
    @State private var autoAnalyze = true
    @State private var formation: DefensiveFormation = .fourThreeThree
    @State private var teammates = TacticalScene.defaultTeammates
    @State private var opponents = TacticalScene.defaultOpponents
    @State private var sceneEditTarget: SceneEditTarget = .ball
    @State private var sceneEditing = false
    @State private var intelligence = PositioningIntelligence()
    @State private var explanation: String?
    @State private var message: String?
    @State private var isGenerating = false
    @State private var generation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scene: TacticalScene {
        TacticalScene(ball: ball, formation: formation, teammates: teammates, opponents: opponents)
    }
    private var acceptedPlan: AIPositionPlan? {
        aiPositioning ? intelligence.analysis.acceptedPlan(for: scene) : nil
    }
    private var recommendation: Recommendation { guidance(for: position) }
    private var effectiveEditTarget: SceneEditTarget { aiPositioning ? sceneEditTarget : .ball }
    private var displayedAdvice: [PlayerAdvice] {
        let roles = Position.allCases.filter { aiPositioning || $0 == position || (comparing && $0 == comparison) }
        return roles.map {
            let result = guidance(for: $0)
            return PlayerAdvice(role: $0, point: result.point, reason: result.cue)
        }
    }

    private func guidance(for role: Position) -> Recommendation {
        acceptedPlan?.recommendation(for: role) ?? Positioning.recommend(ball: ball, position: role)
    }

    private var coachingBoard: some View {
        GeometryReader { proxy in
            let division = activeDivision(proxy)
            let duo = hasDuoDisplay(proxy)
            let layout = CoachingLayout.resolve(
                size: proxy.size, division: division, largeText: typeSize.isAccessibilitySize, duoDisplay: duo
            )
            ZStack(alignment: .topLeading) {
                CoachPalette.ink.ignoresSafeArea()
                RadialGradient(colors: [CoachPalette.lime.opacity(0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 600)
                    .ignoresSafeArea().allowsHitTesting(false)
                Group {
                    if layout.coachPane != nil {
                        fixedPitchPane(size: layout.pitchPane.size)
                    } else {
                        pitchPane(layout: layout, duo: duo)
                    }
                }
                    .frame(width: layout.pitchPane.width, height: layout.pitchPane.height)
                    .position(x: layout.pitchPane.midX, y: layout.pitchPane.midY)
                if let coach = layout.coachPane {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            brand
                            sectionEyebrow(layout.mode == .tabletop ? "TOUCHLINE CONTROLS" :
                                            layout.usesDuoControls ? "DUO COACHING DESK" : "THE COACH'S VIEW")
                            coachingControls(layout: layout)
                        }
                        .padding(layout.controlPanelPadding)
                    }
                    .frame(width: coach.width, height: coach.height)
                    .position(x: coach.midX, y: coach.midY)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            coachingBoard
                .toolbar(.hidden, for: .navigationBar)
                .toolbar { nativeControls }
                .toolbar(.visible, for: .bottomBar)
                .toolbarBackground(CoachPalette.ink, for: .bottomBar)
                .toolbarBackground(.visible, for: .bottomBar)
                .toolbarColorScheme(.dark, for: .bottomBar)
        }
        .preferredColorScheme(.dark)
        .tint(CoachPalette.lime)
        .onChange(of: scene) {
            routeDrawing.cancelStroke()
            invalidateExplanation()
            intelligence.cancel(message: aiPositioning ? "Scene changed. Showing the instant guide." : "Instant guide active.")
            if aiPositioning, autoAnalyze, !sceneEditing { analyzePositions(debounced: true) }
        }
        .onChange(of: sceneEditing) {
            if !sceneEditing, aiPositioning, autoAnalyze { analyzePositions(debounced: true) }
        }
        .onChange(of: aiPositioning) {
            intelligence.cancel()
            invalidateExplanation()
            routeDrawing.cancelStroke()
            sceneEditTarget = .ball
            drawing = false
            if aiPositioning { analyzePositions() }
        }
        .onChange(of: autoAnalyze) {
            if autoAnalyze, aiPositioning, !sceneEditing { analyzePositions(debounced: true) }
        }
        .onChange(of: sceneEditTarget) { drawing = false; routeDrawing.cancelStroke() }
        .onChange(of: acceptedPlan) { routeDrawing.cancelStroke(); invalidateExplanation() }
        .onChange(of: position) {
            if comparison == position {
                comparison = Position.allCases.first { $0 != position } ?? .lb
            }
            routeDrawing.cancelStroke()
            invalidateExplanation()
        }
        .onChange(of: drawing) { routeDrawing.cancelStroke() }
        .onChange(of: routeStyle) { routeDrawing.cancelStroke() }
        .onChange(of: snapRoutes) { routeDrawing.cancelStroke() }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                routeDrawing.cancelStroke()
                invalidateExplanation()
                intelligence.cancel(message: "Analysis paused while the app is inactive. Showing the instant guide.")
            } else if aiPositioning, autoAnalyze {
                analyzePositions(debounced: true)
            }
        }
        .onDisappear { invalidateExplanation(); intelligence.cancel() }
        .sensoryFeedback(.selection, trigger: position)
        .sensoryFeedback(.selection, trigger: routeDrawing.routes.count)
    }

    @ToolbarContentBuilder private var nativeControls: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Menu {
                Picker("Your position", selection: $position) {
                    ForEach(Position.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Position \(position.rawValue)", systemImage: "person.crop.circle")
            }
            .accessibilityLabel("Choose position")
            .accessibilityValue(position.label)
            .accessibilityIdentifier("coach.toolbar.position")

            Button { drawing.toggle() } label: {
                Label(drawing ? "Done drawing" : "Draw route", systemImage: drawing ? "checkmark" : "pencil.tip.crop.circle")
            }
            .tint(drawing ? CoachPalette.lime : CoachPalette.muted)
            .accessibilityLabel(drawing ? "Done drawing" : "Draw route")
            .accessibilityValue(drawing ? "Drawing routes" : "Moving players")
            .accessibilityIdentifier("coach.toolbar.draw")

            Button(action: positioningAction) {
                Label(intelligence.analysis.isBusy ? "Cancel analysis" : "Analyze positions",
                      systemImage: intelligence.analysis.isBusy ? "stop.circle" : "sparkles")
            }
            .disabled(isGenerating)
            .accessibilityHint("Enables AI Positioning if it is off.")
            .accessibilityIdentifier("coach.toolbar.analyze")

            Menu {
                Button("Undo route", systemImage: "arrow.uturn.backward") { routeDrawing.undo() }
                    .disabled(!routeDrawing.canUndo)
                Button("Redo route", systemImage: "arrow.uturn.forward") { routeDrawing.redo() }
                    .disabled(!routeDrawing.canRedo)
                Button("Reset ball", systemImage: "arrow.counterclockwise", action: resetBallPosition)
                Toggle("Position glow", isOn: $showHeat)
                Toggle("Goal-side guide", isOn: $showGuides)
            } label: {
                Label("More pitch actions", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("coach.toolbar.more")
        }
    }

    private func field(horizontal: Bool) -> some View {
        PitchView(
            ball: $ball, routeDrawing: $routeDrawing, role: position,
            comparison: comparing ? comparison : nil,
            showHeat: showHeat, showGuides: showGuides,
            drawing: drawing, routeStyle: routeStyle, snapRoutes: snapRoutes, horizontal: horizontal,
            recommendation: recommendation, suggestions: displayedAdvice,
            currentTeammates: aiPositioning ? teammates : [], opponents: aiPositioning ? opponents : [],
            aiSuggested: acceptedPlan != nil, editTarget: effectiveEditTarget,
            onMoveTarget: moveSceneTarget, onEditingChanged: { sceneEditing = $0 }
        )
    }

    private func fixedPitchPane(size: CGSize) -> some View {
        let horizontal = size.width > size.height
        let viewport = PitchDimensions.fittedViewport(
            in: CGSize(width: max(0, size.width - 16), height: max(0, size.height - 16)),
            horizontal: horizontal
        )
        return field(horizontal: horizontal)
            .frame(width: viewport.width, height: viewport.height)
            .overlay(alignment: .top) {
                HStack(spacing: 12) {
                    legend(position.rawValue, color: acceptedPlan == nil ? CoachPalette.lime : CoachPalette.ai)
                    if comparing { legend(comparison.rawValue, color: CoachPalette.blue) }
                    Spacer(minLength: 0)
                    Label(horizontal ? "Defend left" : "Defend bottom", systemImage: horizontal ? "arrow.left" : "arrow.down")
                        .font(.caption2).foregroundStyle(CoachPalette.muted)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 18).padding(.top, 8)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Text(drawing ? "DRAW ROUTE  ·  \(routeStyle.rawValue.uppercased())" :
                        "\(acceptedPlan == nil ? "INSTANT GUIDE" : "AI SUGGESTIONS") · \(effectiveEditTarget.label.uppercased())")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
    }

    private func pitchPane(layout: CoachingLayout, duo: Bool) -> some View {
        let metrics = CompactPitchMetrics.resolve(size: layout.pitchPane.size, largeText: typeSize.isAccessibilitySize)
        let horizontal = metrics.horizontal
        return ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing) {
                brand
                if metrics.showIntroduction {
                    VStack(alignment: .leading, spacing: 7) {
                        sectionEyebrow("YOUR POSITION LAB")
                        Text("Read the game.\nOwn your space.")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .tracking(-0.7)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("One ball. A better view of your next move.")
                            .font(.subheadline)
                            .foregroundStyle(CoachPalette.muted)
                    }
                }
                rolePicker
                VStack(spacing: 14) {
                    HStack(alignment: .center) {
                        Label(horizontal ? "Defend left" : "Defend bottom", systemImage: horizontal ? "arrow.left" : "arrow.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CoachPalette.muted)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(CoachPalette.lime).frame(width: 5, height: 5)
                            Text(drawing ? "DRAW ROUTE" : acceptedPlan == nil ? "INSTANT GUIDE" : "AI SUGGESTIONS")
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundStyle(CoachPalette.lime)
                        }
                    }
                    field(horizontal: horizontal)
                        .frame(width: metrics.pitchSize.width, height: metrics.pitchSize.height)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 16) {
                        legend(position.rawValue, color: acceptedPlan == nil ? CoachPalette.lime : CoachPalette.ai)
                        if comparing { legend(comparison.rawValue, color: CoachPalette.blue) }
                        Label("Ball", systemImage: "soccerball").font(.caption).foregroundStyle(CoachPalette.muted)
                        Spacer(minLength: 0)
                    }
                    Text(drawing ? "Draw a route with your finger or Apple Pencil." :
                            aiPositioning ? "\(effectiveEditTarget.label) by dragging on the pitch. White outlines are current players; colored markers are suggestions." :
                            "Drag the ball anywhere. Your positioning updates instantly.")
                        .font(.caption)
                        .foregroundStyle(CoachPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if duo || layout.mode == .book || layout.mode == .tabletop {
                    duoBadge(layout.mode)
                }
                coachingControls(includeRole: false, layout: layout)
            }
            .padding(metrics.padding)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
    }

    private var brand: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { brandIdentity; Spacer(minLength: 8); phaseBadge }
            VStack(alignment: .leading, spacing: 8) { brandIdentity; phaseBadge }
        }
    }

    private var brandIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.soccer")
                .font(.title3.weight(.bold))
                .foregroundStyle(CoachPalette.ink)
                .frame(width: 40, height: 40)
                .background(CoachPalette.lime.gradient, in: RoundedRectangle(cornerRadius: 13))
            Text("CoachAI")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .tracking(-0.5)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
    }

    private var phaseBadge: some View {
        Text("DEFENDING")
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1)
            .foregroundStyle(CoachPalette.lime)
            .lineLimit(1).minimumScaleFactor(0.65)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(CoachPalette.lime.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(CoachPalette.lime.opacity(0.2)))
    }

    private var pitchToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { drawingTools; Spacer(minLength: 4); resetBall }
            VStack(alignment: .leading, spacing: 10) { drawingTools; resetBall }
        }
    }

    private var drawingTools: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { drawModeButton; routeHistoryButtons }
            VStack(alignment: .leading, spacing: 8) { drawModeButton; routeHistoryButtons }
        }
    }

    private var drawModeButton: some View {
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
    }

    private var routeHistoryButtons: some View {
        HStack(spacing: 8) {
            Button { routeDrawing.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("Undo last route")
            .disabled(!routeDrawing.canUndo)
            .opacity(routeDrawing.canUndo ? 1 : 0.35)
            Button { routeDrawing.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("Redo route")
            .disabled(!routeDrawing.canRedo)
            .opacity(routeDrawing.canRedo ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }

    private var routePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionEyebrow("PITCH & ROUTE TOOLS")
            pitchToolbar
            Picker("Route style", selection: $routeStyle) {
                ForEach(RouteStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Snap endpoints", isOn: $snapRoutes)
                .font(.subheadline)
            Text("Curve smooths your stroke. Straight draws a pass. Nearby endpoints snap to the ball or a player.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if routeDrawing.canUndo || routeDrawing.canRedo {
                Button("Clear routes and history", role: .destructive) { routeDrawing.clear() }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .coachCard()
    }

    private var resetBall: some View {
        Button(action: resetBallPosition) {
            Label("Reset ball", systemImage: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .foregroundStyle(CoachPalette.muted)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func resetBallPosition() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            ball = FieldPoint(depth: 0.65, width: 0.35)
        }
    }

    private var rolePicker: some View {
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
        .accessibilityLabel("Your position")
    }

    private var roleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionEyebrow("01  CHOOSE YOUR ROLE")
                Spacer(minLength: 0)
                Image(systemName: "person.crop.circle").foregroundStyle(CoachPalette.muted)
            }
            rolePicker
            Text(position.label).font(.subheadline.weight(.semibold))
        }
        .coachCard()
    }

    private func coachingControls(includeRole: Bool = true, layout: CoachingLayout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(layout.controlSections.filter { includeRole || $0 != .role }, id: \.self) { section in
                switch section {
                case .role: roleCard
                case .routes: routePanel
                case .ai: aiPositioningPanel
                }
            }
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
            Label(acceptedPlan == nil ? "THE NEXT MOVE · INSTANT GUIDE" : "THE NEXT MOVE · AI SUGGESTION", systemImage: "scope")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .tracking(1)
                .foregroundStyle(CoachPalette.lime)
            Text(recommendation.cue)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let plan = acceptedPlan {
                Text(plan.summary).font(.caption).foregroundStyle(CoachPalette.ai)
                    .fixedSize(horizontal: false, vertical: true)
                Text("AI target: \(Int((recommendation.point.depth * 100).rounded()))% upfield, \(Int((recommendation.point.width * 100).rounded()))% across.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            let metricsLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
            metricsLayout {
                metric("BALL SIDE", value: ball.width < 0.4 ? "Left channel" : ball.width > 0.6 ? "Right channel" : "Central")
                metric("FIELD ZONE", value: ball.depth < 0.33 ? "Defensive third" : ball.depth > 0.67 ? "Attacking third" : "Middle third")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        legend(position.rawValue, color: CoachPalette.lime)
                        Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(CoachPalette.muted)
                        comparisonPicker
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        legend(position.rawValue, color: CoachPalette.lime)
                        comparisonPicker
                    }
                }
                Text(guidance(for: comparison).cue)
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

    private var comparisonPicker: some View {
        Picker("Compare with", selection: $comparison) {
            ForEach(Position.allCases.filter { $0 != position }) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(CoachPalette.blue)
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
            .disabled(isGenerating || intelligence.analysis.isBusy)
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

    private var aiPositioningPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $aiPositioning) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("AI Positioning", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text("EXPERIMENTAL · ON DEVICE")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(CoachPalette.ai)
                }
            }
            .tint(CoachPalette.ai)
            Text("Apple Intelligence can propose actual player locations. Suggestions must pass geometry checks before they replace the instant guide.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if aiPositioning {
                Picker("Formation", selection: $formation) {
                    ForEach(DefensiveFormation.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Five-player defensive unit. Opposition has possession. White outlines show current teammates; red numbers show opponents.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Move on pitch", selection: $sceneEditTarget) {
                    Text("Move ball").tag(SceneEditTarget.ball)
                    ForEach(Position.allCases) { Text("Move teammate \($0.rawValue)").tag(SceneEditTarget.teammate($0)) }
                    ForEach(OpponentRole.allCases) { Text("Move opponent \($0.rawValue)").tag(SceneEditTarget.opponent($0)) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                selectedPlayerControls
                Toggle("Analyze after edits", isOn: $autoAnalyze).font(.subheadline)
                Button(action: positioningAction) {
                    HStack(spacing: 9) {
                        if intelligence.analysis.isBusy { ProgressView().tint(CoachPalette.ai) }
                        Text(intelligence.analysis.isBusy ? "Cancel analysis" : "Analyze positions")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: intelligence.analysis.isBusy ? "xmark" : "arrow.up.right")
                    }
                    .foregroundStyle(CoachPalette.ai)
                    .padding(14).frame(minHeight: 48)
                    .background(CoachPalette.ai.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                Text(intelligence.analysis.status)
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("positioningAnalysisStatus")
                Text(acceptedPlan == nil ? "Displayed positions: INSTANT GUIDE" : "Displayed positions: AI SUGGESTIONS")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(acceptedPlan == nil ? CoachPalette.lime : CoachPalette.ai)
                Text("AI may be tactically wrong even after these checks. Review with your coach. No cloud fallback.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .coachCard()
    }

    @ViewBuilder private var selectedPlayerControls: some View {
        switch sceneEditTarget {
        case .ball:
            EmptyView()
        case .teammate(let role):
            if let index = teammates.firstIndex(where: { $0.role == role }) {
                coordinateControls(depth: $teammates[index].point.depth, width: $teammates[index].point.width, label: "Teammate \(role.rawValue)")
            }
        case .opponent(let role):
            if let index = opponents.firstIndex(where: { $0.role == role }) {
                coordinateControls(depth: $opponents[index].point.depth, width: $opponents[index].point.width, label: "Opponent \(role.rawValue)")
            }
        }
    }

    private func coordinateControls(depth: Binding<Double>, width: Binding<Double>, label: String) -> some View {
        DisclosureGroup("Selected player controls") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Distance from own goal").font(.caption)
                Slider(value: depth, in: 0...1, onEditingChanged: { sceneEditing = $0 }) {
                    Text("\(label) distance from own goal")
                }
                Text("Left to right").font(.caption)
                Slider(value: width, in: 0...1, onEditingChanged: { sceneEditing = $0 }) {
                    Text("\(label) left to right")
                }
            }
            .foregroundStyle(CoachPalette.muted)
            .padding(.top, 12)
        }
        .font(.caption)
    }

    private func moveSceneTarget(_ target: SceneEditTarget, _ point: FieldPoint) {
        switch target {
        case .ball:
            ball = point.bounded
        case .teammate(let role):
            guard let index = teammates.firstIndex(where: { $0.role == role }) else {
                intelligence.cancel(message: "The selected teammate is missing. Showing the instant guide.")
                return
            }
            teammates[index].point = point.bounded
        case .opponent(let role):
            guard let index = opponents.firstIndex(where: { $0.role == role }) else {
                intelligence.cancel(message: "The selected opponent is missing. Showing the instant guide.")
                return
            }
            opponents[index].point = point.bounded
        }
    }

    private func analyzePositions(debounced: Bool = false) {
        guard aiPositioning, scenePhase == .active else { return }
        invalidateExplanation()
        intelligence.analyze(scene, debounced: debounced)
    }

    private func positioningAction() {
        if !aiPositioning {
            aiPositioning = true
        } else if intelligence.analysis.isBusy {
            intelligence.cancel(message: "Analysis cancelled. Showing the instant guide.")
        } else {
            analyzePositions()
        }
    }

    private var pitchSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup {
                VStack(spacing: 14) {
                    Toggle("Position glow", isOn: $showHeat)
                    Toggle("Goal-side guide", isOn: $showGuides)
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
                    Slider(value: $ball.depth, in: 0...1, onEditingChanged: { sceneEditing = $0 }) { Text("Ball distance from your goal") }
                    Text("Left to right").font(.caption).foregroundStyle(CoachPalette.muted)
                    Slider(value: $ball.width, in: 0...1, onEditingChanged: { sceneEditing = $0 }) { Text("Ball left to right") }
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
        .fixedSize(horizontal: false, vertical: true)
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
            return !geometry.reservedRegions(
                kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed
            ).isEmpty
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .padding(typeSize.isAccessibilitySize ? 14 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent ? CoachPalette.lime.opacity(0.055) : CoachPalette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(
                accent ? CoachPalette.lime.opacity(contrast == .increased ? 0.55 : 0.2) :
                    .white.opacity(contrast == .increased ? 0.25 : 0.065)
            ))
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

#Preview("Small phone", traits: .fixedLayout(width: 320, height: 568)) {
    CoachView()
}

#Preview("Phone landscape", traits: .fixedLayout(width: 667, height: 320)) {
    CoachView()
}

#Preview("Narrow iPad window", traits: .fixedLayout(width: 375, height: 1000)) {
    CoachView()
}

#Preview("Accessibility text", traits: .fixedLayout(width: 390, height: 800)) {
    CoachView().environment(\.dynamicTypeSize, .accessibility3)
}
