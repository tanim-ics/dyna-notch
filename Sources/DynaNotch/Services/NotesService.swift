import Foundation
import Combine
import DynaNotchCore

/// Quick note text and a small to-do list, persisted in UserDefaults.
final class NotesService: ObservableObject {
    static let shared = NotesService()

    private static let textKey = "dn.data.notes"
    private static let todosKey = "dn.data.todos"

    @Published var text: String = "" {
        didSet { scheduleSave() }
    }
    @Published private(set) var todos: [TodoItem] = []

    private let defaults = UserDefaults.standard
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        text = defaults.string(forKey: NotesService.textKey) ?? ""
        if let data = defaults.data(forKey: NotesService.todosKey),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            todos = decoded
        }
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
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.defaults.set(self.text, forKey: NotesService.textKey)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            defaults.set(data, forKey: NotesService.todosKey)
        }
    }
}
