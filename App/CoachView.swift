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
    @State private var playbook = PlaybookStore()
    @State private var speech = SpeechCoach()
    @State private var showingPlaybook = false
    @State private var showingYouthSetup = false
    @State private var frames: [PlayFrame] = []
    @State private var selectedStep = 0
    @State private var isPlaying = false
    @State private var playbackID: UUID?
    @State private var playbackTask: Task<Void, Never>?
    @State private var showSavedSetup = false
    @State private var practice: PracticeRound?
    @State private var practiceScenario = 0
    @State private var practiceAttempts = 0
    @State private var practiceHits = 0
    @State private var workbenchNotice: String?
    @State private var workbenchError: String?
    @State private var navigation = ControlNavigation()
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
    private var recommendation: Recommendation { practice?.target ?? guidance(for: position) }
    private var effectiveEditTarget: SceneEditTarget {
        practice != nil ? .practice : (aiPositioning || showSavedSetup) ? sceneEditTarget : .ball
    }
    private var snapshot: BoardSnapshot {
        BoardSnapshot(scene: scene, position: position, comparison: comparison, comparing: comparing,
                      showHeat: showHeat, showGuides: showGuides, routes: routeDrawing.routes)
    }
    private var presentation: BoardPresentation {
        BoardPresentation(board: snapshot, advice: displayedAdvice, showPlayers: practice == nil && (aiPositioning || showSavedSetup),
                          aiSuggested: acceptedPlan != nil, practice: practice, preview: routeDrawing.preview)
    }
    private var displayedAdvice: [PlayerAdvice] {
        if let practice {
            return practice.revealed ? [PlayerAdvice(role: practice.role, point: practice.target.point, reason: practice.target.cue)] : []
        }
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
            let duo = proxy.hasDuoDisplay
            let layout = proxy.coachingLayout(largeText: typeSize.isAccessibilitySize)
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
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                brand
                                sectionEyebrow(layout.mode == .tabletop ? "TOUCHLINE CONTROLS" :
                                                layout.usesDuoControls ? "DUO COACHING DESK" : "THE COACH'S VIEW")
                                coachingControls(layout: layout)
                            }
                            .padding(layout.controlPanelPadding)
                        }
                        .onChange(of: navigation.revision) { reader.scrollTo(navigation.anchor, anchor: .top) }
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
        .background(ExternalFieldAccessory().allowsHitTesting(false))
        .onChange(of: presentation, initial: true) { FieldPresentation.shared.board = presentation }
        .task { await playbook.load() }
        .sheet(isPresented: $showingPlaybook) {
            PlaybookView(store: playbook, current: snapshot, frames: frames, onLoad: loadPlay)
        }
        .sheet(isPresented: $showingYouthSetup) { YouthSetupView(store: playbook, board: snapshot) }
        .onChange(of: scene) {
            guard !isPlaying else { return }
            routeDrawing.cancelStroke()
            speech.stop()
            invalidateExplanation()
            intelligence.cancel(message: aiPositioning ? "Scene changed. Showing the instant guide." : "Instant guide active.")
            if aiPositioning, autoAnalyze, !sceneEditing { analyzePositions(debounced: true) }
            if practice != nil { practice = PracticeRound(ball: ball, role: position) }
        }
        .onChange(of: sceneEditing) {
            if !sceneEditing, aiPositioning, autoAnalyze { analyzePositions(debounced: true) }
        }
        .onChange(of: aiPositioning) {
            intelligence.cancel()
            invalidateExplanation()
            routeDrawing.cancelStroke()
            if practice != nil { practice = PracticeRound(ball: ball, role: position) }
            speech.stop()
            sceneEditTarget = .ball
            drawing = false
            if aiPositioning { navigation.reveal(.analysis); analyzePositions() }
        }
        .onChange(of: autoAnalyze) {
            if autoAnalyze, aiPositioning, !sceneEditing { analyzePositions(debounced: true) }
        }
        .onChange(of: sceneEditTarget) { drawing = false; routeDrawing.cancelStroke() }
        .onChange(of: acceptedPlan) { routeDrawing.cancelStroke(); invalidateExplanation(); speech.stop() }
        .onChange(of: position) {
            if comparison == position {
                comparison = Position.allCases.first { $0 != position } ?? .lb
            }
            routeDrawing.cancelStroke()
            speech.stop()
            if practice != nil { practice = PracticeRound(ball: ball, role: position) }
            invalidateExplanation()
        }
        .onChange(of: drawing) {
            routeDrawing.cancelStroke()
            if drawing { navigation.reveal(.routes) }
        }
        .onChange(of: routeStyle) { routeDrawing.cancelStroke() }
        .onChange(of: snapRoutes) { routeDrawing.cancelStroke() }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                routeDrawing.cancelStroke()
                invalidateExplanation()
                intelligence.cancel(message: "Analysis paused while the app is inactive. Showing the instant guide.")
                pauseSequence()
                speech.stop()
            } else if aiPositioning, autoAnalyze {
                analyzePositions(debounced: true)
            }
        }
        .onDisappear { invalidateExplanation(); intelligence.cancel(); pauseSequence(); speech.stop() }
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
            .disabled(isPlaying)

            Button { drawing.toggle() } label: {
                Label(drawing ? "Done drawing" : "Draw route", systemImage: drawing ? "checkmark" : "pencil.tip.crop.circle")
            }
            .tint(drawing ? CoachPalette.lime : CoachPalette.muted)
            .accessibilityLabel(drawing ? "Done drawing" : "Draw route")
            .accessibilityValue(drawing ? "Drawing routes" : "Moving players")
            .accessibilityIdentifier("coach.toolbar.draw")
            .disabled(practice != nil || isPlaying)

            Button(action: positioningAction) {
                Label(intelligence.analysis.isBusy ? "Cancel analysis" : "Analyze positions",
                      systemImage: intelligence.analysis.isBusy ? "stop.circle" : "sparkles")
            }
            .disabled(isGenerating || practice != nil || isPlaying)
            .accessibilityHint("Enables AI Positioning if it is off.")
            .accessibilityIdentifier("coach.toolbar.analyze")

            Menu {
                Section("Library & teams") {
                    Button("Open playbook", systemImage: "books.vertical", action: openPlaybook)
                    Button("Kids & smaller teams", systemImage: "figure.child", action: openYouthSetup)
                    Button("Save current setup", systemImage: "bookmark", action: quickSave)
                        .disabled(playbook.busy || !playbook.loaded || !playbook.writable || practice != nil || isPlaying)
                    Button("Capture sequence step", systemImage: "plus.rectangle.on.rectangle", action: captureStep)
                        .disabled(practice != nil || isPlaying || frames.count >= 24)
                }
                Section("Coaching session") {
                    Button(practice == nil ? "Practice positioning" : "End practice", systemImage: "scope", action: togglePractice)
                        .disabled(isPlaying)
                    Button(speech.speaking ? "Stop spoken coaching" : "Speak coaching cue", systemImage: "speaker.wave.2", action: speakCue)
                        .disabled(isPlaying || (practice != nil && practice?.revealed == false))
                    if isPlaying { Button("Pause sequence", systemImage: "pause", action: pauseSequence) }
                    Button("Reset ball", systemImage: "arrow.counterclockwise", action: resetBallPosition)
                        .disabled(isPlaying)
                }
                Section("Routes") {
                    Button("Undo route", systemImage: "arrow.uturn.backward") { routeDrawing.undo() }
                        .disabled(!routeDrawing.canUndo || practice != nil || isPlaying)
                    Button("Redo route", systemImage: "arrow.uturn.forward") { routeDrawing.redo() }
                        .disabled(!routeDrawing.canRedo || practice != nil || isPlaying)
                }
                Section("Display") {
                    Button("Presentation & TV settings", systemImage: "tv") { navigation.reveal(.presentation) }
                    Toggle("Position glow", isOn: $showHeat)
                    Toggle("Goal-side guide", isOn: $showGuides)
                }
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
            showHeat: showHeat && (practice == nil || practice?.revealed == true),
            showGuides: showGuides && (practice == nil || practice?.revealed == true),
            drawing: drawing, routeStyle: routeStyle, snapRoutes: snapRoutes, horizontal: horizontal,
            recommendation: recommendation, suggestions: displayedAdvice,
            currentTeammates: practice == nil && (aiPositioning || showSavedSetup) ? teammates : [],
            opponents: practice == nil && (aiPositioning || showSavedSetup) ? opponents : [],
            aiSuggested: acceptedPlan != nil, editTarget: effectiveEditTarget,
            onMoveTarget: moveSceneTarget, onEditingChanged: { sceneEditing = $0 }, practice: practice
        )
        .allowsHitTesting(!isPlaying && practice?.revealed != true)
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
                Text(practice != nil ? (practice?.revealed == true ? "PRACTICE · REVEALED" : "PRACTICE · PLACE YOUR PLAYER") :
                        drawing ? "DRAW ROUTE  ·  \(routeStyle.rawValue.uppercased())" :
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
        return ScrollViewReader { reader in
            ScrollView {
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
                    rolePicker.disabled(isPlaying)
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
                            .id("coach.pitch")
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
            .onChange(of: navigation.revision) { reader.scrollTo(navigation.compactAnchor, anchor: .top) }
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
        speech.stop()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            ball = FieldPoint(depth: 0.65, width: 0.35)
        }
        if practice != nil { practice = PracticeRound(ball: TacticalScene.initialBall, role: position) }
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
                sectionEyebrow("YOUR DEFENSIVE ROLE")
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
            WorkspacePicker(selection: Binding(get: { navigation.workspace }, set: { navigation.select($0) }),
                            symbol: { $0.symbol })
                .id("coach.workspace")
            Text(navigation.workspace.summary).font(.caption).foregroundStyle(CoachPalette.muted)
            sessionActivity
            sessionFeedback
            switch navigation.workspace {
            case .coach:
                if practice == nil { cueCard }
                sceneCard.disabled(isPlaying)
                ForEach(layout.controlSections.filter { includeRole || $0 != .role }, id: \.self) { section in
                    switch section {
                    case .role:
                        roleCard.disabled(isPlaying)
                    case .routes:
                        ExpandableToolGroup("Drawing & routes", systemImage: "pencil.tip.crop.circle",
                                            expanded: $navigation.routesExpanded) { routePanel }
                            .id("coach.routes").disabled(isPlaying || practice != nil)
                    case .ai:
                        ExpandableToolGroup("AI & explanations", systemImage: "sparkles",
                                            expanded: $navigation.analysisExpanded) {
                            aiPositioningPanel
                            if practice == nil { aiCard }
                        }
                        .id("coach.analysis").disabled(isPlaying || practice != nil)
                    }
                }
                if practice == nil { comparisonCard.disabled(isPlaying) }
                pitchSettings.disabled(isPlaying || practice != nil)
                audioControls
            case .plays:
                workbenchPanel.id("coach.library")
                youthPanel
                sequencePanel.id("coach.sequence")
            case .practice:
                practicePanel.id("coach.practice")
                if includeRole { roleCard.disabled(isPlaying) }
                VStack(alignment: .leading, spacing: 14) {
                    sectionEyebrow("TRY A DIFFERENT BALL SCENE")
                    scenarioButtons
                }.coachCard().disabled(isPlaying)
                if practice?.revealed == true { aiCard }
                audioControls
            case .present:
                PresenterControls().id("coach.presentation")
                if practice == nil { cueCard }
                audioControls
                if !frames.isEmpty {
                    Button("Open sequence controls", systemImage: "play.rectangle") { navigation.reveal(.sequence) }
                        .frame(minHeight: 44)
                }
            }
            Label("A teaching guide, not match-specific advice.", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
                .padding(.horizontal, 4).padding(.bottom, 12)
        }
    }

    private var scenarioButtons: some View {
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

    private var sceneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ball & team scene", systemImage: "slider.horizontal.3").font(.headline)
            scenarioButtons
            ballControls.disabled(practice != nil)
            if !aiPositioning {
                Toggle("Edit current players", isOn: $showSavedSetup).font(.subheadline)
                    .disabled(practice != nil)
            }
            if aiPositioning || showSavedSetup {
                Picker("Formation", selection: $formation) {
                    ForEach(DefensiveFormation.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(practice != nil)
                sceneTargetPicker.disabled(practice != nil)
                selectedPlayerControls.disabled(practice != nil)
                Text("Five-player defensive unit. White outlines are current players; red markers are opponents.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
            }
        }.coachCard()
    }

    @ViewBuilder private var sessionActivity: some View {
        if practice != nil, navigation.workspace != .practice {
            VStack(alignment: .leading, spacing: 10) {
                Label("Practice is active", systemImage: "scope").font(.subheadline.bold())
                Button("Open practice controls") { navigation.reveal(.practice) }.frame(minHeight: 44)
                Button("End practice", action: togglePractice).frame(minHeight: 44)
            }.coachCard()
        }
        if isPlaying, navigation.workspace != .plays {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sequence playing", systemImage: "play.fill").font(.subheadline.bold())
                Button("Open sequence controls") { navigation.reveal(.sequence) }.frame(minHeight: 44)
                Button("Pause sequence", action: pauseSequence).frame(minHeight: 44)
            }.coachCard()
        }
        if drawing, navigation.workspace != .coach {
            VStack(alignment: .leading, spacing: 10) {
                Label("Drawing is active", systemImage: "pencil.tip.crop.circle").font(.subheadline.bold())
                Button("Open route tools") { navigation.reveal(.routes) }.frame(minHeight: 44)
                Button("Done drawing") { drawing = false }.frame(minHeight: 44)
            }.coachCard()
        }
        if aiPositioning {
            Label(intelligence.analysis.isBusy ? "AI analysis running" : "AI positioning enabled · experimental",
                  systemImage: "sparkles").font(.caption).foregroundStyle(CoachPalette.ai)
            if !intelligence.analysis.isBusy {
                Text(intelligence.analysis.status).font(.caption).foregroundStyle(CoachPalette.muted)
            }
        }
    }

    @ViewBuilder private var sessionFeedback: some View {
        if playbook.busy { ProgressView("Updating local playbook...").font(.caption) }
        if let message = workbenchNotice { Text(message).font(.caption).foregroundStyle(CoachPalette.muted) }
        ForEach(Array([workbenchError, playbook.error, speech.error, message].compactMap { $0 }.enumerated()), id: \.offset) { _, message in
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audioControls: some View {
        Button(action: speakCue) {
            Label(speech.speaking ? "Stop spoken coaching" : "Speak coaching cue", systemImage: "speaker.wave.2")
                .frame(minHeight: 44)
        }
        .font(.subheadline).disabled(isPlaying || (practice != nil && practice?.revealed == false))
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

    private var previousStepButton: some View {
        Button { jumpToStep(selectedStep - 1) } label: { Image(systemName: "backward.end").frame(width: 44, height: 44) }
            .disabled(selectedStep <= 0).accessibilityLabel("Previous sequence step")
    }

    private var nextStepButton: some View {
        Button { jumpToStep(selectedStep + 1) } label: { Image(systemName: "forward.end").frame(width: 44, height: 44) }
            .disabled(selectedStep >= frames.count - 1).accessibilityLabel("Next sequence step")
    }

    private var sequencePlayButton: some View {
        Button(action: toggleSequence) {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill").frame(minHeight: 44)
        }.disabled(frames.count < 2)
    }

    private var youthPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kids & smaller teams", systemImage: "figure.child").font(.headline)
            Text("3v3, 4v4, 5v5, 7v7 and 9v9 starting shapes, smaller reference pitches and editable full teams.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            Button("Choose team size", systemImage: "person.3", action: openYouthSetup).frame(minHeight: 44)
            Text("The main instant/AI guide remains a five-role defensive teaching unit on a full-size pitch; use the youth board for smaller teams.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }.coachCard()
    }

    private func openYouthSetup() {
        pauseSequence()
        speech.stop()
        navigation.reveal(.playbook)
        showingYouthSetup = true
    }

    private var workbenchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your playbook", systemImage: "books.vertical")
                .font(.system(.headline, design: .rounded))
            Text("\(playbook.plays.count) saved plays · \(frames.count) sequence steps")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            ViewThatFits(in: .horizontal) {
                HStack { libraryButton; saveButton }
                VStack(alignment: .leading) { libraryButton; saveButton }
            }
            Text("Local-only playbook. Shared files include your notes and captured steps.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }
        .coachCard()
    }

    private var libraryButton: some View {
        Button(action: openPlaybook) { Label("Playbook", systemImage: "books.vertical").frame(minHeight: 44) }
            .buttonStyle(.borderedProminent).tint(CoachPalette.lime).foregroundStyle(CoachPalette.ink)
    }

    private var saveButton: some View {
        Button(action: quickSave) { Label("Quick save", systemImage: "bookmark").frame(minHeight: 44) }
            .buttonStyle(.bordered)
            .disabled(!playbook.loaded || playbook.busy || !playbook.writable || practice != nil || isPlaying)
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your turn", systemImage: "scope").font(.headline)
            if let round = practice {
                Text("Place your \(round.role.label.lowercased()) by dragging on the pitch.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if round.revealed, let distance = round.distanceMeters {
                    Label(round.insideZone ? "Inside the practice zone" : "Compare your position with the guide",
                          systemImage: round.insideZone ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                        .foregroundStyle(round.insideZone ? CoachPalette.lime : CoachPalette.blue)
                    Text("\(Int(distance.rounded())) m from this guide's reference. The zone has an 8 m radius; it is not the only reasonable answer.")
                        .font(.caption).foregroundStyle(CoachPalette.muted)
                    Text(round.target.cue).font(.subheadline)
                    Button("Next scenario", systemImage: "arrow.right", action: nextPractice).frame(minHeight: 44)
                } else {
                    Text(round.guess == nil ? "The answer is hidden. Place your player, then check." : "Your player is placed. Ready to reveal the guide?")
                        .font(.caption).foregroundStyle(CoachPalette.muted)
                    Button("Check position", systemImage: "checkmark", action: checkPractice)
                        .frame(minHeight: 44).disabled(round.guess == nil)
                    coordinateControls(depth: practiceCoordinate(\.depth), width: practiceCoordinate(\.width), label: "Your player")
                }
                Text("This session: \(practiceHits) in-zone / \(practiceAttempts) checked.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                Button("End practice", action: togglePractice).frame(minHeight: 44)
            } else {
                Text("Hide the answer, place your player, and reveal a generous teaching zone—not a pixel-perfect grade.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                Button("Start positioning practice", systemImage: "play.circle", action: togglePractice)
                    .frame(minHeight: 44).disabled(isPlaying)
            }
        }
        .coachCard()
    }

    private var sequencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Captured board sequence", systemImage: "play.rectangle.on.rectangle").font(.headline)
            Text("Capture the main board at each decision, then save it to keep the steps. For full-team animations, open the playbook designer.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            Button("Capture step \(frames.count + 1)", systemImage: "plus.rectangle.on.rectangle", action: captureStep)
                .frame(minHeight: 44).disabled(frames.count >= 24 || practice != nil || isPlaying)
            if !frames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(frames.enumerated()), id: \.element.id) { index, _ in
                            Button { jumpToStep(index) } label: {
                                Text("\(index + 1)").font(.subheadline.bold()).frame(width: 44, height: 44)
                                    .foregroundStyle(index == selectedStep ? CoachPalette.ink : .white)
                                    .background(index == selectedStep ? CoachPalette.lime : .white.opacity(0.08), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Load sequence step \(index + 1)")
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { previousStepButton; sequencePlayButton; nextStepButton }
                    VStack(alignment: .leading) {
                        sequencePlayButton
                        HStack { previousStepButton; nextStepButton }
                    }
                }
                Text("Selected step \(selectedStep + 1) of \(frames.count) · \(Int(PlaySequence.duration(frames).rounded())) s sequence")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                if frames.indices.contains(selectedStep) {
                    Slider(value: stepDurationBinding(selectedStep), in: 1...10, step: 0.5) {
                        Text("Step hold duration")
                    }
                    .disabled(isPlaying)
                    Text("Hold this step \(frames[selectedStep].duration, specifier: "%.1f") s before the next.")
                        .font(.caption2).foregroundStyle(CoachPalette.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack { replaceStepButton; removeStepButton }
                        VStack(alignment: .leading) { replaceStepButton; removeStepButton }
                    }
                }
            }
            Text("Up to 24 steps. Playback pauses when the app becomes inactive.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }
        .coachCard()
    }

    private var replaceStepButton: some View {
        Button("Replace selected step", systemImage: "arrow.triangle.2.circlepath") {
            do {
                try snapshot.validate()
                guard frames.indices.contains(selectedStep) else { throw WorkbenchError.invalid("Select a sequence step first.") }
                frames[selectedStep].board = snapshot
                workbenchNotice = "Selected step updated."
                workbenchError = nil
            } catch { workbenchError = error.localizedDescription }
        }

        .font(.caption).frame(minHeight: 44).disabled(isPlaying || practice != nil)
    }

    private var removeStepButton: some View {
        Button("Remove step", systemImage: "trash", role: .destructive) {
            guard frames.indices.contains(selectedStep) else { return }
            pauseSequence()
            frames.remove(at: selectedStep)
            selectedStep = max(0, min(selectedStep, frames.count - 1))
        }
        .font(.caption).frame(minHeight: 44).disabled(isPlaying)
    }

    private func stepDurationBinding(_ index: Int) -> Binding<Double> {
        Binding(get: { frames.indices.contains(index) ? frames[index].duration : 2 }, set: { value in
            guard frames.indices.contains(index) else { workbenchError = "Select a sequence step first."; return }
            frames[index].duration = value
        })
    }

    private func openPlaybook() {
        pauseSequence()
        speech.stop()
        navigation.reveal(.playbook)
        showingPlaybook = true
    }

    private func quickSave() {
        navigation.reveal(.playbook)
        do {
            try snapshot.validate()
            let play = SavedPlay(title: "\(position.rawValue) - \(formation.rawValue) setup", board: snapshot, frames: frames)
            workbenchError = nil
            workbenchNotice = nil
            Task {
                if await playbook.save(play) {
                    workbenchNotice = "Setup saved. Open Playbook to add notes, favorite or share it."
                    workbenchError = nil
                }
            }
        } catch { workbenchError = error.localizedDescription }
    }

    private func loadPlay(_ play: SavedPlay) {
        do {
            try play.validate()
            pauseSequence()
            try applyBoard(play.board)
            frames = play.frames
            selectedStep = 0
            navigation.reveal(frames.isEmpty ? .coach : .sequence)
            workbenchNotice = "Loaded \(play.title). AI responses are regenerated, not treated as saved authority."
            workbenchError = nil
        } catch { workbenchError = "Could not load play: \(error.localizedDescription)" }
    }

    private func applyBoard(_ board: BoardSnapshot) throws {
        try board.validate()
        try routeDrawing.restore(board.routes)
        speech.stop()
        invalidateExplanation()
        intelligence.cancel()
        aiPositioning = false
        drawing = false
        practice = nil
        sceneEditTarget = .ball
        ball = board.scene.ball
        formation = board.scene.formation
        teammates = board.scene.teammates
        opponents = board.scene.opponents
        position = board.position
        comparison = board.comparison
        comparing = board.comparing
        showHeat = board.showHeat
        showGuides = board.showGuides
        showSavedSetup = true
    }

    private func captureStep() {
        navigation.reveal(.sequence)
        do {
            guard frames.count < 24 else { throw WorkbenchError.invalid("A sequence supports up to 24 steps.") }
            try snapshot.validate()
            frames.append(PlayFrame(board: snapshot))
            selectedStep = frames.count - 1
            workbenchNotice = "Step \(frames.count) captured. Save the play to keep the sequence."
            workbenchError = nil
        } catch { workbenchError = error.localizedDescription }
    }

    private func jumpToStep(_ index: Int) {
        guard frames.indices.contains(index) else { return }
        pauseSequence()
        do { try applyBoard(frames[index].board); selectedStep = index }
        catch { workbenchError = "Could not load step: \(error.localizedDescription)" }
    }

    private func toggleSequence() {
        if isPlaying { pauseSequence(); return }
        guard frames.count >= 2 else { workbenchError = "Capture at least two steps."; return }
        pauseSequence()
        speech.stop()
        if selectedStep >= frames.count - 1 { selectedStep = 0 }
        do { try applyBoard(frames[selectedStep].board) }
        catch { workbenchError = error.localizedDescription; return }
        let run = UUID()
        playbackID = run
        isPlaying = true
        playbackTask = Task { @MainActor in
            do {
                while selectedStep < frames.count - 1 {
                    let hold = frames[selectedStep].duration
                    try await Task.sleep(for: .seconds(hold))
                    try Task.checkCancellation()
                    guard playbackID == run else { return }
                    let next = selectedStep + 1
                    guard frames.indices.contains(next) else { throw WorkbenchError.invalid("The sequence changed during playback.") }
                    try withAnimation(reduceMotion ? nil : .linear(duration: min(0.7, hold / 2))) {
                        try applyBoard(frames[next].board)
                        selectedStep = next
                    }
                }
                guard playbackID == run else { return }
                isPlaying = false
                playbackID = nil
                workbenchNotice = "Sequence complete."
            } catch is CancellationError {
                // A pause or scene transition owns the new playback state.
            } catch {
                guard playbackID == run else { return }
                pauseSequence()
                workbenchError = "Playback stopped: \(error.localizedDescription)"
            }
        }
    }

    private func pauseSequence() {
        playbackID = nil
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func togglePractice() {
        navigation.reveal(.practice)
        pauseSequence()
        speech.stop()
        invalidateExplanation()
        intelligence.cancel()
        drawing = false
        aiPositioning = false
        routeDrawing.cancelStroke()
        if practice == nil { practice = PracticeRound(ball: ball, role: position) }
        else { practice = nil }
    }

    private func checkPractice() {
        guard var round = practice, !round.revealed else { return }
        do {
            try round.reveal()
            practice = round
            practiceAttempts += 1
            if round.insideZone { practiceHits += 1 }
        } catch { workbenchError = error.localizedDescription }
    }

    private func nextPractice() {
        let scenarios = FieldScenario.allCases
        let current = scenarios.firstIndex { $0.point == ball } ?? practiceScenario
        practiceScenario = (current + 1) % scenarios.count
        ball = scenarios[practiceScenario].point
        practice = PracticeRound(ball: ball, role: position)
    }

    private func speakCue() {
        if speech.speaking { speech.stop() }
        else if practice == nil || practice?.revealed == true { speech.speak(recommendation.cue) }
    }

    private func practiceCoordinate(_ keyPath: WritableKeyPath<FieldPoint, Double>) -> Binding<Double> {
        Binding(get: { (practice?.guess ?? FieldPoint(depth: 0.5, width: 0.5))[keyPath: keyPath] }, set: { value in
            guard var round = practice, !round.revealed else { return }
            var point = round.guess ?? FieldPoint(depth: 0.5, width: 0.5)
            point[keyPath: keyPath] = value
            round.place(point)
            practice = round
        })
    }

    private var sceneTargetPicker: some View {
        Picker("Move on pitch", selection: $sceneEditTarget) {
            Text("Move ball").tag(SceneEditTarget.ball)
            ForEach(Position.allCases) { Text("Move teammate \($0.rawValue)").tag(SceneEditTarget.teammate($0)) }
            ForEach(OpponentRole.allCases) { Text("Move opponent \($0.rawValue)").tag(SceneEditTarget.opponent($0)) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
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
            Text("An on-device explanation of your coaching cue. AI processing stays on your device.")
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
                if let plan = acceptedPlan {
                    Button("Use suggestions as editable setup", systemImage: "checkmark.rectangle") {
                        teammates = plan.players.map { PlayerPlacement(role: $0.role, point: $0.point) }
                        showSavedSetup = true
                        aiPositioning = false
                        workbenchNotice = "AI preview copied to current players. You can now edit, capture or save it."
                    }
                    .frame(minHeight: 44)
                    Text("Ends AI preview; these become your editable positions, not a certified tactical answer.")
                        .font(.caption2).foregroundStyle(CoachPalette.muted)
                }
                Text("AI may be tactically wrong even after these checks. Review with your coach. No cloud fallback.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .coachCard()
    }

    @ViewBuilder private var selectedPlayerControls: some View {
        switch sceneEditTarget {
        case .ball, .practice:
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
        case .practice:
            practice?.place(point)
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
        navigation.reveal(.analysis)
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
        }
        .coachCard()
    }

    private var ballControls: some View {
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

extension GeometryProxy {
    var hasDuoDisplay: Bool {
        if #available(iOS 27.1, *) {
            return !reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed).isEmpty
        }
        return false
    }

    func coachingLayout(largeText: Bool) -> CoachingLayout {
        let division: CGRect?
        if #available(iOS 27.1, *) {
            division = reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).first?.frame
        } else { division = nil }
        return CoachingLayout.resolve(size: size, division: division, largeText: largeText, duoDisplay: hasDuoDisplay)
    }
}

struct CoachCard: ViewModifier {
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

extension View {
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
