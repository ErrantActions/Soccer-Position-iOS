import Foundation
import FoundationModels
import Observation
import OSLog

@Generable
private struct GeneratedPlacement {
    @Guide(description: "Distance from own goal, normalized", .range(0.0...1.0))
    var depth: Double
    @Guide(description: "Left to right, normalized", .range(0.0...1.0))
    var width: Double
    @Guide(description: "One short English sentence explaining this position, under 35 words")
    var reason: String

    func advice(for role: Position) -> PlayerAdvice {
        PlayerAdvice(role: role, point: FieldPoint(depth: depth, width: width), reason: reason)
    }
}

@Generable
private struct GeneratedDefensiveUnit {
    var lb: GeneratedPlacement
    var lcb: GeneratedPlacement
    var rcb: GeneratedPlacement
    var rb: GeneratedPlacement
    var cdm: GeneratedPlacement
    @Guide(description: "One short English sentence describing the coordinated defensive shape, under 45 words")
    var summary: String

    var plan: AIPositionPlan {
        AIPositionPlan(players: [
            lb.advice(for: .lb), lcb.advice(for: .lcb), rcb.advice(for: .rcb),
            rb.advice(for: .rb), cdm.advice(for: .cdm),
        ], summary: summary)
    }
}

@MainActor
@Observable
final class PositioningIntelligence {
    private(set) var analysis = PositioningAnalysis()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "AIPositioning")

    func cancel(message: String = "Instant guide active.") {
        task?.cancel()
        timeout?.cancel()
        task = nil
        timeout = nil
        analysis.reset(message: message)
    }

    func analyze(_ scene: TacticalScene, debounced: Bool = false) {
        cancel()
        let issues = AIPositionValidation.inputIssues(scene)
        guard issues.isEmpty else {
            analysis.reset(message: "Cannot analyze this scene: \(issues.joined(separator: " ")) Showing the instant guide.")
            return
        }
        if let message = availabilityMessage {
            analysis.reset(message: "\(message) Showing the instant guide; no cloud fallback.")
            return
        }
        let request = analysis.begin(scene: scene, scheduled: debounced)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if debounced { try await Task.sleep(for: .milliseconds(650)) }
                try Task.checkCancellation()
                guard self.analysis.request == request else { return }
                self.analysis.markThinking(request)
                self.startTimeout(for: request)
                let session = LanguageModelSession(instructions: """
                    You propose experimental soccer defensive positioning for a five-player unit.
                    Return actual normalized coordinates and concise explanations for all five roles.
                    Treat supplied teammate positions as the current situation, not the desired answer.
                    Use formation, ball and opponent positions to coordinate pressure, cover and balance.
                    Never claim professional accuracy or invent a confidence score.
                    All coordinates must be finite and between 0 and 1.
                    Keep LB width 0.05...0.46, LCB 0.20...0.58, RCB 0.42...0.80,
                    RB 0.54...0.95 and CDM 0.30...0.70.
                    Keep the back four ordered LB, LCB, RCB, RB with lateral gaps at least 0.035.
                    Pairwise teammate distances must be at least \(AIPositionValidation.minimumSpacing).
                    Keep at least \(AIPositionValidation.opponentClearance) away from each opponent.
                    Back-four depths must not differ by more than 0.25.
                    A back's depth must be <= max(0.12, ball depth + 0.03);
                    CDM depth must be <= max(0.12, ball depth + 0.08).
                    At least one center back must have width 0.32...0.68 and
                    depth <= max(0.12, min(0.58, ball depth * 0.8)) to protect the goal.
                    Explain pressure, covering space or denying a passing lane using only this scene.
                    """)
                let result = try await session.respond(
                    to: scene.promptContext, generating: GeneratedDefensiveUnit.self,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 1800)
                )
                try Task.checkCancellation()
                guard self.analysis.request == request else { return }
                self.timeout?.cancel()
                self.analysis.finish(result.content.plan, request: request, currentScene: scene)
            } catch is CancellationError {
                // Superseded requests must not alter a newer scene or its status.
            } catch {
                guard self.analysis.request == request, !Task.isCancelled else { return }
                self.timeout?.cancel()
                self.logger.error("Position generation failed: \(String(describing: error), privacy: .private)")
                self.analysis.fail("Apple Intelligence could not complete this analysis. Try again. Showing the instant guide.", request: request)
            }
        }
    }

    private func startTimeout(for request: PositioningRequest) {
        timeout = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(45))
                guard let self, self.analysis.request == request else { return }
                self.task?.cancel()
                self.analysis.fail("AI positioning timed out. Try again. Showing the instant guide.", request: request)
            } catch is CancellationError {
                // The analysis finished, changed, or was explicitly cancelled.
            } catch {
                guard let self else { return }
                self.analysis.fail("The analysis timer failed. Showing the instant guide.", request: request)
                self.task?.cancel()
            }
        }
    }

    private var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Enable Apple Intelligence in Settings to use AI positioning."
        case .unavailable(.modelNotReady): "Apple Intelligence's on-device model is not ready. Allow its download to finish."
        case .unavailable: "On-device AI is unavailable in the current device, language or region configuration."
        @unknown default: "On-device AI is unavailable on this device."
        }
    }
}
