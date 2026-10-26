import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import DynaNotchCore
import os

// MARK: - Navigation

/// Shared sidebar selection so rows (e.g. Popups → Feature alerts) can jump to another page.
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()
    @Published var selection: SettingsPage? = .general

    func go(_ page: SettingsPage) { selection = page }
}

// MARK: - Page

/// Every settings page: large title + plain-English subtitle, then a grouped form.
struct SettingsPageView<Content: View>: View {
    let page: SettingsPage
    let content: Content

    init(page: SettingsPage, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        // The header scrolls with the page (inside the Form) so nothing slides underneath it, and the window keeps
        // a standard title bar whose material appears as soon as the content scrolls under it.
        // The header sits in an empty Section's header slot: grouped Forms draw no card for a section without rows,
        // so it reads as a plain large title (a row with .listRowBackground(.clear) still gets the card border).
        Form {
            Section {
                EmptyView()
            } header: {
                SettingsPageHeader(page: page)
                    .padding(.bottom, 12)
                    .textCase(nil)
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
        .background(SettingsWindowProbe())
        .onAppear { SettingsScrollDriver.shared.start() }
    }
}

struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(symbol: page.symbol, color: page.color, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primary)
                Text(page.subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Icons

/// Rounded-square coloured SF Symbol, like macOS System Settings. Fades when its row is disabled.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(Color.white)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Rows

/// Title + one grey sentence; dims when disabled.
struct SettingLabel: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIcon(symbol: symbol, color: color, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

/// Icon + title + description on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let control: Control

    init(symbol: String, color: Color, title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingLabel(symbol: symbol, color: color, title: title, detail: detail)
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 1)
    }
}

extension SettingRow where Control == EmptyView {
    init(symbol: String, color: Color, title: String, detail: String) {
        self.init(symbol: symbol, color: color, title: title, detail: detail) { EmptyView() }
    }
}

/// Icon + title + description, with a wide control (segmented picker, preview cards …) underneath.
struct SettingStackedRow<Control: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let control: Control

    init(symbol: String, color: Color, title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingLabel(symbol: symbol, color: color, title: title, detail: detail)
            control
                .padding(.leading, 32)
        }
        .padding(.vertical, 2)
    }
}

/// A switch row.
struct SettingToggle: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var testID: String? = nil

    var body: some View {
        SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .settingsTestID(testID)
        }
    }
}

/// A read-only value row (status read-outs).
struct SettingValueRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

/// A row that jumps to another settings page.
struct SettingNavigationRow: View {
    let page: SettingsPage
    let detail: String

    var body: some View {
        Button {
            SettingsNavigator.shared.go(page)
        } label: {
            HStack(spacing: 12) {
                SettingLabel(symbol: page.symbol, color: page.color, title: page.title, detail: detail)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Value controls

/// "−  value  +" with small borderless buttons.
struct ValueStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var valueWidth: CGFloat = 58
    var testID: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button { nudge(-1) } label: {
                Image(systemName: "minus").frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .disabled(value <= range.lowerBound + step / 1000)
            .help("Decrease")
            .settingsTestID(testID.map { $0 + "-minus" })
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .frame(minWidth: valueWidth)
                .lineLimit(1)
            Button { nudge(1) } label: {
                Image(systemName: "plus").frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .disabled(value >= range.upperBound - step / 1000)
            .help("Increase")
            .settingsTestID(testID.map { $0 + "-plus" })
        }
    }

    private func nudge(_ direction: Double) {
        let raw = value + direction * step
        let snapped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}

/// Int-backed "−  value  +".
struct IntValueStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: (Int) -> String

    var body: some View {
        ValueStepper(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                     range: Double(range.lowerBound)...Double(range.upperBound),
                     step: Double(step),
                     format: { format(Int($0.rounded())) })
    }
}

/// Icon/title/description with "− value +" on the right and a full-width slider below.
struct SliderRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var testID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
                ValueStepper(value: $value, range: range, step: step, format: format, testID: testID)
            }
            Slider(value: $value, in: range, step: step)
                .labelsHidden()
                .settingsTestID(testID)
                .padding(.leading, 32)
        }
    }
}

/// Int-backed slider row.
struct IntSliderRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String
    var testID: String? = nil

    var body: some View {
        SliderRow(symbol: symbol, color: color, title: title, detail: detail,
                  value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                  range: Double(range.lowerBound)...Double(range.upperBound),
                  step: Double(step),
                  format: { format(Int($0.rounded())) },
                  testID: testID)
    }
}

/// Int-backed stepper row (minutes, counts).
struct StepperRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: (Int) -> String

    var body: some View {
        SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
            IntValueStepper(value: $value, range: range, step: step, format: format)
        }
    }
}

// MARK: - Buttons

/// "Copy …" button that briefly reads "Copied" after putting `text()` on the pasteboard.
struct CopyButton: View {
    let title: String
    let text: () -> String

    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = false }
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(minWidth: 70)
        }
    }
}

/// A red button (Clear…, Reset…, Quit).
struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title).foregroundStyle(Color.red)
        }
    }
}

/// "Title…" → inline "Cancel · Confirm" (no modal alert).
struct InlineConfirmButton: View {
    let title: String
    let confirmTitle: String
    var destructive: Bool = true
    let action: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack(spacing: 6) {
            if confirming {
                Button("Cancel") { confirming = false }
                if destructive {
                    DestructiveButton(title: confirmTitle) {
                        confirming = false
                        action()
                    }
                } else {
                    Button(confirmTitle) {
                        confirming = false
                        action()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else if destructive {
                DestructiveButton(title: title) { confirming = true }
            } else {
                Button(title) { confirming = true }
            }
        }
    }
}

/// Last section of every page: forgets this page's keys.
struct RestoreDefaultsSection: View {
    @EnvironmentObject var settings: AppSettings
    let keys: [String]

    @State private var restored = false

    var body: some View {
        Section {
            SettingRow(symbol: "arrow.counterclockwise", color: .gray, title: "Restore Defaults",
                       detail: restored ? "Done — this page is back to its defaults."
                                        : "Reset this page's settings; nothing else changes.") {
                InlineConfirmButton(title: "Restore…", confirmTitle: "Restore", destructive: false) {
                    settings.restoreDefaults(keys)
                    restored = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { restored = false }
                }
            }
        }
    }
}

/// Small "lock" reassurance line used as a section footer.
struct PrivacyFooter: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section footer text, leading-aligned like System Settings (grouped Forms otherwise right-align it).
struct SettingsFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sidebar search

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
    }
}

// MARK: - Permissions

/// Permission status row: icon, title, description, state dot and an action.
struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let status: PermissionStatus
    let anchor: String
    let request: (() -> Void)?

    var body: some View {
        SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                    Text(status.title)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                if status == .notDetermined, let request = request {
                    Button("Allow…", action: request)
                } else if status != .granted {
                    Button("Open…") { SettingsLinks.openPrivacy(anchor) }
                        .help("Open System Settings → Privacy & Security")
                }
            }
        }
    }
}

// MARK: - Suggestions (General page + sidebar badge)

struct SettingsSuggestion: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
}

enum SettingsSuggestions {
    /// One suggestion per permission a turned-on feature still misses.
    static func current(settings: AppSettings) -> [SettingsSuggestion] {
        var result: [SettingsSuggestion] = []
        let ax = PermissionProbe.accessibility
        if ax != .granted && (settings.replaceSystemHUD || settings.pasteOnClick) {
            result.append(SettingsSuggestion(
                id: "accessibility", symbol: "accessibility", color: .blue,
                title: "Allow Accessibility",
                detail: "Lets DynaNotch replace the volume / brightness HUD and paste clipboard items. Already switched on but this stays? Select DynaNotch in that list, remove it with −, then click Allow… again (an old build is listed).",
                actionTitle: "Allow…",
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }))
        }
        let cal = PermissionProbe.eventKit(.event)
        if cal != .granted && settings.calendarEnabled {
            result.append(SettingsSuggestion(
                id: "calendar", symbol: "calendar", color: .red,
                title: "Connect your calendar",
                detail: "Shows Up Next, alerts before events and meeting reminders.",
                actionTitle: cal == .notDetermined ? "Allow…" : "Open…",
                action: {
                    if cal == .notDetermined { CalendarService.shared.requestAccess() }
                    else { Permissions.openCalendarSettings() }
                }))
        }
        let rem = PermissionProbe.eventKit(.reminder)
        if rem != .granted && settings.enabledTabs.contains(.reminders) {
            result.append(SettingsSuggestion(
                id: "reminders", symbol: "checklist", color: .orange,
                title: "Allow Reminders",
                detail: "Needed by the Reminders tab to list and complete your reminders.",
                actionTitle: rem == .notDetermined ? "Allow…" : "Open…",
                action: {
                    if rem == .notDetermined { RemindersService.shared.requestAccess() }
                    else { SettingsLinks.openPrivacy("Privacy_Reminders") }
                }))
        }
        if settings.focusActivity && PermissionProbe.fullDiskAccess != .granted {
            result.append(SettingsSuggestion(
                id: "fda", symbol: "moon.fill", color: .indigo,
                title: "Detect Focus modes",
                detail: "Grant Full Disk Access so DynaNotch can show a popup when Focus turns on or off.",
                actionTitle: "Open…",
                action: { Permissions.openFullDiskAccessSettings() }))
        }
        return result
    }
}

// MARK: - Bundle ID list

/// Editable comma-separated list of bundle identifiers (clipboard ignored apps, launcher apps).
struct BundleIDListEditor: View {
    @Binding var list: String
    let placeholder: String
    @State private var draft: String = ""

    private var ids: [String] {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        ForEach(ids, id: \.self) { id in
            HStack(spacing: 10) {
                appIcon(id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appName(id) ?? id)
                    if appName(id) != nil {
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { remove(id) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        HStack(spacing: 8) {
            TextField("Bundle ID", text: $draft, prompt: Text(placeholder))
                .labelsHidden()
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Choose App…", action: chooseApp)
        }
    }

    private func appURL(_ id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    private func appName(_ id: String) -> String? {
        guard let url = appURL(id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @ViewBuilder
    private func appIcon(_ id: String) -> some View {
        if let url = appURL(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        insert(draft.trimmingCharacters(in: .whitespaces))
        draft = ""
    }

    private func insert(_ id: String) {
        guard !id.isEmpty, !ids.contains(id) else { return }
        list = (ids + [id]).joined(separator: ",")
    }

    private func remove(_ id: String) {
        list = ids.filter { $0 != id }.joined(separator: ",")
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { insert(id) }
        }
    }
}

// MARK: - Scripted scrolling (UI tests)

/// Debug hook for scripted checks: a distributed notification `com.tanim.dynanotch.debug.settingsScroll` whose
/// object is "<y>" or "<y>|<name>" (y in points from the top, or "end") scrolls the open settings page, so rows
/// below the fold can be clicked by `.uiTestID`; with a name it then renders the window to
/// `~/Library/Application Support/DynaNotch/Snapshots/<name>.png`.
final class SettingsScrollDriver {
    static let shared = SettingsScrollDriver()
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "settings")

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.tanim.dynanotch.debug.settingsScroll"), object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note.object as? String ?? "0")
        }
    }

    /// Set by `SettingsWindowProbe` in the page background.
    weak var window: NSWindow?

    private func handle(_ command: String) {
        let parts = command.split(separator: "|", maxSplits: 1).map(String.init)
        scroll(to: parts.first ?? "0")
        guard parts.count == 2 else { return }
        let name = parts[1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.snapshot(name) }
    }

    private func scroll(to value: String) {
        guard let window = window, let content = window.contentView else {
            logger.error("scroll: no settings window")
            return
        }
        var views: [NSScrollView] = []
        collect(content, into: &views)
        // The detail page is the right-most scroll view.
        guard let scrollView = views.max(by: { a, b in
            a.convert(a.bounds, to: nil).minX < b.convert(b.bounds, to: nil).minX
        }), let document = scrollView.documentView else {
            let all = NSApp.windows.map { w in
                "\(type(of: w)) '\(w.title)' \(Int(w.frame.width))x\(Int(w.frame.height)) vis=\(w.isVisible)"
            }.joined(separator: "; ")
            logger.error("scroll: no scroll view in \(String(describing: type(of: window)), privacy: .public) \(Int(window.frame.width), privacy: .public); windows: \(all, privacy: .public)")
            return
        }
        let visible = scrollView.contentView.bounds.height
        let maxY = max(0, document.frame.height - visible)
        let wanted = value == "end" ? maxY : min(maxY, max(0, CGFloat(Double(value) ?? 0)))
        let y = document.isFlipped ? wanted : maxY - wanted
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        logger.info("scroll: \(views.count, privacy: .public) views, doc \(document.frame.height, privacy: .public), y \(y, privacy: .public)")
    }

    private func snapshot(_ name: String) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let dir = base.appendingPathComponent("DynaNotch/Snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent(name + ".png"))
        }
    }

    private func collect(_ view: NSView, into result: inout [NSScrollView]) {
        if let scroll = view as? NSScrollView, scroll.bounds.width > 300 { result.append(scroll) }
        for sub in view.subviews { collect(sub, into: &result) }
    }
}

/// Hands the hosting window to `SettingsScrollDriver`.
struct SettingsWindowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { SettingsScrollDriver.shared.window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { SettingsScrollDriver.shared.window = window }
        }
    }
}

// MARK: - Helpers

extension View {
    /// `.uiTestID` when an id is given (shared rows take an optional id).
    @ViewBuilder
    func settingsTestID(_ id: String?) -> some View {
        if let id = id { self.uiTestID(id) } else { self }
    }
}

enum SettingsFormat {
    static func seconds(_ v: Double) -> String { String(format: "%.2f s", v) }
    static func wholeSeconds(_ v: Double) -> String { String(format: "%.0f s", v) }
    static func oneDecimalSeconds(_ v: Double) -> String { String(format: "%.1f s", v) }
    static func signedSeconds(_ v: Double) -> String { String(format: "%+.1f s", v) }
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
    static func multiplier(_ v: Double) -> String { String(format: "%.1f×", v) }
    static func minutes(_ v: Int) -> String { "\(v) min" }
    static func signedPoints(_ v: Double) -> String { String(format: "%+.0f pt", v) }
}

/// Opens a System Settings privacy pane.
enum SettingsLinks {
    static func openPrivacy(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One shared 2 s tick for every Settings page's status read-outs (permissions, suggestions, live values).
/// A `Timer.publish(…).autoconnect()` stored in a view is re-created with every view init and kept ticking after
/// the page was left — with all pages visited that was ~25 wake-ups/s.
enum SettingsTicker {
    static let tick: AnyPublisher<Date, Never> = Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common)
        .autoconnect()
        .share()
        .eraseToAnyPublisher()
}
