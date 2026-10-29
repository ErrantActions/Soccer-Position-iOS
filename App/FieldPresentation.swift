import SwiftUI
import UIKit
import Observation
import OSLog

struct BoardPresentation: Equatable {
    let board: BoardSnapshot
    let advice: [PlayerAdvice]
    let showPlayers: Bool
    let aiSuggested: Bool
    let practice: PracticeRound?
    let preview: [FieldPoint]
}

@MainActor @Observable
final class FieldPresentation {
    static let shared = FieldPresentation()
    var board: BoardPresentation?
    private(set) var animation: AnimationFrame?
    private(set) var animationFormat: TeamFormat?
    private(set) var animationOwner: UUID?
    var blanked = false
    private var sessions: Set<String> = []
    var connected: Bool { !sessions.isEmpty }

    func connect(_ id: String) { sessions.insert(id) }
    func disconnect(_ id: String) { sessions.remove(id) }
    func beginAnimation(owner: UUID) {
        animationOwner = owner
    }
    func publish(_ frame: AnimationFrame, owner: UUID, format: TeamFormat? = nil) {
        guard animationOwner == owner else { return }
        animation = frame
        animationFormat = format
    }
    func finishAnimation(owner: UUID) {
        guard animationOwner == owner else { return }
        animation = nil
        animationFormat = nil
        animationOwner = nil
    }
}

struct PresenterControls: View {
    @Bindable private var display = FieldPresentation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Field-only presentation", systemImage: "tv").font(.headline)
            if #available(iOS 27.0, *) {
                Text(display.connected ? "External field connected. Controls and notes stay here." :
                        "Connect an AirPlay display or a video-capable USB-C adapter. The app supplies a separate field, not a copy of these controls.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                Toggle("Blank the external field", isOn: $display.blanked)
                    .font(.subheadline)
                Text("Ordinary FaceTime/Zoom screen sharing may still show your entire device. Verify what the audience sees before sharing.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            } else {
                Text("Separate field presentation requires iOS 27 or later. Standard screen mirroring can show all device controls.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
            }
        }
        .coachCard()
    }
}

struct ExternalFieldAccessory: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        if #available(iOS 27.0, *) { return ExternalAccessoryController() }
        return UIViewController()
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

@available(iOS 27.0, *)
private final class ExternalAccessoryController: UIViewController {
    private var registration: UISceneAccessoryRegistration?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let configuration = UISceneConfiguration()
        configuration.delegateClass = ExternalFieldSceneDelegate.self
        registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
    }
}

@MainActor
final class ExternalFieldSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "ExternalField")

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            logger.error("External field connection did not provide a window scene.")
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(rootView: ExternalFieldView())
        self.window = window
        window.makeKeyAndVisible()
        FieldPresentation.shared.connect(session.persistentIdentifier)
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        FieldPresentation.shared.disconnect(scene.session.persistentIdentifier)
        window = nil
    }
}

private struct ExternalFieldView: View {
    private var display: FieldPresentation { .shared }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if !display.blanked {
                    if let frame = display.animation {
                        AnimationPitchView(frame: frame, audience: true, format: display.animationFormat)
                    } else if let content = display.board {
                        board(content, horizontal: proxy.size.width > proxy.size.height)
                    } else {
                        Text("Open a field in CoachAI").foregroundStyle(.white)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .allowsHitTesting(false)
    }

    private func board(_ content: BoardPresentation, horizontal: Bool) -> some View {
        let board = content.board
        let practice = content.practice
        let advice = content.advice.first { $0.role == board.position }
        let recommendation = practice?.target ?? advice.map { Recommendation(point: $0.point, cue: $0.reason) } ??
            Positioning.recommend(ball: board.scene.ball, position: board.position)
        return PitchView(
            ball: .constant(board.scene.ball), routeDrawing: .constant(RouteDrawing()),
            role: board.position, comparison: board.comparing ? board.comparison : nil,
            showHeat: board.showHeat && practice?.revealed != false,
            showGuides: board.showGuides && practice?.revealed != false,
            drawing: false, routeStyle: .curve, snapRoutes: false, horizontal: horizontal,
            recommendation: recommendation, suggestions: content.advice,
            currentTeammates: content.showPlayers ? board.scene.teammates : [],
            opponents: content.showPlayers ? board.scene.opponents : [],
            aiSuggested: content.aiSuggested, editTarget: .ball,
            onMoveTarget: { _, _ in }, onEditingChanged: { _ in }, practice: practice,
            displayRoutes: board.routes + (content.preview.isEmpty ? [] : [content.preview])
        )
    }
}
