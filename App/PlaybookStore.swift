import Foundation
import Observation
import OSLog

@MainActor @Observable
final class PlaybookStore {
    private(set) var plays: [SavedPlay] = []
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var writable = true
    private(set) var error: String?
    private(set) var storageURL: URL?
    @ObservationIgnored private var repository: PlaybookRepository?
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "Playbook")

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent("CoachAI", isDirectory: true).appendingPathComponent("playbook.json")
            storageURL = url
            repository = PlaybookRepository(url: url)
        } catch { report(error, prefix: "Local storage is unavailable."); writable = false }
    }

    func load() async {
        guard !loaded, !busy, let repository else { return }
        busy = true
        defer { busy = false; loaded = true }
        do { plays = try await repository.load(); error = nil }
        catch { report(error, prefix: "The playbook could not be opened. Existing data was preserved."); writable = false }
    }

    @discardableResult func save(_ play: SavedPlay) async -> Bool {
        guard let repository = editingRepository() else { return false }
        busy = true
        defer { busy = false }
        do {
            var changed = plays
            var play = play
            play.updated = Date()
            if let index = changed.firstIndex(where: { $0.id == play.id }) { changed[index] = play }
            else { changed.insert(play, at: 0) }
            try await repository.save(changed)
            plays = changed
            error = nil
            return true
        } catch { report(error, prefix: "The play was not saved."); return false }
    }

    func remove(_ play: SavedPlay) async {
        guard let repository = editingRepository() else { return }
        busy = true
        defer { busy = false }
        do {
            let changed = plays.filter { $0.id != play.id }
            try await repository.save(changed)
            plays = changed
            error = nil
        } catch { report(error, prefix: "The play was not deleted.") }
    }

    func importFile(_ url: URL) async {
        guard let repository = editingRepository() else { return }
        busy = true
        defer { busy = false }
        do {
            var play = try await repository.importPlay(at: url)
            play.id = UUID()
            play.created = Date()
            play.updated = Date()
            let changed = [play] + plays
            try await repository.save(changed)
            plays = changed
            error = nil
        } catch { report(error, prefix: "The file was not imported.") }
    }

    func resetDamagedStorage() async {
        guard !busy, let repository else { return }
        busy = true
        defer { busy = false }
        do {
            try await repository.resetWithRecoveryCopy()
            plays = []
            writable = true
            loaded = true
            error = nil
        } catch { report(error, prefix: "Storage was not reset.") }
    }

    func report(_ problem: Error, prefix: String) {
        logger.error("\(prefix, privacy: .public) \(String(describing: problem), privacy: .private)")
        error = "\(prefix) \(problem.localizedDescription)"
    }

    private func editingRepository() -> PlaybookRepository? {
        guard loaded, writable, !busy, let repository else {
            report(WorkbenchError.invalid("Wait for loading or saving to finish. If storage is damaged, use Playbook recovery before editing."),
                   prefix: "The playbook is not ready to edit.")
            return nil
        }
        return repository
    }
}
