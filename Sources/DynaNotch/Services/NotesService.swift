import Foundation
import Combine
import DynaNotchCore

/// Quick note text and a small to-do list, in `notes.json`, encrypted with the Secure Enclave key (`Vault`).
/// Older builds kept them in UserDefaults (`dn.data.notes` / `dn.data.todos`); they are moved over once.
final class NotesService: ObservableObject {
    static let shared = NotesService()

    private static let textKey = "dn.data.notes"
    private static let todosKey = "dn.data.todos"
    static let file = "notes.json"

    private struct Stored: Codable {
        var text: String
        var todos: [TodoItem]
    }

    @Published var text: String = "" {
        didSet { scheduleSave() }
    }
    @Published private(set) var todos: [TodoItem] = []

    private let defaults = UserDefaults.standard
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        if let stored = AppDataStore.loadFile(Stored.self, file: NotesService.file) {
            text = stored.text
            todos = stored.todos
        } else if defaults.object(forKey: NotesService.textKey) != nil || defaults.object(forKey: NotesService.todosKey) != nil {
            // Migrate out of the (plain, backed-up) preferences file.
            text = defaults.string(forKey: NotesService.textKey) ?? ""
            if let data = defaults.data(forKey: NotesService.todosKey),
               let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
                todos = decoded
            }
            persist()
            defaults.removeObject(forKey: NotesService.textKey)
            defaults.removeObject(forKey: NotesService.todosKey)
        }
        saveWorkItem?.cancel()   // setting `text` above scheduled a save
    }

    /// Everything, for Export Notes.
    var exportText: String {
        var lines = [text]
        if !todos.isEmpty {
            lines.append("")
            lines += todos.map { ($0.done ? "- [x] " : "- [ ] ") + $0.text }
        }
        return lines.joined(separator: "\n")
    }

    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(text: trimmed, createdAt: Date()))
        saveTodos()
    }

    func toggle(_ todo: TodoItem) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].done.toggle()
        saveTodos()
    }

    func remove(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        saveTodos()
    }

    func clearDone() {
        todos.removeAll { $0.done }
        saveTodos()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persist() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func saveTodos() {
        persist()
    }

    private func persist() {
        AppDataStore.saveFile(Stored(text: text, todos: todos), file: NotesService.file)
    }
}
