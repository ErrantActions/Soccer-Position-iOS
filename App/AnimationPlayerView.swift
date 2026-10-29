import SwiftUI
import Observation
import OSLog

@MainActor @Observable
final class AnimationPlayback {
    private(set) var frame: AnimationFrame?
    private(set) var elapsed: Double = 0
    private(set) var playing = false
    private(set) var error: String?
    private(set) var clip: TacticalAnimation?
    var speed: Double = 1
    var looping = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID: UUID?
    let owner = UUID()
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "Animation")

    func load(_ clip: TacticalAnimation) {
        close()
        self.clip = nil
        frame = nil
        elapsed = 0
        do {
            try clip.validate()
            self.clip = clip
            error = nil
            FieldPresentation.shared.beginAnimation(owner: owner)
            seek(to: 0)
        } catch { report(error) }
    }

    func seek(to time: Double, reducedMotion: Bool = false) {
        pause()
        guard let clip else { return }
        guard time.isFinite else { report(WorkbenchError.invalid("Animation time must be finite.")); return }
        FieldPresentation.shared.beginAnimation(owner: owner)
        elapsed = min(clip.duration, max(0, time))
        publish(clip.sampleValidated(at: elapsed, reducedMotion: reducedMotion))
    }

    func play(reducedMotion: Bool) {
        guard let clip else { return }
        pause()
        FieldPresentation.shared.beginAnimation(owner: owner)
        if elapsed >= clip.duration { elapsed = 0 }
        let run = UUID()
        runID = run
        playing = true
        task = Task { @MainActor in
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled, runID == run {
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch is CancellationError { return }
                catch { report(error); return }
                guard !Task.isCancelled, runID == run else { return }
                let now = clock.now
                let parts = previous.duration(to: now).components
                let delta = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
                previous = now
                elapsed += delta * speed
                if elapsed >= clip.duration {
                    publish(clip.sampleValidated(at: clip.duration, reducedMotion: reducedMotion))
                    if looping { elapsed.formTruncatingRemainder(dividingBy: clip.duration) }
                    else { elapsed = clip.duration; playing = false; runID = nil; return }
                }
                publish(clip.sampleValidated(at: elapsed, reducedMotion: reducedMotion))
            }
        }
    }

    func pause() {
        task?.cancel()
        task = nil
        runID = nil
        playing = false
    }

    func close() {
        pause()
        FieldPresentation.shared.finishAnimation(owner: owner)
    }

    private func publish(_ frame: AnimationFrame) {
        self.frame = frame
        FieldPresentation.shared.publish(frame, owner: owner, format: clip?.teamSetup?.format)
    }
    private func report(_ problem: Error) {
        pause()
        logger.error("Animated play failed: \(String(describing: problem), privacy: .private)")
        error = "The animated play could not be shown. \(problem.localizedDescription)"
    }
}

struct AnimationPlayerView: View {
    let play: SavedPlay
    @State private var playback = AnimationPlayback()
    @State private var speech = SpeechCoach()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

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
            .navigationTitle(play.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { jumpPhase(-1) } label: { Label("Previous phase", systemImage: "backward.end") }
                        .disabled(playback.clip == nil || playback.elapsed <= 0)
                    Button(action: togglePlayback) {
                        Label(playback.playing ? "Pause" : "Play", systemImage: playback.playing ? "pause.fill" : "play.fill")
                    }
                    .disabled(playback.clip == nil)
                    .accessibilityIdentifier("coach.animation.play")
                    Button { jumpPhase(1) } label: { Label("Next phase", systemImage: "forward.end") }
                        .disabled(playback.clip == nil || playback.elapsed >= (playback.clip?.duration ?? 0))
                    Menu {
                        Button("Restart") { playback.seek(to: 0, reducedMotion: reduceMotion) }
                        Toggle("Loop play", isOn: $playback.looping)
                        Picker("Playback speed", selection: $playback.speed) {
                            Text("0.5x").tag(0.5)
                            Text("1x").tag(1.0)
                            Text("2x").tag(2.0)
                        }
                    } label: { Label("Playback options", systemImage: "ellipsis") }
                }
            }
            .toolbar(.visible, for: .bottomBar)
            .toolbarBackground(CoachPalette.ink, for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
        }
        .preferredColorScheme(.dark).tint(CoachPalette.lime)
        .background(ExternalFieldAccessory().allowsHitTesting(false))
        .onAppear { if let clip = play.animation { playback.load(clip) } }
        .onDisappear { playback.close(); speech.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { playback.pause(); speech.stop() } }
        .onChange(of: reduceMotion) { playback.seek(to: playback.elapsed, reducedMotion: reduceMotion) }
        .onChange(of: playback.frame?.cue) { speech.stop() }
    }

    @ViewBuilder private var field: some View {
        if let frame = playback.frame {
            AnimationPitchView(frame: frame, format: playback.clip?.teamSetup?.format)
        } else {
            ContentUnavailableView("Animated field unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("ANIMATED PLAY", systemImage: "play.rectangle")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(CoachPalette.lime)
            Text(play.title).font(.system(.title2, design: .rounded, weight: .bold))
            Text(playback.frame?.cue ?? "Preparing the field...").font(.headline).fixedSize(horizontal: false, vertical: true)
            if let clip = playback.clip {
                if let setup = clip.teamSetup {
                    Text("\(setup.format.rawValue) · starting shape \(setup.formation.rawValue) · \(Int(setup.format.fieldLength)) x \(Int(setup.format.fieldWidth)) m reference")
                        .font(.subheadline).foregroundStyle(CoachPalette.blue)
                    Text(setup.format.layoutNote + " " + setup.format.pitchNote)
                        .font(.caption).foregroundStyle(CoachPalette.muted)
                    Text(playback.frame?.rosterSummary ?? "").font(.caption).foregroundStyle(CoachPalette.blue)
                }
                HStack(spacing: 16) {
                    Button { playback.seek(to: 0, reducedMotion: reduceMotion) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("Restart animated play")
                    Button(action: togglePlayback) {
                        Label(playback.playing ? "Pause" : "Play", systemImage: playback.playing ? "pause.fill" : "play.fill").frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(CoachPalette.ink)
                }
                Slider(value: Binding(get: { playback.elapsed }, set: { playback.seek(to: $0, reducedMotion: reduceMotion) }), in: 0...clip.duration) {
                    Text("Animated play timeline")
                }
                Text("\(playback.elapsed, specifier: "%.1f") / \(clip.duration, specifier: "%.1f") seconds")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                Picker("Playback speed", selection: $playback.speed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                }.pickerStyle(.segmented)
                Toggle("Loop play", isOn: $playback.looping)
                Text(reduceMotion ? "Reduce Motion is on: the timeline advances in clear steps." :
                        "Players move continuously; the ball travels between decisions. Scrub or slow down to discuss timing.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                phaseButtons(clip)
            }
            if let message = playback.error ?? speech.error {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Text("Lime: coaching team. Red: opposition. Attack toward the opposite goal; coordinates are illustrative, not a complete offside or match simulation.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            if !play.notes.isEmpty { Text(play.notes).font(.subheadline).textSelection(.enabled) }
            Button(speech.speaking ? "Stop spoken cue" : "Speak this cue", systemImage: "speaker.wave.2") {
                if speech.speaking { speech.stop() }
                else if let cue = playback.frame?.cue { playback.pause(); speech.speak(cue) }
            }.frame(minHeight: 44)
            PresenterControls()
            VStack(alignment: .leading, spacing: 12) {
                Label("Sources and authorship", systemImage: "link").font(.headline)
                Text(provenance)
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                ForEach(Array((play.animation?.references ?? []).enumerated()), id: \.offset) { _, reference in
                    Link(reference.title, destination: reference.url).font(.subheadline).frame(minHeight: 44)
                }
                if play.animation?.references.isEmpty == true {
                    Text("No web references attached to this custom play.").font(.caption).foregroundStyle(CoachPalette.muted)
                }
                Text("Provenance is informational, not verified ownership. Source links do not imply affiliation, endorsement or permission to copy.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
                Text("Links open the web only when tapped. Exported JSON keeps the full animation; SVG is a static opening-frame diagram.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }.coachCard()
        }
    }

    private func togglePlayback() {
        speech.stop()
        if playback.playing { playback.pause() } else { playback.play(reducedMotion: reduceMotion) }
    }

    private var provenance: String {
        switch play.animation?.origin {
        case .coachAIOriginal:
            "Original CoachAI diagrams and coaching wording based on common tactical principles. Reference text, images and authored drills are not included."
        case .userCreated:
            "Custom animated play created in CoachAI. Review its accuracy and your rights to any material you add before sharing."
        case .adapted:
            "Customized animated play. Retained references describe underlying principles; verify the origin and permissions of any imported material."
        case nil:
            "This imported or older animation has no origin metadata. Check authorship and permissions before sharing."
        }
    }

    private func jumpPhase(_ direction: Int) {
        guard let clip = playback.clip else { return }
        let current = clip.frames.lastIndex { $0.time <= playback.elapsed } ?? 0
        let target = max(0, min(clip.frames.count - 1, current + direction))
        playback.seek(to: clip.frames[target].time, reducedMotion: reduceMotion)
    }

    private func phaseButtons(_ clip: TacticalAnimation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(clip.frames.indices, id: \.self) { index in
                    Button("Step \(index + 1)") { playback.seek(to: clip.frames[index].time, reducedMotion: reduceMotion) }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
        }
    }
}

struct AnimationPitchView: View {
    let frame: AnimationFrame
    var audience = false
    var format: TeamFormat? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let thumbnail = min(size.width, size.height) < 160
                let canvas = thumbnail ? CGSize(width: 300, height: 400) : size
                if thumbnail {
                    let scale = min(size.width / canvas.width, size.height / canvas.height)
                    context.translateBy(x: (size.width - canvas.width * scale) / 2, y: (size.height - canvas.height * scale) / 2)
                    context.scaleBy(x: scale, y: scale)
                }
                let projection = PitchProjection(size: canvas, horizontal: canvas.width > canvas.height, format: format)
                PitchView.drawField(context: &context, projection: projection, increasedContrast: contrast == .increased)
                for player in frame.players {
                    let point = projection.location(player.point)
                    let radius: CGFloat = min(20, max(11, projection.metersToPoints * 2.4))
                    let bounds = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    let color = player.team == .home ? CoachPalette.lime : Color(red: 0.77, green: 0.24, blue: 0.30)
                    let marker = player.team == .home ? Path(ellipseIn: bounds) : Path(roundedRect: bounds, cornerRadius: radius * 0.35)
                    context.fill(marker, with: .color(color))
                    context.stroke(marker, with: .color(.white.opacity(0.65)), lineWidth: 1.5)
                    if player.role == .goalkeeper {
                        context.stroke(Path(ellipseIn: bounds.insetBy(dx: 3, dy: 3)), with: .color(.white.opacity(0.8)), lineWidth: 1)
                    }
                    context.draw(Text(player.label).font(.system(size: radius * 0.85, weight: .heavy))
                        .foregroundStyle(player.team == .home ? CoachPalette.ink : .white), at: point)
                }
                let ball = projection.location(frame.ball)
                context.draw(Text(Image(systemName: "soccerball")).font(.system(size: 24)).foregroundStyle(.white), at: ball)
            }
        }
        .background(CoachPalette.surface, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated soccer field")
        .accessibilityValue(audience ? "\(frame.players.count) players and the ball." : frame.cue)
    }
}
