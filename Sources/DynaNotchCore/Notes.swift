import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct TodoItem: Equatable, Identifiable, Codable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date) {
        self.id = id
        self.text = text
        self.done = done
        self.createdAt = createdAt
    }
}

public struct ShelfItem: Equatable, Identifiable, Codable {
    public var id: UUID
    public var path: String
    public var addedAt: Date

    public init(id: UUID = UUID(), path: String, addedAt: Date) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }

    public var name: String { (path as NSString).lastPathComponent }
}

public enum ShelfList {
    /// New paths first (in the given order), existing duplicates moved to the front.
    public static func adding(_ paths: [String], to items: [ShelfItem], now: Date) -> [ShelfItem] {
        var seen = Set<String>()
        var fresh: [ShelfItem] = []
        for path in paths where !path.isEmpty && !seen.contains(path) {
            seen.insert(path)
            if let existing = items.first(where: { $0.path == path }) {
                fresh.append(existing)
            } else {
                fresh.append(ShelfItem(path: path, addedAt: now))
            }
        }
        return fresh + items.filter { !seen.contains($0.path) }
    }
}
