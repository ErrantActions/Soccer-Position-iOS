import Foundation

enum AnimatedPlayLibrary {
    // Original illustrative layouts and wording. References explain principles, not these diagrams.
    static let plays: [SavedPlay] = [overlap, underlap, thirdPlayer, switchPlay, widePress, compactSlide]

    private static let fullBack = PlayReference(
        title: "Coaches' Voice - Modern full-back",
        url: URL(string: "https://learning.coachesvoice.com/cv/modern-full-back-explained-alexander-arnold-robertson-alba/")!
    )
    private static let thirdMan = PlayReference(
        title: "Coaches' Voice - Third-man runs",
        url: URL(string: "https://learning.coachesvoice.com/cv/third-man-runs-football-tactics-explained-gasperini-guardiola/")!
    )
    private static let switching = PlayReference(
        title: "Coaches' Voice - Switches of play",
        url: URL(string: "https://learning.coachesvoice.com/cv/switches-of-play-football-tactics-explained/")!
    )
    private static let block = PlayReference(
        title: "Coaches' Voice - Mid-block",
        url: URL(string: "https://learning.coachesvoice.com/cv/mid-block-football-tactics-explained/")!
    )

    private static func player(_ id: Int, _ depth: Double, _ width: Double) -> AnimationPlayer {
        AnimationPlayer(id: id, label: String(id > 100 ? id - 100 : id),
                        team: id > 100 ? .away : .home, point: FieldPoint(depth: depth, width: width))
    }

    private static func frame(
        _ time: Double, _ ballDepth: Double, _ ballWidth: Double, _ cue: String,
        _ players: [AnimationPlayer]
    ) -> AnimationFrame {
        AnimationFrame(time: time, ball: FieldPoint(depth: ballDepth, width: ballWidth), players: players, cue: cue)
    }

    private static func play(
        _ title: String, category: String, notes: String, reference: PlayReference, frames: [AnimationFrame]
    ) -> SavedPlay {
        SavedPlay(
            title: title,
            notes: notes + "\nOriginal CoachAI teaching illustration of a common pattern, not a copied drill or match reconstruction. Adapt spacing and timing to your players.",
            board: SavedPlay.examples[0].board,
            animation: TacticalAnimation(category: category, frames: frames, references: [reference])
        )
    }

    private static let overlap = play(
        "Around the outside", category: "Attacking", notes: "The wide player draws attention inside while a supporting runner goes outside. Keep cover behind the attack.",
        reference: fullBack, frames: [
            frame(0, 0.53, 0.22, "Hold the defender's attention; the supporting full-back starts from behind.", [
                player(2, 0.35, 0.15), player(7, 0.53, 0.22), player(8, 0.38, 0.47), player(9, 0.70, 0.50),
                player(103, 0.56, 0.14), player(104, 0.58, 0.42), player(105, 0.68, 0.62)]),
            frame(2, 0.56, 0.30, "The winger moves inward as the outside runner accelerates beyond.", [
                player(2, 0.58, 0.08), player(7, 0.56, 0.30), player(8, 0.43, 0.45), player(9, 0.74, 0.48),
                player(103, 0.58, 0.24), player(104, 0.62, 0.41), player(105, 0.70, 0.59)]),
            frame(4, 0.72, 0.08, "Release the pass into the runner's path, not behind them.", [
                player(2, 0.72, 0.08), player(7, 0.64, 0.32), player(8, 0.47, 0.43), player(9, 0.78, 0.48),
                player(103, 0.65, 0.18), player(104, 0.70, 0.38), player(105, 0.75, 0.58)]),
            frame(6, 0.80, 0.42, "Look up before the cut-back; the central runner arrives rather than waiting.", [
                player(2, 0.77, 0.10), player(7, 0.69, 0.31), player(8, 0.50, 0.43), player(9, 0.80, 0.42),
                player(103, 0.72, 0.18), player(104, 0.77, 0.38), player(105, 0.78, 0.58)])
        ])

    private static let underlap = play(
        "Through the inside lane", category: "Attacking", notes: "Keep one player wide to open an inside running lane. A teammate stays behind the move to protect a turnover.",
        reference: fullBack, frames: [
            frame(0, 0.56, 0.12, "Stay wide with the ball and check the inside channel.", [
                player(2, 0.36, 0.26), player(7, 0.56, 0.12), player(8, 0.39, 0.48), player(9, 0.72, 0.52),
                player(103, 0.60, 0.16), player(104, 0.66, 0.48), player(105, 0.70, 0.69)]),
            frame(2, 0.59, 0.12, "The supporting runner goes inside while the winger holds the width.", [
                player(2, 0.61, 0.30), player(7, 0.59, 0.12), player(8, 0.43, 0.46), player(9, 0.76, 0.56),
                player(103, 0.63, 0.16), player(104, 0.69, 0.45), player(105, 0.73, 0.67)]),
            frame(4, 0.73, 0.30, "Slip the ball into the inside run before the gap closes.", [
                player(2, 0.73, 0.30), player(7, 0.65, 0.12), player(8, 0.46, 0.46), player(9, 0.79, 0.56),
                player(103, 0.68, 0.18), player(104, 0.73, 0.45), player(105, 0.76, 0.65)])
        ])

    private static let thirdPlayer = play(
        "Find the third player", category: "Combination", notes: "Use a linking teammate to reach a runner who cannot be found directly. Check shoulders and time the run to stay available.",
        reference: thirdMan, frames: [
            frame(0, 0.36, 0.43, "The direct forward lane is blocked; find an angled link.", [
                player(8, 0.36, 0.43), player(9, 0.58, 0.48), player(10, 0.43, 0.64), player(7, 0.61, 0.15),
                player(104, 0.49, 0.55), player(105, 0.65, 0.69), player(103, 0.64, 0.30)]),
            frame(2, 0.58, 0.48, "As the link receives, the third player moves beyond the first pressure line.", [
                player(8, 0.40, 0.43), player(9, 0.58, 0.48), player(10, 0.59, 0.64), player(7, 0.65, 0.17),
                player(104, 0.53, 0.51), player(105, 0.66, 0.69), player(103, 0.66, 0.31)]),
            frame(4, 0.69, 0.62, "The link sets the ball into the third player's path.", [
                player(8, 0.45, 0.44), player(9, 0.61, 0.46), player(10, 0.69, 0.62), player(7, 0.69, 0.18),
                player(104, 0.58, 0.52), player(105, 0.68, 0.71), player(103, 0.68, 0.33)])
        ])

    private static let switchPlay = play(
        "Escape to the far side", category: "Attacking", notes: "Draw pressure to one side and use a central support player to reach the space opposite. The receiver scans before the ball arrives.",
        reference: switching, frames: [
            frame(0, 0.54, 0.13, "Pressure is arriving on the near side; keep the far player wide.", [
                player(7, 0.54, 0.13), player(6, 0.36, 0.49), player(11, 0.58, 0.87), player(9, 0.73, 0.50),
                player(103, 0.58, 0.20), player(104, 0.57, 0.36), player(105, 0.65, 0.48)]),
            frame(2, 0.36, 0.49, "Set the ball back to a support player with a view of both sides.", [
                player(7, 0.57, 0.15), player(6, 0.36, 0.49), player(11, 0.62, 0.87), player(9, 0.75, 0.51),
                player(103, 0.59, 0.23), player(104, 0.52, 0.40), player(105, 0.66, 0.53)]),
            frame(4, 0.65, 0.86, "Switch before the block can recover. Receive with the next action in mind.", [
                player(7, 0.60, 0.18), player(6, 0.42, 0.52), player(11, 0.65, 0.86), player(9, 0.77, 0.56),
                player(103, 0.60, 0.36), player(104, 0.55, 0.55), player(105, 0.68, 0.68)]),
            frame(6, 0.75, 0.78, "Attack the free space with the first touch while teammates reconnect.", [
                player(7, 0.65, 0.26), player(6, 0.47, 0.55), player(11, 0.75, 0.78), player(9, 0.81, 0.56),
                player(103, 0.64, 0.42), player(104, 0.60, 0.63), player(105, 0.73, 0.69)])
        ])

    private static let widePress = play(
        "Press wide, cover inside", category: "Defending", notes: "Use a wide pass as a cue to press together. The nearest player closes down while teammates protect the inside and the space behind. A regain is not guaranteed.",
        reference: block, frames: [
            frame(0, 0.55, 0.60, "Stay connected while the opposition looks for a wide outlet.", [
                player(2, 0.29, 0.80), player(4, 0.25, 0.62), player(5, 0.25, 0.40), player(3, 0.29, 0.20), player(6, 0.40, 0.55),
                player(111, 0.55, 0.88), player(108, 0.55, 0.60), player(107, 0.55, 0.12)]),
            frame(2, 0.55, 0.88, "Travel with the pass. Close the receiver without opening a simple inside escape.", [
                player(2, 0.47, 0.83), player(4, 0.31, 0.74), player(5, 0.27, 0.53), player(3, 0.30, 0.34), player(6, 0.46, 0.66),
                player(111, 0.55, 0.88), player(108, 0.54, 0.61), player(107, 0.55, 0.16)]),
            frame(4, 0.51, 0.90, "Keep the cover behind the press; contain the opponent rather than diving in.", [
                player(2, 0.49, 0.85), player(4, 0.35, 0.77), player(5, 0.30, 0.56), player(3, 0.32, 0.37), player(6, 0.49, 0.68),
                player(111, 0.51, 0.90), player(108, 0.53, 0.63), player(107, 0.55, 0.20)])
        ])

    private static let compactSlide = play(
        "Move the block together", category: "Defending", notes: "As the ball crosses the pitch, move as a unit. The nearest defender applies pressure; far-side players tuck in while keeping sight of opponents.",
        reference: switching, frames: [
            frame(0, 0.61, 0.15, "Protect the inside when the ball is on the left.", [
                player(3, 0.40, 0.16), player(5, 0.30, 0.30), player(4, 0.30, 0.47), player(2, 0.34, 0.65), player(6, 0.43, 0.35),
                player(107, 0.61, 0.15), player(108, 0.55, 0.50), player(111, 0.61, 0.85)]),
            frame(2, 0.55, 0.50, "Recover toward the middle as the pass goes back through the centre.", [
                player(3, 0.35, 0.25), player(5, 0.30, 0.41), player(4, 0.30, 0.59), player(2, 0.35, 0.75), player(6, 0.43, 0.50),
                player(107, 0.61, 0.16), player(108, 0.55, 0.50), player(111, 0.61, 0.84)]),
            frame(4, 0.61, 0.85, "Press the new side while the whole block slides across behind the pressure.", [
                player(3, 0.34, 0.35), player(5, 0.30, 0.53), player(4, 0.30, 0.70), player(2, 0.40, 0.84), player(6, 0.43, 0.65),
                player(107, 0.61, 0.17), player(108, 0.55, 0.52), player(111, 0.61, 0.85)])
        ])
}
