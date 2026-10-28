import FoundationModels
import SwiftUI

struct CoachView: View {
    @State private var ball = FieldPoint(depth: 0.65, width: 0.35)
    @State private var position: Position = .lb
    @State private var showHeat = true
    @State private var showGuides = true
    @State private var explanation: String?
    @State private var message: String?
    @State private var isGenerating = false
    @State private var generation: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var recommendation: Recommendation {
        Positioning.recommend(ball: ball, position: position)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    if geometry.size.width >= 700 {
                        HStack(alignment: .top, spacing: 24) {
                            pitch
                            controls.frame(width: 290)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 20) {
                            pitch
                            controls
                        }
                        .padding()
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("CoachAI")
            .toolbar {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    ball = FieldPoint(depth: 0.65, width: 0.35)
                }
            }
        }
        .onChange(of: ball) { invalidateExplanation() }
        .onChange(of: position) { invalidateExplanation() }
        .onChange(of: scenePhase) { if scenePhase != .active { invalidateExplanation() } }
        .onDisappear { generation?.cancel() }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Defend the bottom goal", systemImage: "shield")
                .font(.headline)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.05, green: 0.34, blue: 0.23))
                    Canvas { context, canvas in
                        var lines = Path()
                        let bounds = CGRect(x: 12, y: 12, width: canvas.width - 24, height: canvas.height - 24)
                        lines.addRect(bounds)
                        lines.move(to: CGPoint(x: 12, y: canvas.height / 2))
                        lines.addLine(to: CGPoint(x: canvas.width - 12, y: canvas.height / 2))
                        lines.addEllipse(in: CGRect(x: canvas.width / 2 - 30, y: canvas.height / 2 - 30, width: 60, height: 60))
                        for y in [CGFloat(12), canvas.height - 82] {
                            lines.addRect(CGRect(x: canvas.width * 0.2, y: y, width: canvas.width * 0.6, height: 70))
                        }
                        context.stroke(lines, with: .color(.white.opacity(0.65)), lineWidth: 2)
                        if showGuides {
                            var guide = Path()
                            guide.move(to: coordinate(ball, size: canvas))
                            guide.addLine(to: coordinate(recommendation.point, size: canvas))
                            guide.addLine(to: CGPoint(x: canvas.width / 2, y: canvas.height - 12))
                            context.stroke(guide, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        }
                    }
                    if showHeat {
                        Circle()
                            .fill(.cyan.opacity(0.3))
                            .frame(width: size.width * 0.35, height: size.width * 0.35)
                            .blur(radius: 15)
                            .position(coordinate(recommendation.point, size: size))
                    }
                    Text(position.rawValue)
                        .font(.caption.bold())
                        .frame(width: 40, height: 40)
                        .background(.cyan, in: Circle())
                        .foregroundStyle(.black)
                        .position(coordinate(recommendation.point, size: size))
                    Image(systemName: "soccerball")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .position(coordinate(ball, size: size))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    ball = FieldPoint(
                        depth: 1 - (value.location.y - 12) / max(1, size.height - 24),
                        width: (value.location.x - 12) / max(1, size.width - 24)
                    ).bounded
                })
            }
            .aspectRatio(0.7, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Soccer field. \(position.label). \(recommendation.cue)")
            Text("Drag anywhere to move the ball. Cyan marks the suggested position.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your position").font(.title2.bold())
            Picker("Position", selection: $position) {
                ForEach(Position.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Text(recommendation.cue).font(.headline)
            Text("A simplified teaching guide, not a match-specific instruction.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Position heat spot", isOn: $showHeat)
            Toggle("Goal-side guide", isOn: $showGuides)
            DisclosureGroup("Accessible ball controls") {
                Slider(value: $ball.depth, in: 0...1) { Text("Ball distance from your goal") }
                Slider(value: $ball.width, in: 0...1) { Text("Ball left to right") }
            }
            Divider()
            Label("On-device coach", systemImage: "sparkles").font(.headline)
            Text("Apple Intelligence can explain the guide. It never sets player positions or sends your field to a server.")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: explain) {
                if isGenerating { ProgressView() } else { Text("Explain this position") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
            if let explanation {
                Text(explanation)
                Text("AI-generated; check with your coach.").font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func coordinate(_ point: FieldPoint, size: CGSize) -> CGPoint {
        CGPoint(x: 12 + point.width * (size.width - 24), y: 12 + (1 - point.depth) * (size.height - 24))
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
