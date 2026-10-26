import SwiftUI
import AppKit
import DynaNotchCore

/// Track-change sneak peek: compact row plus title · artist below the notch.
struct PeekView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    private var side: CGFloat { IslandLayout.sideWidth(for: .peek, hudStyle: settings.hudStyle) }
    private var radii: IslandRadii { IslandLayout.radii(for: .peek, hudStyle: settings.hudStyle) }

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(notch: vm.notch,
                       side: side,
                       radii: radii,
                       leadingAlignment: .leading,
                       trailingAlignment: .trailing) {
                CompactArtwork()
                    .padding(.leading, 8)
            } trailing: {
                NowPlayingIndicator()
                    .padding(.trailing, 8)
            }
            titleRow
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(nowPlaying.snapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if !nowPlaying.snapshot.artist.isEmpty {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandColors.secondary)
                Text(nowPlaying.snapshot.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(IslandColors.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
    }
}
