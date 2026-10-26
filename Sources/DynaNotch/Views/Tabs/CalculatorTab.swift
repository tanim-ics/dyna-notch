import SwiftUI
import AppKit
import Combine
import DynaNotchCore

/// Calculator: type an expression (live result) or use the keypad; Return / "=" keeps it in the history.
struct CalculatorTab: View {
    @ObservedObject private var store = CalculatorStore.shared
    @State private var copiedID: UUID?
    @State private var copiedResult = false

    private var liveValue: Double? { Calculator.evaluate(store.expression) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                PanelInputField(symbol: "function", placeholder: "Type an expression, e.g. 12% * (3 + sqrt 16)",
                                text: $store.expression, fontSize: 12, monospaced: true,
                                onSubmit: { store.commit() })
                resultLine
                historyList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CalculatorKeypad(store: store)
                .frame(width: 214)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resultLine: some View {
        HStack(spacing: 8) {
            Text("=")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(PanelStyle.tertiary)
            Text(resultText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(liveValue == nil ? PanelStyle.tertiary : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            if copiedResult {
                CopiedBadge()
            } else if liveValue != nil {
                PanelIconButton(symbol: "doc.on.doc", size: 10, frame: 22, help: "Copy result") {
                    copyResult()
                }
            }
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture { copyResult() }
    }

    private var resultText: String {
        if let v = liveValue { return Calculator.format(v) }
        return store.expression.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : "…"
    }

    @ViewBuilder
    private var historyList: some View {
        if store.history.isEmpty {
            Text("Return saves a result here · click a result to copy it")
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.tertiary)
                .padding(.top, 4)
        } else {
            HStack {
                PanelCaption("History")
                Spacer()
                Button("Clear") { store.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(store.history) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: CalculatorStore.Entry) -> some View {
        HStack(spacing: 6) {
            Text(entry.expression)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(PanelStyle.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 6)
            if copiedID == entry.id {
                CopiedBadge()
            } else {
                Text("= " + entry.result)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            PanelPasteboard.copy(entry.rawResult)
            withAnimation(.easeOut(duration: 0.15)) { copiedID = entry.id }
            let id = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedID == id { withAnimation { copiedID = nil } }
            }
        }
        .contextMenu {
            Button("Copy Result") { PanelPasteboard.copy(entry.rawResult) }
            Button("Use Expression") { store.expression = entry.expression }
            Button("Insert Result") { store.append(entry.rawResult) }
        }
        .help("Click to copy \(entry.result)")
        .accessibilityLabel("Click to copy \(entry.result)")
    }

    private func copyResult() {
        guard let v = liveValue else { return }
        PanelPasteboard.copy(CalculatorStore.plain(v))
        withAnimation(.easeOut(duration: 0.15)) { copiedResult = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedResult = false }
        }
    }
}

/// 5 × 5 keypad.
private struct CalculatorKeypad: View {
    @ObservedObject var store: CalculatorStore

    private let rows: [[String]] = [
        ["C", "⌫", "(", ")", "÷"],
        ["7", "8", "9", "^", "×"],
        ["4", "5", "6", "√", "−"],
        ["1", "2", "3", "%", "+"],
        ["0", ".", "π", "±", "="],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            store.press(key)
        } label: {
            Text(key)
                .font(.system(size: 13, weight: key.first?.isNumber == true || key == "." ? .medium : .semibold,
                              design: .rounded))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(for: key)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func fill(for key: String) -> Color {
        switch key {
        case "=": return PanelStyle.timer.opacity(0.85)
        case "÷", "×", "−", "+": return PanelStyle.timer.opacity(0.3)
        case "C", "⌫": return Color.white.opacity(0.16)
        default:
            return key.first?.isNumber == true || key == "." ? Color.white.opacity(0.1) : Color.white.opacity(0.06)
        }
    }
}

/// Calculator state that survives tab switches (tab views are rebuilt on every switch).
final class CalculatorStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let expression: String
        let result: String      // formatted
        let rawResult: String   // plain, for copying / re-use
    }

    static let shared = CalculatorStore()

    @Published var expression = ""
    @Published private(set) var history: [Entry] = []
    /// After "=", typing a digit starts a new expression; an operator continues from the result.
    private var justEvaluated = false
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = $expression.dropFirst().sink { [weak self] _ in self?.justEvaluated = false }
    }

    func press(_ key: String) {
        switch key {
        case "C":
            expression = ""
        case "⌫":
            if !expression.isEmpty { expression.removeLast() }
        case "=":
            commit()
        case "±":
            let trimmed = expression.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            if trimmed.hasPrefix("-(") && trimmed.hasSuffix(")") {
                expression = String(trimmed.dropFirst(2).dropLast())
            } else {
                expression = "-(" + trimmed + ")"
            }
        case "√":
            appendToken("sqrt(")
        case "÷", "×", "−", "+", "^", "%":
            append(key)
        default:
            appendToken(key)
        }
    }

    /// Appends text, continuing from the last result (operators keep it, digits replace it).
    func append(_ text: String) {
        expression += text
        justEvaluated = false
    }

    private func appendToken(_ text: String) {
        if justEvaluated {
            expression = text
        } else {
            expression += text
        }
        justEvaluated = false
    }

    func commit() {
        let text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = Calculator.evaluate(text) else { return }
        let entry = Entry(expression: text, result: Calculator.format(value), rawResult: Self.plain(value))
        if history.first?.expression != entry.expression {
            history.insert(entry, at: 0)
            if history.count > 20 { history.removeLast(history.count - 20) }
        }
        expression = entry.rawResult
        justEvaluated = true
    }

    func clearHistory() {
        history = []
    }

    /// Ungrouped number for the pasteboard ("1234.5", not "1,234.5").
    static func plain(_ value: Double) -> String {
        Calculator.format(value).replacingOccurrences(of: ",", with: "")
    }
}
