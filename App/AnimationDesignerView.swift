import SwiftUI
import OSLog

struct AnimationDesignerView: View {
    let store: PlaybookStore
    let initial: SavedPlay
    @State private var draft: AnimationDraft?
    @State private var baseline: TacticalAnimation?
    @State private var title: String
    @State private var notes: String
    @State private var favorite: Bool
    @State private var undo: [AnimationDraft] = []
    @State private var redo: [AnimationDraft] = []
    @State private var gestureStart: AnimationDraft?
    @State private var error: String?
    @State private var loaded = false
    @State private var saving = false
    @State private var discard = false
    @State private var removePlayer = false
    @State private var removePhase = false
    @State private var showPaths = true
    @State private var preview: SavedPlay?
    @State private var audienceOwner = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "Designer")

    init(store: PlaybookStore, initial: SavedPlay) {
        self.store = store
        self.initial = initial
        _title = State(initialValue: initial.title)
        _notes = State(initialValue: initial.notes)
        _favorite = State(initialValue: initial.favorite)
    }

    private var busy: Bool { saving || store.busy }
    private var dirty: Bool {
        draft?.animation != baseline || title != initial.title || notes != initial.notes || favorite != initial.favorite
    }
    private var validation: String? {
        do { _ = try candidate(); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = proxy.coachingLayout(largeText: typeSize.isAccessibilitySize)
                ZStack(alignment: .topLeading) {
                    if let coach = layout.coachPane {
                        field.frame(width: layout.pitchPane.width, height: layout.pitchPane.height)
                            .position(x: layout.pitchPane.midX, y: layout.pitchPane.midY)
                        ScrollView { controls.padding(layout.controlPanelPadding) }
                            .frame(width: coach.width, height: coach.height)
                            .position(x: coach.midX, y: coach.midY)
                    } else {
                        ScrollView {
                            VStack(spacing: 18) {
                                field.frame(height: min(460, max(180, layout.pitchPane.height * 0.56)))
                                controls
                            }.padding(16)
                        }
                        .frame(width: layout.pitchPane.width, height: layout.pitchPane.height)
                        .position(x: layout.pitchPane.midX, y: layout.pitchPane.midY)
                    }
                }
            }
            .background(CoachPalette.ink)
            .navigationTitle("Play designer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbar(.visible, for: .bottomBar)
            .toolbarBackground(CoachPalette.ink, for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
        }
        .preferredColorScheme(.dark).tint(CoachPalette.lime)
        .background(ExternalFieldAccessory().allowsHitTesting(false))
        .interactiveDismissDisabled(dirty || busy)
        .sheet(item: $preview) { AnimationPlayerView(play: $0) }
        .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        .confirmationDialog("Remove this player from every phase?", isPresented: $removePlayer, titleVisibility: .visible) {
            Button("Remove player", role: .destructive) { edit { try $0.removeSelectedPlayer() } }
        }
        .confirmationDialog("Remove this phase and shorten the timeline?", isPresented: $removePhase, titleVisibility: .visible) {
            Button("Remove phase", role: .destructive) { edit { try $0.removePhase() } }
        }
        .onAppear(perform: load)
        .onDisappear { finishGesture(); FieldPresentation.shared.finishAnimation(owner: audienceOwner) }
        .onChange(of: preview?.id) { if preview == nil { publish() } }
        .onChange(of: scenePhase) { if scenePhase != .active { finishGesture() } }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { finishGesture(); if dirty { discard = true } else { dismiss() } }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(saving ? "Saving..." : "Save", action: save).disabled(busy || validation != nil || !store.writable)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { restore(undoing: true) } label: { Label("Undo edit", systemImage: "arrow.uturn.backward") }
                .disabled(undo.isEmpty || busy)
            Button { restore(undoing: false) } label: { Label("Redo edit", systemImage: "arrow.uturn.forward") }
                .disabled(redo.isEmpty || busy)
            Button(action: showPreview) { Label("Preview animation", systemImage: "play.fill") }
                .disabled(validation != nil || busy)
            Menu {
                Button("Capture next phase", systemImage: "plus.rectangle.on.rectangle", action: capturePhase)
                    .disabled(!canInsert)
                Button("Add lime player") { edit { try $0.addPlayer(team: .home) } }
                    .disabled((draft?.frame.players.count ?? 22) >= 22)
                Button("Add red player") { edit { try $0.addPlayer(team: .away) } }
                    .disabled((draft?.frame.players.count ?? 22) >= 22)
                Toggle("Movement guides", isOn: $showPaths)
            } label: { Label("Designer actions", systemImage: "ellipsis") }
            .disabled(draft == nil || busy)
        }
    }

    @ViewBuilder private var field: some View {
        if let draft {
            AnimationEditingPitch(
                frame: draft.frame, previous: showPaths ? draft.previousFrame : nil,
                phase: draft.phase, target: draft.target,
                onBegin: beginGesture, onEnd: finishGesture,
                onSelect: { select($0, gesture: true) },
                onMove: { target, point in
                    edit(record: false) { try $0.select(target); try $0.move(to: point) }
                }
            )
            .allowsHitTesting(!busy)
        } else {
            ContentUnavailableView("Designer unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("MAKE IT YOUR PLAY", systemImage: "pencil.and.outline").font(.headline)
                Text("Set phase 1, select phase 2 and move players or the ball. Between phases, players run and the ball travels automatically. Capture more phases to add bends, passes and decisions.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                Text("Tap a marker to select it; drag it, or use the selected item's coordinate sliders. Dashed guides show movement into the current phase.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
            }.coachCard()
            if let draft {
                phasePanel(draft)
                selectionPanel(draft)
                metadataPanel
            }
            if let message = error {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if let message = store.error {
                Label(message, systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
            if let validation {
                Label(validation, systemImage: "info.circle").font(.caption).foregroundStyle(CoachPalette.muted)
            }
            Button(action: showPreview) { Label("Preview this play", systemImage: "play.rectangle").frame(minHeight: 44) }
                .buttonStyle(.borderedProminent).foregroundStyle(CoachPalette.ink)
                .disabled(validation != nil || busy)
            PresenterControls()
            Text("Save to keep your work. Undo/redo covers field edits, roster, timing, category and phase cues. Name and notes use normal text editing. A custom play is an illustration, not a verified tactical or rights assessment.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }
        .disabled(busy)
    }

    private var canInsert: Bool {
        guard let draft else { return false }
        return draft.animation.frames.count < 24 && draft.animation.duration <= 119.75
    }

    private func phasePanel(_ draft: AnimationDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Phase \(draft.phase + 1) of \(draft.animation.frames.count)", systemImage: "rectangle.stack").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(draft.animation.frames.indices, id: \.self) { index in
                        Button { finishGesture(); edit(record: false) { try $0.selectPhase(index) } } label: {
                            Text("\(index + 1)").font(.headline).frame(width: 44, height: 44)
                                .background(index == draft.phase ? CoachPalette.lime : .white.opacity(0.08), in: Circle())
                                .foregroundStyle(index == draft.phase ? CoachPalette.ink : .white)
                        }
                        .accessibilityLabel("Edit phase \(index + 1)")
                    }
                }
            }
            Button("Capture next phase", systemImage: "plus.rectangle.on.rectangle", action: capturePhase)
                .frame(minHeight: 44).disabled(!canInsert)
            if let seconds = draft.travelTime {
                Stepper(value: Binding(get: { self.draft?.travelTime ?? seconds },
                                       set: { seconds in edit { try $0.setTravelTime(seconds) } }),
                        in: 0.25...max(0.25, 120 - draft.animation.duration + seconds), step: 0.25) {
                    Text("\(seconds, specifier: "%.2f") seconds to next phase").font(.subheadline)
                }
            } else {
                Text("Final phase. Capture another to continue the play.").font(.caption).foregroundStyle(CoachPalette.muted)
            }
            TextField("Cue for movement out of this phase", text: Binding(
                get: { self.draft?.cue ?? "" }, set: { text in edit { $0.cue = text } }), axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5)
            Text("\(draft.cue.count)/400 cue characters · \(draft.animation.duration, specifier: "%.2f") seconds total")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
            Toggle("Show movement guides", isOn: $showPaths).font(.subheadline)
            Button("Remove phase", role: .destructive) { finishGesture(); removePhase = true }
                .frame(minHeight: 44).disabled(draft.animation.frames.count <= 2)
        }.coachCard()
    }

    private func selectionPanel(_ draft: AnimationDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Players and ball", systemImage: "person.3").font(.headline)
            Picker("Selected item", selection: Binding(get: { self.draft?.target ?? .ball }, set: { select($0) })) {
                Text("Ball").tag(AnimationEditTarget.ball)
                ForEach(draft.frame.players) { player in
                    Text("\(player.team == .home ? "Lime" : "Red") \(player.label)").tag(AnimationEditTarget.player(player.id))
                }
            }.pickerStyle(.menu)
            Text("Distance from own goal: \(Int((draft.selectedPoint.depth * 100).rounded()))%")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            Slider(value: coordinate(\.depth), in: 0...1, onEditingChanged: { $0 ? beginGesture() : finishGesture() }) {
                Text("Selected item distance from own goal")
            }
            Text("Left to right: \(Int((draft.selectedPoint.width * 100).rounded()))%")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            Slider(value: coordinate(\.width), in: 0...1, onEditingChanged: { $0 ? beginGesture() : finishGesture() }) {
                Text("Selected item left to right")
            }
            if draft.selectedPlayer != nil {
                TextField("Player label", text: Binding(get: { self.draft?.selectedPlayer?.label ?? "" },
                                                       set: { text in edit { try $0.editSelectedLabel(text) } }))
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Text("1 to 6 characters. Label changes apply to every phase.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                Button("Pass ball to this player", systemImage: "soccerball") { edit { try $0.passToSelectedPlayer() } }
                    .frame(minHeight: 44)
                Text("Sets this phase's ball position. Playback passes from the previous phase to this receiver.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                Button("Remove player from all phases", role: .destructive) { finishGesture(); removePlayer = true }
                    .frame(minHeight: 44).disabled(draft.frame.players.count <= 2)
            }
            Menu("Add a player", systemImage: "person.badge.plus") {
                Button("Lime team") { edit { try $0.addPlayer(team: .home) } }
                Button("Red team") { edit { try $0.addPlayer(team: .away) } }
            }
            .frame(minHeight: 44).disabled(draft.frame.players.count >= 22)
            Text("\(draft.frame.players.count)/22 players. Roster and labels stay consistent across all phases.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }.coachCard()
    }

    private var metadataPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Save to your playbook", systemImage: "bookmark").font(.headline)
            TextField("Play title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Category", text: Binding(get: { draft?.category ?? "" }, set: { text in edit { $0.category = text } }))
                .textFieldStyle(.roundedBorder)
            Text("Coaching notes").font(.subheadline)
            TextEditor(text: $notes).frame(minHeight: 120)
                .padding(6).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Text("\(title.count)/80 title · \(notes.count)/4000 notes").font(.caption2).foregroundStyle(CoachPalette.muted)
            Toggle("Favorite", isOn: $favorite)
            Text("Notes and editing controls are not part of the external field. Retained research references stay with customized patterns.")
                .font(.caption2).foregroundStyle(CoachPalette.muted)
        }.coachCard()
    }

    private func coordinate(_ keyPath: WritableKeyPath<FieldPoint, Double>) -> Binding<Double> {
        Binding(get: { (draft?.selectedPoint ?? FieldPoint(depth: 0.5, width: 0.5))[keyPath: keyPath] }, set: { value in
            guard var point = draft?.selectedPoint else { return }
            point[keyPath: keyPath] = value
            edit(record: gestureStart == nil) { try $0.move(to: point) }
        })
    }

    private func capturePhase() {
        edit { draft in
            let seconds = min(2, 120 - draft.animation.duration)
            try draft.insertPhase(duration: seconds)
        }
    }

    private func candidate() throws -> SavedPlay {
        guard let draft else { throw WorkbenchError.invalid("The animated play could not be loaded.") }
        var play = initial
        play.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        play.notes = notes
        play.favorite = favorite
        play.animation = draft.animation
        play.frames = []
        try play.validate()
        return play
    }

    private func load() {
        if !loaded {
            loaded = true
            do {
                guard let animation = initial.animation else { throw WorkbenchError.invalid("Choose an animated play to design.") }
                let draft = try AnimationDraft(animation)
                self.draft = draft
                baseline = draft.animation
            } catch { report(error) }
        }
        publish()
    }

    private func edit(record: Bool = true, _ operation: (inout AnimationDraft) throws -> Void) {
        if record { finishGesture() }
        guard let before = draft else { return }
        do {
            var next = before
            try operation(&next)
            guard next != before else { return }
            if record { pushUndo(before) }
            draft = next
            error = nil
            publish()
        } catch { report(error) }
    }

    private func select(_ target: AnimationEditTarget, gesture: Bool = false) {
        if !gesture { finishGesture() }
        edit(record: false) { try $0.select(target) }
    }

    private func beginGesture() {
        if gestureStart == nil { gestureStart = draft }
    }
    private func finishGesture() {
        if let start = gestureStart, start.animation != draft?.animation { pushUndo(start) }
        gestureStart = nil
    }
    private func pushUndo(_ before: AnimationDraft) {
        undo.append(before)
        if undo.count > 30 { undo.removeFirst() }
        redo = []
    }
    private func restore(undoing: Bool) {
        finishGesture()
        guard let current = draft else { return }
        if undoing, let previous = undo.popLast() { redo.append(current); draft = previous }
        else if !undoing, let next = redo.popLast() { undo.append(current); draft = next }
        error = nil
        publish()
    }
    private func publish() {
        guard let frame = draft?.frame, preview == nil else { return }
        FieldPresentation.shared.beginAnimation(owner: audienceOwner)
        FieldPresentation.shared.publish(frame, owner: audienceOwner)
    }
    private func showPreview() {
        finishGesture()
        do { preview = try candidate() }
        catch { report(error) }
    }
    private func save() {
        finishGesture()
        do {
            let play = try candidate()
            saving = true
            Task {
                let saved = await store.save(play)
                saving = false
                if saved { dismiss() }
            }
        } catch { report(error) }
    }
    private func report(_ problem: Error) {
        logger.error("Play design failed: \(String(describing: problem), privacy: .private)")
        error = problem.localizedDescription
    }
}

private struct AnimationEditingPitch: View {
    let frame: AnimationFrame
    let previous: AnimationFrame?
    let phase: Int
    let target: AnimationEditTarget
    let onBegin: () -> Void
    let onEnd: () -> Void
    let onSelect: (AnimationEditTarget) -> Void
    let onMove: (AnimationEditTarget, FieldPoint) -> Void
    @State private var active: DragContext?
    @State private var rejectedGesture = false
    @GestureState private var dragging = false

    private struct DragContext {
        let frame: CGRect
        let phase: Int
        let target: AnimationEditTarget
    }

    var body: some View {
        GeometryReader { proxy in
            let projection = PitchProjection(size: proxy.size, horizontal: proxy.size.width > proxy.size.height)
            let bounds = proxy.frame(in: .global)
            let usable = projection.isUsable && min(proxy.size.width, proxy.size.height) >= 160
            AnimationPitchView(frame: frame)
                .overlay {
                    if usable {
                        Canvas { context, _ in
                            if let previous {
                                arrow(from: previous.ball, to: frame.ball, color: .white, context: &context, projection: projection)
                                for player in frame.players {
                                    if let start = previous.players.first(where: { $0.id == player.id }) {
                                        arrow(from: start.point, to: player.point,
                                              color: player.team == .home ? CoachPalette.lime : CoachPalette.blue,
                                              context: &context, projection: projection)
                                    }
                                }
                            }
                            let point = projection.location(selectedPoint)
                            let radius: CGFloat = 26
                            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                                           with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, flag, _ in flag = true }
                    .onChanged { value in
                        guard !rejectedGesture else { return }
                        if active == nil {
                            guard usable, projection.interactionBounds.contains(value.startLocation) else { return }
                            let selection = nearest(to: value.startLocation, projection: projection) ?? target
                            active = DragContext(frame: bounds, phase: phase, target: selection)
                            onBegin()
                            onSelect(selection)
                        }
                        guard let active, active.frame == bounds, active.phase == phase,
                              hypot(value.translation.width, value.translation.height) >= 2 else { return }
                        onMove(active.target, projection.fieldPoint(value.location))
                    }
                    .onEnded { value in
                        if !rejectedGesture, let active, active.frame == bounds, active.phase == phase,
                           hypot(value.translation.width, value.translation.height) >= 2 {
                            onMove(active.target, projection.fieldPoint(value.location))
                        }
                        finish()
                        rejectedGesture = false
                    })
                .onChange(of: bounds) { invalidateGesture() }
                .onChange(of: phase) { invalidateGesture() }
                .onChange(of: frame.players.map(\.id)) { invalidateGesture() }
                .onChange(of: target) { if let active, active.target != target { invalidateGesture() } }
                .onChange(of: dragging) { if !dragging { finish(); rejectedGesture = false } }
                .onDisappear(perform: finish)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Editable animated soccer field")
                .accessibilityHint("Choose an item and use its coordinate sliders in Players and ball.")
        }
    }

    private var selectedPoint: FieldPoint {
        if case .player(let id) = target, let player = frame.players.first(where: { $0.id == id }) { return player.point }
        return frame.ball
    }
    private func nearest(to location: CGPoint, projection: PitchProjection) -> AnimationEditTarget? {
        let items: [(AnimationEditTarget, FieldPoint)] = [(.ball, frame.ball)] +
            frame.players.map { (.player($0.id), $0.point) }
        return items.map { item -> (AnimationEditTarget, CGFloat) in
            let point = projection.location(item.1)
            return (item.0, hypot(point.x - location.x, point.y - location.y))
        }.filter { $0.1 <= 26 }.min { $0.1 < $1.1 }?.0
    }
    private func finish() {
        if active != nil { active = nil; onEnd() }
    }
    private func invalidateGesture() {
        if dragging { rejectedGesture = true }
        finish()
    }
    private func arrow(from: FieldPoint, to: FieldPoint, color: Color, context: inout GraphicsContext, projection: PitchProjection) {
        let start = projection.location(from), end = projection.location(to)
        guard hypot(end.x - start.x, end.y - start.y) > 3 else { return }
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
        if let direction = RouteDrawing.arrowDirection(for: [from, to], projection: projection) {
            let angle = atan2(direction.dy, direction.dx)
            var tip = Path()
            tip.move(to: CGPoint(x: end.x - 9 * cos(angle - 0.5), y: end.y - 9 * sin(angle - 0.5)))
            tip.addLine(to: end)
            tip.addLine(to: CGPoint(x: end.x - 9 * cos(angle + 0.5), y: end.y - 9 * sin(angle + 0.5)))
            context.stroke(tip, with: .color(color.opacity(0.8)), lineWidth: 1.5)
        }
    }
}
