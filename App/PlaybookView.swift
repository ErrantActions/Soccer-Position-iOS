import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private struct PlayFileShare: Transferable {
    let play: SavedPlay
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { (item: PlayFileShare) in
            try PlayCodec.document(item.play)
        }
        .suggestedFileName { PlayCodec.filename($0.play.title) + ".coachai.json" }
    }
}

private struct PlayDiagramShare: Transferable {
    let play: SavedPlay
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .svg) { (item: PlayDiagramShare) in
            try PlayDiagram.svg(item.play)
        }
        .suggestedFileName { PlayCodec.filename($0.play.title) + ".svg" }
    }
}

struct PlaybookView: View {
    let store: PlaybookStore
    let current: BoardSnapshot
    let frames: [PlayFrame]
    let onLoad: (SavedPlay) -> Void
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var importing = false
    @State private var editing: SavedPlay?
    @State private var animating: SavedPlay?
    @State private var designing: SavedPlay?
    @State private var resetting = false
    @Environment(\.dismiss) private var dismiss

    private var filtered: [SavedPlay] {
        store.plays.filter {
            (!favoritesOnly || $0.favorite) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                        if !store.writable {
                            if let url = store.storageURL {
                                ShareLink("Export recovery file", item: url)
                            }
                            Button("Reset damaged storage", role: .destructive) { resetting = true }
                        }
                    }
                }
                Section {
                    Button {
                        do { designing = try AnimationDraft.newPlay(board: current) }
                        catch { store.report(error, prefix: "The designer could not be opened.") }
                    } label: { Label("Create animated play", systemImage: "pencil.and.outline") }
                    .accessibilityIdentifier("coach.designer.new")
                    Button {
                        editing = SavedPlay(title: "New coaching play", board: current, frames: frames)
                    } label: { Label("Save current setup", systemImage: "bookmark") }
                    Button { importing = true } label: { Label("Import CoachAI play", systemImage: "square.and.arrow.down") }
                    if store.busy { ProgressView("Updating local playbook...") }
                }
                .disabled(!store.writable || store.busy || !store.loaded)
                Section {
                    Toggle("Favorites only", isOn: $favoritesOnly)
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "Your next great play starts here" : "No matching plays",
                            systemImage: "books.vertical",
                            description: Text("Save an editable setup, import a play file, or start with an example below.")
                        )
                    }
                    ForEach(filtered) { play in
                        row(play, example: false)
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { Task { await store.remove(play) } }
                                    .disabled(store.busy)
                            }
                    }
                } header: { Text("Your playbook · \(store.plays.count)/100") }
                Section("Animated tactical patterns") {
                    ForEach(AnimatedPlayLibrary.plays.filter {
                        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
                            $0.notes.localizedCaseInsensitiveContains(search) ||
                            $0.animation?.category.localizedCaseInsensitiveContains(search) == true
                    }) { row($0, example: true) }
                    Text("Original animated illustrations researched from coaching references. Open a play for phases, sources and presenter controls; save a copy to favorite it.")
                        .font(.caption).foregroundStyle(CoachPalette.muted)
                }
                Section("Example scenes") {
                    ForEach(SavedPlay.examples.filter {
                        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                    }) { row($0, example: true) }
                }
                Section {
                    Text("Stored locally; system backups and sharing are controlled by you. Share files only with people you trust: editable files include full notes and sequence steps; diagrams include a notes excerpt. No live AI response is saved as authoritative analysis.")
                        .font(.caption).foregroundStyle(CoachPalette.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CoachPalette.ink)
            .searchable(text: $search, prompt: "Find plays or coaching notes")
            .navigationTitle("Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { PlayEditorView(store: store, initial: $0) }
            .sheet(item: $animating) { AnimationPlayerView(play: $0) }
            .sheet(item: $designing) { AnimationDesignerView(store: store, initial: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await store.importFile(url) }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        store.report(error, prefix: "The file could not be opened.")
                    }
                }
            }
            .confirmationDialog("Reset local playbook storage?", isPresented: $resetting, titleVisibility: .visible) {
                Button("Preserve a recovery copy and reset", role: .destructive) {
                    Task { await store.resetDamagedStorage() }
                }
            } message: {
                Text("This creates an empty playbook. A copy of the previous file is preserved in the app's local storage. Export a recovery file first if you need an external backup.")
            }
        }
        .preferredColorScheme(.dark)
        .tint(CoachPalette.lime)
        .background(ExternalFieldAccessory().allowsHitTesting(false))
        .task { await store.load() }
    }

    private func row(_ play: SavedPlay, example: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                open(play)
            } label: {
                HStack(spacing: 14) {
                    PlayThumbnail(play: play).frame(width: 75, height: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if play.favorite { Image(systemName: "star.fill").foregroundStyle(CoachPalette.lime).font(.caption) }
                            Text(play.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                        }
                        if let clip = play.animation {
                            Text("\(clip.category) · \(clip.frames.count) phases · \(Int(clip.duration)) seconds")
                                .font(.caption).foregroundStyle(CoachPalette.blue)
                        } else {
                            Text("\(play.board.scene.formation.rawValue) · \(play.board.position.rawValue) · \(play.board.routes.count) routes")
                                .font(.caption).foregroundStyle(CoachPalette.muted)
                            Text(play.frames.isEmpty ? "Single scene" : "\(play.frames.count) sequence steps")
                                .font(.caption2).foregroundStyle(CoachPalette.blue)
                        }
                        if !play.notes.isEmpty {
                            Text(play.notes).font(.caption2).foregroundStyle(CoachPalette.muted).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(play.animation == nil ? "Load" : "Show animated play") \(play.title)")
            Menu {
                Button(play.animation == nil ? "Load setup" : "Show animated play", systemImage: "play.rectangle") { open(play) }
                if play.animation != nil {
                    Button(example ? "Customize an editable copy" : "Edit animation", systemImage: "pencil.and.outline") {
                        var editable = play
                        if example {
                            editable.id = UUID()
                            editable.title = String((play.title + " custom").prefix(80))
                            editable.created = Date()
                            editable.updated = Date()
                        }
                        designing = editable
                    }
                    .disabled(!store.writable || !store.loaded)
                }
                if !example {
                    Button("Edit name and notes", systemImage: "square.and.pencil") { editing = play }
                    Button(play.favorite ? "Remove favorite" : "Favorite", systemImage: play.favorite ? "star.slash" : "star") {
                        var changed = play
                        changed.favorite.toggle()
                        Task { await store.save(changed) }
                    }
                }
                Button(example ? "Save a copy" : "Duplicate play", systemImage: "doc.on.doc") {
                    var copy = play
                    copy.id = UUID()
                    copy.title = String((play.title + " copy").prefix(80))
                    copy.created = Date()
                    copy.updated = Date()
                    Task { await store.save(copy) }
                }
                ShareLink(item: PlayFileShare(play: play), preview: SharePreview(play.title)) {
                    Label("Share editable play file", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: PlayDiagramShare(play: play), preview: SharePreview(play.title)) {
                    Label("Share field diagram (SVG)", systemImage: "photo")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
            }
            .disabled(store.busy)
        }
        .padding(.vertical, 6)
        .listRowBackground(CoachPalette.surface)
    }

    private func open(_ play: SavedPlay) {
        if play.animation != nil { animating = play }
        else { onLoad(play); dismiss() }
    }
}

private struct PlayEditorView: View {
    let store: PlaybookStore
    @State private var play: SavedPlay
    @Environment(\.dismiss) private var dismiss

    init(store: PlaybookStore, initial: SavedPlay) {
        self.store = store
        _play = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Play title", text: $play.title).textInputAutocapitalization(.words) }
                Section("Coaching notes") {
                    TextEditor(text: $play.notes).frame(minHeight: 150)
                    Text("\(play.notes.count)/4000 characters").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Favorite", isOn: $play.favorite)
                    PlayThumbnail(play: play).frame(height: 220).frame(maxWidth: .infinity)
                    Text(play.animation == nil ?
                         "\(play.frames.count) captured sequence steps. Stores editable positions and routes, not a live AI assessment." :
                         "Keeps the full animation, phase cues and research links. Edit its name, notes and favorite status here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Save play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        play.title = play.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { if await store.save(play) { dismiss() } }
                    }
                    .disabled(store.busy || !store.writable || play.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              play.title.count > 80 || play.notes.count > 4_000)
                }
            }
        }
        .preferredColorScheme(.dark).tint(CoachPalette.lime)
        .background(ExternalFieldAccessory().allowsHitTesting(false))
    }
}

struct PlayThumbnail: View {
    let play: SavedPlay
    var body: some View {
        if let frame = play.animation?.frames.first {
            AnimationPitchView(frame: frame)
        } else {
            BoardThumbnail(board: play.board)
        }
    }
}

struct BoardThumbnail: View {
    let board: BoardSnapshot
    var body: some View {
        Canvas { context, size in
            let width = min(size.width, size.height * 0.75)
            context.translateBy(x: (size.width - width) / 2, y: (size.height - width / 0.75) / 2)
            context.scaleBy(x: width / 300, y: width / 300)
            let projection = PitchProjection(size: CGSize(width: 300, height: 400), horizontal: false)
            context.fill(Path(projection.bounds), with: .color(Color(red: 0.06, green: 0.25, blue: 0.18)))
            context.stroke(Path(projection.bounds), with: .color(.white.opacity(0.5)), lineWidth: 2)
            for route in board.routes {
                var line = Path()
                for (index, point) in route.enumerated() {
                    if index == 0 { line.move(to: projection.location(point)) }
                    else { line.addLine(to: projection.location(point)) }
                }
                context.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 2)
            }
            for player in board.scene.teammates {
                let point = projection.location(player.point)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                             with: .color(player.role == board.position ? CoachPalette.lime : CoachPalette.blue))
            }
            let point = projection.location(board.scene.ball)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(.white))
        }
        .accessibilityLabel("Saved scene, \(board.position.label), \(board.scene.formation.rawValue)")
    }
}
