import SwiftUI
import OSLog

struct TeamSetupPicker: View {
    @Binding var setup: TeamSetup
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Players per side", selection: Binding(get: { setup.format }, set: { format in
                setup = TeamSetup(format: format, formation: format.formations[0])
            })) {
                ForEach(TeamFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Outfield starting shape", selection: $setup.formation) {
                ForEach(setup.format.formations) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Text(setup.format.layoutNote).font(.subheadline)
            Text(setup.format.ageContext).font(.caption).foregroundStyle(CoachPalette.muted)
            Text("\(Int(setup.format.fieldLength)) x \(Int(setup.format.fieldWidth)) m reference · \(setup.format.hasGoalkeeper ? "goalkeeper included" : "no goalkeeper")")
                .font(.caption).foregroundStyle(CoachPalette.blue)
            Text(setup.format.pitchNote).font(.caption2).foregroundStyle(CoachPalette.muted)
        }
    }
}

struct YouthSetupView: View {
    let store: PlaybookStore
    let board: BoardSnapshot
    @State private var setup = TeamSetup(format: .seven, formation: .twoThreeOne)
    @State private var play: SavedPlay?
    @State private var designing: SavedPlay?
    @State private var error: String?
    @State private var audienceOwner = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "YouthSetup")

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
            .navigationTitle("Kids & smaller teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Design this play", systemImage: "pencil.and.outline", action: openDesigner)
                        .disabled(play == nil || !store.loaded || !store.writable || store.busy)
                }
            }
            .toolbar(.visible, for: .bottomBar)
            .toolbarBackground(CoachPalette.ink, for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
        }
        .preferredColorScheme(.dark).tint(CoachPalette.lime)
        .background(ExternalFieldAccessory().allowsHitTesting(false))
        .sheet(item: $designing) { AnimationDesignerView(store: store, initial: $0) }
        .onAppear { if play == nil { refresh() } else { publish() } }
        .onChange(of: setup) { refresh() }
        .onChange(of: designing?.id) { if designing == nil { publish() } }
        .onDisappear { FieldPresentation.shared.finishAnimation(owner: audienceOwner) }
    }

    @ViewBuilder private var field: some View {
        if let frame = play?.animation?.frames.first {
            AnimationPitchView(frame: frame, format: setup.format)
        } else {
            ContentUnavailableView("Choose a starting layout", systemImage: "person.3")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("SMALLER TEAMS, MORE INVOLVEMENT", systemImage: "figure.child").font(.headline)
                TeamSetupPicker(setup: $setup)
                Text("These are starting shapes, not rigid positions or a ranking of formations. Let children explore, rotate roles, share playing time and make their own decisions.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
            }.coachCard()
            Button(action: openDesigner) { Label("Design this play", systemImage: "pencil.and.outline").frame(minHeight: 44) }
                .buttonStyle(.borderedProminent).foregroundStyle(CoachPalette.ink)
                .disabled(play == nil || !store.loaded || !store.writable || store.busy)
            Text("Creates a new, editable two-phase play. Add simple passes and runs, preview, then Save to keep it. The original five-role defensive AI guide is not used to generate youth positions.")
                .font(.caption).foregroundStyle(CoachPalette.muted)
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            PresenterControls()
            VStack(alignment: .leading, spacing: 12) {
                Label("Guidance, not universal rules", systemImage: "book").font(.headline)
                Text("Formats and ages vary by country, season and league. England's 2026-27 pathway starts at U7 3v3; U.S. programs commonly use 4v4 before 7v7 and 9v9. Confirm your team's actual format. Formation numbers exclude the goalkeeper.")
                    .font(.caption).foregroundStyle(CoachPalette.muted)
                ForEach(Array(setup.format.references.enumerated()), id: \.offset) { _, reference in
                    Link(reference.title, destination: reference.url).frame(minHeight: 44)
                }
                Text("Original schematic layouts; source diagrams are not copied. No child names, birth dates or accounts are required.")
                    .font(.caption2).foregroundStyle(CoachPalette.muted)
            }.coachCard()
        }
    }

    private func refresh() {
        do {
            play = try setup.newPlay(board: board)
            error = nil
            publish()
        } catch {
            logger.error("Youth setup failed: \(String(describing: error), privacy: .private)")
            self.error = error.localizedDescription
            play = nil
            FieldPresentation.shared.finishAnimation(owner: audienceOwner)
        }
    }
    private func publish() {
        guard designing == nil, let frame = play?.animation?.frames.first else { return }
        FieldPresentation.shared.beginAnimation(owner: audienceOwner)
        FieldPresentation.shared.publish(frame, owner: audienceOwner, format: setup.format)
    }
    private func openDesigner() {
        guard var copy = play else { return }
        copy.id = UUID()
        copy.created = Date()
        copy.updated = Date()
        designing = copy
    }
}
