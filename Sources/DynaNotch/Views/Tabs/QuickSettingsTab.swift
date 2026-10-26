import SwiftUI
import AppKit
import DynaNotchCore

/// Quick Settings: switch tiles for the settings people flip most, bound live to AppSettings and services.
struct QuickSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var keepAwake: KeepAwakeService
    @EnvironmentObject var audio: AudioDeviceService
    @EnvironmentObject var vm: IslandViewModel

    private struct Tile: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let tint: Color
        let isOn: Bool
        let toggle: () -> Void
    }

    private var breaksOn: Bool { settings.breakLookAway || settings.breakStandUp || settings.breakDrinkWater }

    private var tiles: [Tile] {
        let s = settings
        return [
            Tile(id: "keepAwake", title: "Keep Awake", symbol: "cup.and.saucer.fill", tint: Color(red: 1, green: 0.75, blue: 0.3),
                 isOn: keepAwake.isOn, toggle: { keepAwake.toggle() }),
            Tile(id: "micMute", title: "Mute Mic", symbol: audio.isMicMuted ? "mic.slash.fill" : "mic.fill",
                 tint: IslandColors.low, isOn: audio.isMicMuted, toggle: { audio.toggleMicMute() }),
            Tile(id: "expandOnHover", title: "Open on Hover", symbol: "cursorarrow.motionlines", tint: .blue,
                 isOn: s.expandOnHover, toggle: { s.expandOnHover.toggle() }),
            Tile(id: "autoCollapse", title: "Auto Collapse", symbol: "arrow.down.right.and.arrow.up.left", tint: .blue,
                 isOn: s.autoCollapse, toggle: { s.autoCollapse.toggle() }),
            Tile(id: "nowPlaying", title: "Now Playing", symbol: "music.note", tint: .pink,
                 isOn: s.nowPlayingEnabled && s.showCompactNowPlaying, toggle: {
                     let on = !(s.nowPlayingEnabled && s.showCompactNowPlaying)
                     if on { s.nowPlayingEnabled = true }
                     s.showCompactNowPlaying = on
                 }),
            Tile(id: "lyrics", title: "Synced Lyrics", symbol: "quote.bubble.fill", tint: .pink,
                 isOn: s.lyricsEnabled, toggle: { s.lyricsEnabled.toggle() }),
            Tile(id: "lyricsOnPill", title: "Lyrics on Pill", symbol: "text.bubble.fill", tint: .pink,
                 isOn: s.lyricsEnabled && s.lyricsInCompact, toggle: {
                     let on = !(s.lyricsEnabled && s.lyricsInCompact)
                     if on { s.lyricsEnabled = true }
                     s.lyricsInCompact = on
                 }),
            Tile(id: "replaceHUD", title: "Volume HUD", symbol: "speaker.wave.2.fill", tint: .teal,
                 isOn: s.hudEnabled && s.replaceSystemHUD, toggle: {
                     let on = !(s.hudEnabled && s.replaceSystemHUD)
                     if on { s.hudEnabled = true }
                     s.replaceSystemHUD = on
                 }),
            Tile(id: "hideFullscreen", title: "Hide in Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                 tint: .indigo, isOn: s.hideInFullscreen, toggle: { s.hideInFullscreen.toggle() }),
            Tile(id: "glass", title: "Glass Panel", symbol: "square.on.square.intersection.dashed", tint: .cyan,
                 isOn: s.islandMaterial == .glass, toggle: { s.islandMaterial = s.islandMaterial == .glass ? .black : .glass }),
            Tile(id: "breaks", title: "Break Reminders", symbol: "figure.stand", tint: .green,
                 isOn: breaksOn, toggle: {
                     if breaksOn {
                         s.breakLookAway = false
                         s.breakStandUp = false
                         s.breakDrinkWater = false
                     } else {
                         s.breakLookAway = true
                         s.breakStandUp = true
                         s.breakDrinkWater = true
                     }
                 }),
            Tile(id: "quietFocus", title: "Quiet in Focus", symbol: "moon.fill", tint: .indigo,
                 isOn: s.quietDuringFocus, toggle: { s.quietDuringFocus.toggle() }),
            Tile(id: "peekOnHover", title: "Peek on Hover", symbol: "eye.fill", tint: .orange,
                 isOn: s.peekOnHover, toggle: { s.peekOnHover.toggle() }),
            Tile(id: "screenPrivacy", title: "Hide in Shares", symbol: "rectangle.on.rectangle.slash", tint: .orange,
                 isOn: s.screenSharingPrivacy, toggle: { s.screenSharingPrivacy.toggle() }),
            Tile(id: "haptics", title: "Haptics", symbol: "hand.tap.fill", tint: .purple,
                 isOn: s.hapticFeedback, toggle: { s.hapticFeedback.toggle() }),
            Tile(id: "pin", title: "Pin Panel", symbol: vm.isPinned ? "pin.fill" : "pin", tint: .white,
                 isOn: vm.isPinned, toggle: { vm.togglePin() }),
        ]
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(tiles) { tile in
                    QuickSettingTile(title: tile.title, symbol: tile.symbol, tint: tile.tint, isOn: tile.isOn,
                                     action: tile.toggle)
                        .uiTestID("qs.\(tile.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One switch tile: round icon (filled with the tint when on), title, On/Off.
struct QuickSettingTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(isOn ? tint.opacity(0.9) : Color.white.opacity(0.1))
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isOn ? Color.black.opacity(0.75) : Color.white.opacity(0.7))
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 9))
                        .foregroundStyle(PanelStyle.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.12 : 0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .help("\(title): \(isOn ? "On" : "Off")")
        .accessibilityLabel("\(title): \(isOn ? "On" : "Off")")
    }
}
