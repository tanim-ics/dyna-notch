import AppKit
import Combine
import Foundation
import os
import DynaNotchCore

/// Now Playing listening history + bookmarks (`ListeningHistory`), recorded from `NowPlayingService.trackChanged`
/// while settings.listeningHistory is on. Stays on this Mac: App Support/listening-history.json.
final class ListeningHistoryService: ObservableObject {
    static let shared = ListeningHistoryService()
    @Published private(set) var history = ListeningHistory()

    private static let file = "listening-history.json"
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "listening")
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        if let saved = AppDataStore.loadFile(ListeningHistory.self, file: ListeningHistoryService.file) {
            history = saved
        }
        NowPlayingService.shared.trackChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard AppSettings.shared.listeningHistory else { return }
                // appName is updated in the same main-queue turn as the snapshot; read it on the next one.
                DispatchQueue.main.async { self?.record(snapshot) }
            }
            .store(in: &cancellables)
    }

    func toggleBookmark(_ entry: ListenEntry) {
        var updated = history
        updated.toggleBookmark(id: entry.id)
        save(updated)
    }

    /// Bookmarks the track that is playing now (adds it to the history first if needed; never un-bookmarks).
    func bookmarkCurrent() {
        let snapshot = NowPlayingService.shared.snapshot
        guard !snapshot.isEmpty else { return }
        var updated = history
        if let newest = updated.entries.first, newest.title == snapshot.title, newest.artist == snapshot.artist {
            if !newest.bookmarked { updated.toggleBookmark(id: newest.id) }
        } else {
            var entry = makeEntry(snapshot)
            entry.bookmarked = true
            updated.record(entry)
        }
        save(updated)
    }

    /// Clears the history; bookmarks stay unless `keepBookmarks` is false.
    func clear(keepBookmarks: Bool) {
        var updated = history
        updated.clear(keepBookmarks: keepBookmarks)
        save(updated)
    }

    func clear() {
        clear(keepBookmarks: true)
    }

    // MARK: Private (main queue)

    private func record(_ snapshot: NowPlayingSnapshot) {
        guard !snapshot.isEmpty else { return }
        var updated = history
        updated.record(makeEntry(snapshot))
        guard updated != history else { return }
        save(updated)
    }

    private func makeEntry(_ snapshot: NowPlayingSnapshot) -> ListenEntry {
        let name = NowPlayingService.shared.appName
        return ListenEntry(title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                           app: name.isEmpty ? snapshot.bundleIdentifier : name, playedAt: Date())
    }

    private func save(_ updated: ListeningHistory) {
        history = updated
        AppDataStore.saveFile(updated, file: ListeningHistoryService.file)
    }
}
