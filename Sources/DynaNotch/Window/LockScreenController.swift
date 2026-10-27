import AppKit
import Combine
import os
import SwiftUI
import DynaNotchCore

/// Lock screen (CONTRACTS §6.11): lock / unlock sounds, the "Unlocked" island and the weather + batteries strip drawn
/// over the lock screen through a private SkyLight space (fallback: no strip).
final class LockScreenController {
    static let shared = LockScreenController()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "lockscreen")
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var window: NSPanel?
    /// Islands that show the "Unlocked" activity (the primary one plus Every Display extras).
    private var islands: () -> [IslandViewModel] = { [] }

    private(set) var isLocked = false
    private(set) var isShown = false
    /// What happened at the last lock (state.json `lockScreen.lastLock`), kept after unlocking so a real lock can be
    /// diagnosed afterwards.
    private(set) var lastLock = "none"

    private init() {}

    func start(islands: @escaping () -> [IslandViewModel]) {
        guard !started else { return }
        started = true
        self.islands = islands
        UserPresence.shared.start()
        UserPresence.shared.lockChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in locked ? self?.didLock() : self?.didUnlock() }
            .store(in: &cancellables)
        // Turning the strip off while locked (unlikely) or the Mac waking with it hidden: follow the setting.
        AppSettings.shared.$lockScreenWidgets
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in if !on { self?.hideStrip() } }
            .store(in: &cancellables)
    }

    /// state.json `lockScreen`.
    var state: [String: Any] {
        let summary = currentSummary()
        return [
            "locked": isLocked,
            "lastLock": lastLock,
            "shown": isShown,
            "skyLight": SkyLightSpace.shared.status,
            "delegated": SkyLightSpace.shared.lastDelegateSucceeded,
            "result": Int(SkyLightSpace.shared.lastResult),
            "space": Int(SkyLightSpace.shared.spaceID),
            "onScreen": window.map(SkyLightSpace.isOnScreen) ?? false,
            "windowNumber": window?.windowNumber ?? 0,
            "weatherStatus": WeatherService.shared.status,
            "weather": summary.weather.map { "\($0.temperature) \($0.detail)" } ?? "",
            "devices": summary.devices.map { "\($0.name) \($0.level)" }.joined(separator: ","),
        ]
    }

    // MARK: Lock / unlock

    private func didLock() {
        isLocked = true
        AlertSoundPlayer.play(.screenLock)
        showStrip()
    }

    private func didUnlock() {
        isLocked = false
        hideStrip()
        AlertSoundPlayer.play(.screenUnlock)
        guard AppSettings.shared.unlockActivity else { return }
        for island in islands() {
            island.post(.toggle(symbol: "lock.open.fill", label: ToggleActivity.unlockedLabel, on: true))
        }
    }

    // MARK: Widgets

    private func currentSummary() -> LockScreenSummary {
        let settings = AppSettings.shared
        return LockScreenSummary.make(
            weather: settings.lockScreenWeather && settings.weatherEnabled ? WeatherService.shared.snapshot : nil,
            devices: settings.lockScreenBatteries ? DeviceBatteryService.shared.devices : [])
    }

    private func showStrip() {
        let settings = AppSettings.shared
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        guard settings.lockScreenWidgets, settings.lockScreenWeather || settings.lockScreenBatteries else {
            lastLock = "\(time) strip off"
            return
        }
        // The main display (the one with the menu bar) shows the lock screen's clock; the widgets go under it.
        guard let screen = NSScreen.screens.first else {
            lastLock = "\(time) no screen"
            return
        }
        if settings.lockScreenBatteries { DeviceBatteryService.shared.refresh() }
        guard SkyLightSpace.shared.isAvailable else {
            lastLock = "\(time) SkyLight unavailable"
            logger.info("lock-screen strip skipped: SkyLight unavailable")
            return
        }
        let panel = window ?? makeWindow()
        window = panel
        panel.contentView = NSHostingView(rootView: LockScreenWidgetsView())
        panel.setFrame(LockScreenLayout.widgetsRect(size: LockScreenWidgetsView.canvasSize, screenFrame: screen.frame),
                       display: true)
        // Into the lock-screen space first, then on screen (the order SkyLightWindow uses). The call's return value is
        // not a reliable status (3 on macOS 27 even when the window moves), so the strip counts as shown while its
        // window is on screen.
        SkyLightSpace.shared.delegate(panel)
        panel.orderFrontRegardless()
        isShown = panel.isVisible
        let detail = "result=\(SkyLightSpace.shared.lastResult) screen=\(screen.localizedName)"
        lastLock = "\(time) shown, \(detail)"
        // The window server lists the window a moment later; keep what it says for state.json.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak panel] in
            guard let self = self, let panel = panel, self.isShown else { return }
            self.lastLock = "\(time) shown, onScreen=\(SkyLightSpace.isOnScreen(panel)), \(detail)"
        }
    }

    private func hideStrip() {
        window?.orderOut(nil)
        isShown = false
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))   // above the lock screen's shield
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    /// `dynanotch://snapshot-lockscreen/<name>`: renders the widgets as they would look now (no window needed), on a
    /// sky-blue backdrop like a wallpaper.
    func snapshot(to url: URL) -> Bool {
        let backdrop = LinearGradient(colors: [Color(red: 0.35, green: 0.55, blue: 0.9), Color(red: 0.95, green: 0.7, blue: 0.4)],
                                      startPoint: .top, endPoint: .bottom)
        let view = NSHostingView(rootView: LockScreenWidgetsView().background(backdrop))
        view.frame = CGRect(origin: .zero, size: LockScreenWidgetsView.canvasSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

/// Lock-screen widgets under the clock (Notchy style): a weather card and a battery-ring card, set in SF Pro like the
/// system clock. Cards without data are left out; nothing at all → transparent.
struct LockScreenWidgetsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var batteries = DeviceBatteryService.shared

    /// Window size: room for the widest layout (weather + four rings); the cards are centred inside.
    static let canvasSize = CGSize(width: 760, height: 150)
    private static let cardHeight: CGFloat = 112

    private var summary: LockScreenSummary {
        LockScreenSummary.make(
            weather: settings.lockScreenWeather && settings.weatherEnabled ? weather.snapshot : nil,
            devices: settings.lockScreenBatteries ? batteries.devices : [], maxDevices: 4)
    }

    var body: some View {
        let s = summary
        HStack(spacing: 14) {
            if let w = s.weather { weatherCard(w) }
            if !s.devices.isEmpty { batteryCard(s.devices) }
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height, alignment: .top)
        .opacity(s.isEmpty ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lock screen weather and batteries")
    }

    private func weatherCard(_ w: LockScreenSummary.Weather) -> some View {
        HStack(spacing: 12) {
            Image(systemName: w.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(w.temperature)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                Text(w.place.isEmpty ? w.detail : "\(w.place) · \(w.detail)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Self.cardHeight)
        .background(card)
    }

    private func batteryCard(_ devices: [LockScreenSummary.Device]) -> some View {
        HStack(spacing: 18) {
            ForEach(devices) { device in
                VStack(spacing: 7) {
                    BatteryRing(device: device)
                    Text("\(device.level)%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .help(device.name)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Self.cardHeight)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }
}

/// iOS-style battery ring: the device glyph inside a ring filled to its level; green, red at ≤ 20 %, a bolt when charging.
private struct BatteryRing: View {
    let device: LockScreenSummary.Device

    private var tint: Color { device.level <= 20 && !device.isCharging ? Color(red: 1, green: 0.27, blue: 0.23) : Color(red: 0.2, green: 0.84, blue: 0.29) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(device.level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: device.symbol)
                .font(.system(size: 17, weight: .medium))
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(y: -27)
            }
        }
        .frame(width: 50, height: 50)
    }
}
