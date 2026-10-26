import Foundation
import Combine

/// Colours picked with the colour picker, formatted per settings.colorFormat
/// (newest first, deduplicated, max 12, persisted in UserDefaults `dn.data.colorHistory`).
final class ColorHistory: ObservableObject {
    static let shared = ColorHistory()

    @Published private(set) var colors: [String] = []

    private static let key = "dn.data.colorHistory"
    private static let limit = 12

    private init() {
        colors = UserDefaults.standard.stringArray(forKey: ColorHistory.key) ?? []
    }

    func add(_ formatted: String) {
        let value = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var updated = colors.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        updated.insert(value, at: 0)
        if updated.count > ColorHistory.limit { updated.removeLast(updated.count - ColorHistory.limit) }
        colors = updated
        UserDefaults.standard.set(updated, forKey: ColorHistory.key)
    }

    func remove(_ formatted: String) {
        colors.removeAll { $0 == formatted }
        UserDefaults.standard.set(colors, forKey: ColorHistory.key)
    }

    func clear() {
        colors = []
        UserDefaults.standard.removeObject(forKey: ColorHistory.key)
    }
}
