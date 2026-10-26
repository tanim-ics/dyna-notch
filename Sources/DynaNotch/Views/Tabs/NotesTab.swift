import SwiftUI
import AppKit
import DynaNotchCore

/// Notes: a scratchpad on the left, a to-do list on the right.
struct NotesTab: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NotesEditor()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TodoList()
                .frame(width: 240)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct NotesEditor: View {
    @EnvironmentObject var notes: NotesService
    @SwiftUI.FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .focused($focused)
                .padding(6)
            if notes.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 12))
                    .foregroundStyle(PanelStyle.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .requestsPanelKey()
        .onChange(of: focused) {
            if focused { PanelKey.request() }
        }
    }
}

struct TodoList: View {
    @EnvironmentObject var notes: NotesService
    @State private var draft = ""
    @SwiftUI.FocusState private var focused: Bool

    private var hasDone: Bool { notes.todos.contains { $0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PanelCaption("To-Do")
                Spacer(minLength: 4)
                if hasDone {
                    Button("Clear done") { notes.clearDone() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PanelStyle.secondary)
                }
            }
            inputRow
            rows
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField("Add a to-do", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white)
                .focused($focused)
                .onSubmit(add)
            PanelIconButton(symbol: "plus", size: 10, frame: 18, help: "Add") { add() }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .panelField()
        .requestsPanelKey()
        .onChange(of: focused) {
            if focused { PanelKey.request() }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if notes.todos.isEmpty {
            Text("Nothing to do 🎉")
                .font(.system(size: 11))
                .foregroundStyle(PanelStyle.tertiary)
                .padding(.top, 4)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes.todos) { todo in
                        TodoRow(todo: todo)
                    }
                }
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notes.addTodo(text)
        draft = ""
    }
}

struct TodoRow: View {
    let todo: TodoItem

    @EnvironmentObject var notes: NotesService
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { notes.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(todo.done ? IslandColors.charging : Color.white.opacity(0.5))
            }
            .buttonStyle(PressableButtonStyle())
            Text(todo.text)
                .font(.system(size: 11))
                .strikethrough(todo.done, color: Color.white.opacity(0.4))
                .foregroundStyle(Color.white.opacity(todo.done ? 0.4 : 0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                PanelIconButton(symbol: "xmark", size: 8, frame: 16, tint: PanelStyle.secondary, help: "Delete") {
                    notes.remove(todo)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
        )
        .onHover { hovering = $0 }
    }
}
