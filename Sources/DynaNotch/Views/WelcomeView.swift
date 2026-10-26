import SwiftUI
import AppKit
import DynaNotchCore

/// First-launch greeting as an island pop-up: it grows out of the notch, the handwritten "hello" draws itself,
/// "Welcome to DynaNotch" fades in, then (first launch only) the tips play as self-advancing slides. It always ends by
/// morphing into the real panel (`onHandOff`), so the intro flows straight into the app.
struct WelcomeView: View {
    let notch: NotchMetrics
    let greetingOnly: Bool
    /// The real expanded panel's size — the island morphs into it at the end.
    let handOffSize: CGSize
    var closer = WelcomeCloser()
    /// The island has taken the panel's shape: open the real panel underneath and fade this window out.
    let onHandOff: () -> Void

    private enum Phase: Equatable { case closed, hello, welcome, tips, handOff }

    static let helloSize = CGSize(width: 560, height: 256)
    static let tipsSize = CGSize(width: 460, height: 150)
    /// Seconds each tip slide stays up.
    static let slideDuration: TimeInterval = 3.4

    /// Window canvas: room for the largest island (hello or the panel it turns into) plus its shadow.
    static func canvasSize(notch: NotchMetrics, handOff: CGSize) -> CGSize {
        CGSize(width: max(helloSize.width, handOff.width) + 80,
               height: max(notch.height + helloSize.height, handOff.height) + 60)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .closed
    @State private var drawn: CGFloat = 0
    @State private var tipIndex = 0
    @State private var slideStart = Date()
    @State private var slideGeneration = 0

    static let gradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 1.0),
                 Color(red: 1.0, green: 0.33, blue: 0.6), Color(red: 1.0, green: 0.55, blue: 0.25)],
        startPoint: .leading, endPoint: .trailing)

    private var islandSize: CGSize {
        switch phase {
        case .closed: return CGSize(width: notch.width + 12, height: notch.height)
        case .hello, .welcome: return CGSize(width: WelcomeView.helloSize.width, height: notch.height + WelcomeView.helloSize.height)
        case .tips: return CGSize(width: WelcomeView.tipsSize.width, height: notch.height + WelcomeView.tipsSize.height)
        case .handOff: return handOffSize
        }
    }

    private var shape: IslandShape {
        switch phase {
        case .closed: return IslandShape(isPill: false, topRadius: 6, bottomRadius: 9)
        case .handOff: return IslandShape(isPill: false, topRadius: 14, bottomRadius: 28)   // the panel's radii
        default: return IslandShape(isPill: false, topRadius: 14, bottomRadius: 34)
        }
    }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(phase == .closed ? 0 : 0.45), radius: 22, y: 10)
                if phase != .closed && phase != .handOff {
                    content
                        .padding(.top, notch.height)
                        .transition(.opacity)
                }
            }
            .frame(width: islandSize.width, height: islandSize.height)
            .clipShape(shape)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onAppear {
            closer.close = handOff
            closer.next = { advance(by: 1) }
            closer.previous = { advance(by: -1) }
            play()
        }
    }

    @ViewBuilder
    private var content: some View {
        if phase == .tips {
            WelcomeSlidesView(index: tipIndex, slideStart: slideStart, onSkip: handOff, onAdvance: { advance(by: 1) })
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .uiTestID("welcome.slides")
        } else {
            VStack(spacing: 0) {
                HelloShape()
                    .trim(from: 0, to: drawn)
                    .stroke(WelcomeView.gradient,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    .frame(width: 300, height: 142)
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 1.0).opacity(0.4), radius: 16)
                    .scaleEffect(phase == .welcome ? 0.72 : 1)
                    .padding(.top, phase == .welcome ? 12 : 50)
                if phase == .welcome {
                    welcome
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var welcome: some View {
        VStack(spacing: 6) {
            Text("Welcome to DynaNotch")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("Your notch, reimagined — music, timers, clipboard and more, one hover away.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .offset(y: -6)
    }

    // MARK: Sequence

    private func play() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(spring) { phase = .hello }
            let drawTime: TimeInterval
            if reduceMotion {
                drawn = 1
                drawTime = 0.8
            } else {
                withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: 2.6).delay(0.35)) { drawn = 1 }
                drawTime = 3.3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + drawTime) {
                guard phase == .hello else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { phase = .welcome }
                // Read the welcome line, then move on by itself — no button to press.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    guard phase == .welcome else { return }
                    if greetingOnly {
                        handOff()
                    } else {
                        withAnimation(spring) { phase = .tips }
                        startSlide(0)
                    }
                }
            }
        }
    }

    /// Shows slide `index` and schedules the next one (a newer slide cancels the old timer via the generation).
    private func startSlide(_ index: Int) {
        slideGeneration += 1
        let generation = slideGeneration
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) {
            tipIndex = index
        }
        slideStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + WelcomeView.slideDuration) {
            guard generation == slideGeneration, phase == .tips else { return }
            advance(by: 1)
        }
    }

    /// Click / → / ← on the slides; past the last slide the intro hands off to the app.
    private func advance(by step: Int) {
        guard phase == .tips else { return }
        let next = tipIndex + step
        if next >= WelcomeTip.all.count {
            handOff()
        } else {
            startSlide(max(0, next))
        }
    }

    /// End of the intro (last slide, Skip, Esc): the island takes the panel's shape, the real panel opens under it.
    func handOff() {
        guard phase != .handOff else { return }
        slideGeneration += 1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.86)) {
            phase = .handOff
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 0.42), execute: onHandOff)
    }
}

/// Lets the controller's Esc handler reach the view's `close()`.
final class WelcomeCloser {
    var close: (() -> Void)?
    var next: (() -> Void)?
    var previous: (() -> Void)?
}

// MARK: - Tips

struct WelcomeTip {
    let symbol: String
    let title: String
    let text: String

    static let all: [WelcomeTip] = [
        WelcomeTip(symbol: "cursorarrow.motionlines", title: "Hover the Notch",
                   text: "Move the pointer to the notch to open your panel — music, timers, clipboard, files and more."),
        WelcomeTip(symbol: "square.grid.2x2.fill", title: "Switch Tabs",
                   text: "Click the tab pill or the ⋯ menu, or press ⌘1–⌘9 while the panel is open."),
        WelcomeTip(symbol: "tray.and.arrow.down.fill", title: "Drop Files on the Notch",
                   text: "Drag files to the notch to park them on the Shelf, then drag them out into any app."),
        WelcomeTip(symbol: "battery.75percent", title: "All Your Batteries",
                   text: "Rest the pointer on the battery pill to see your Mac, AirPods, mouse and keyboard at a glance."),
        WelcomeTip(symbol: "keyboard.fill", title: "From Anywhere",
                   text: "⌃⌥N opens the panel and ⌃⌥V your clipboard history. Settings live in the menu-bar icon."),
    ]
}

/// The tips as a self-playing slideshow: each slide pushes in from the right, a Stories-style bar shows how long it
/// stays; click anywhere (or →) for the next one, Skip goes straight into the app.
struct WelcomeSlidesView: View {
    let index: Int
    let slideStart: Date
    let onSkip: () -> Void
    let onAdvance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            ZStack(alignment: .topLeading) {
                WelcomeSlide(tip: WelcomeTip.all[index])
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            HStack {
                Text("Click for the next tip")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .uiTestID("welcome.skip")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onAdvance)
        .environment(\.colorScheme, .dark)
    }

    /// One segment per slide: done = full, current = filling over the slide's duration, upcoming = empty.
    private var progress: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(slideStart)
            let current = min(1, max(0, elapsed / WelcomeView.slideDuration))
            HStack(spacing: 4) {
                ForEach(0..<WelcomeTip.all.count, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(Color.white.opacity(0.9))
                                .frame(width: geo.size.width * CGFloat(i < index ? 1 : (i == index ? current : 0)))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }
}

struct WelcomeSlide: View {
    let tip: WelcomeTip

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 5) {
                Text(tip.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(tip.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
