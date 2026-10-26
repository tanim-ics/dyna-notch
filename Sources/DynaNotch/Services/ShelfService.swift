import AppKit
import Combine
import DynaNotchCore

/// Temporary file shelf: remembers file paths dropped on the island (the files themselves stay where they are).
final class ShelfService: ObservableObject {
    static let shared = ShelfService()

    private static let itemsKey = "dn.data.shelf"

    @Published private(set) var items: [ShelfItem] = []

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let data = defaults.data(forKey: ShelfService.itemsKey),
           let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            // Forget files that were moved or deleted since.
            items = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        pruneExpired()
        // Settings → Tabs → Shelf retention: prune every 5 minutes and whenever the setting changes.
        Timer.publish(every: 300, tolerance: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pruneExpired() }
            .store(in: &cancellables)
        AppSettings.shared.$shelfRetention
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pruneExpired() }
            .store(in: &cancellables)
    }

    func add(urls: [URL]) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return }
        items = ShelfList.adding(paths, to: items, now: Date())
        pruneExpired(save: false)
        save()
    }

    /// Drops shelf entries older than `settings.shelfRetention` (the files themselves stay where they are).
    func pruneExpired(save shouldSave: Bool = true) {
        let expired = AppSettings.shared.shelfRetention.expired(items, now: Date())
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        items.removeAll { ids.contains($0.id) }
        if shouldSave { save() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func url(for item: ShelfItem) -> URL {
        URL(fileURLWithPath: item.path)
    }

    func icon(for item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.path)
    }

    func airDrop(_ items: [ShelfItem]) {
        let urls = items.map { url(for: $0) }
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([url(for: item)])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(url(for: item))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: ShelfService.itemsKey)
        }
    }
}
