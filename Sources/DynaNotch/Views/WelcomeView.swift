import SwiftUI
import AppKit
import DynaNotchCore

/// First-launch greeting as an island pop-up: it grows out of the notch, the handwritten "hello" draws itself,
/// then "Welcome to DynaNotch" and (first launch only) the tip cards appear in the same island, which finally
/// shrinks back into the notch.
struct WelcomeView: View {
    let notch: NotchMetrics
    let greetingOnly: Bool
    var closer = WelcomeCloser()
    let onFinish: () -> Void

    private enum Phase: Equatable { case closed, hello, welcome, tips, closing }

    static let helloSize = CGSize(width: 560, height: 256)
    static let tipsSize = CGSize(width: 460, height: 178)
    /// Window canvas: room for the largest island plus its shadow.
    static func canvasSize(notch: NotchMetrics) -> CGSize {
        CGSize(width: helloSize.width + 80, height: notch.height + helloSize.height + 60)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .closed
    @State private var drawn: CGFloat = 0
    @State private var tipIndex = 0

    static let gradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 1.0),
                 Color(red: 1.0, green: 0.33, blue: 0.6), Color(red: 1.0, green: 0.55, blue: 0.25)],
        startPoint: .leading, endPoint: .trailing)

    private var isOpen: Bool { phase != .closed && phase != .closing }

    private var islandSize: CGSize {
        switch phase {
        case .closed, .closing: return CGSize(width: notch.width + 12, height: notch.height)
        case .hello, .welcome: return CGSize(width: WelcomeView.helloSize.width, height: notch.height + WelcomeView.helloSize.height)
        case .tips: return CGSize(width: WelcomeView.tipsSize.width, height: notch.height + WelcomeView.tipsSize.height)
        }
    }

    private var shape: IslandShape {
        IslandShape(isPill: false, topRadius: isOpen ? 14 : 6, bottomRadius: isOpen ? 34 : 9)
    }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(isOpen ? 0.45 : 0), radius: 22, y: 10)
                if isOpen {
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
            closer.close = close
            play()
        }
    }

    @ViewBuilder
    private var content: some View {
        if phase == .tips {
            WelcomeTipsView(index: $tipIndex, onFinish: close)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                HelloShape()
                    .trim(from: 0, to: drawn)
                    .stroke(WelcomeView.gradient,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    .frame(width: 300, height: 142)
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 1.0).opacity(0.4), radius: 16)
                    .scaleEffect(phase == .welcome ? 0.72 : 1)
                    .padding(.top, phase == .welcome ? 0 : 50)
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
            Button(action: next) {
                Text(greetingOnly ? "Done" : "Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 24)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)
        }
        .offset(y: -12)
    }

    private func play() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(spring) { phase = .hello }
            if reduceMotion {
                drawn = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .welcome }
                }
                return
            }
            withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: 2.6).delay(0.35)) { drawn = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                guard phase == .hello else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { phase = .welcome }
            }
        }
    }

    /// Get Started: tips on first launch, otherwise back into the notch.
    func next() {
        if greetingOnly {
            close()
        } else {
            withAnimation(spring) { phase = .tips }
        }
    }

    /// Esc / Skip / Done: shrink into the notch, then let the controller remove the window.
    func close() {
        guard phase != .closing else { return }
        withAnimation(spring) { phase = .closing }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: onFinish)
    }
}

/// Lets the controller's Esc handler reach the view's `close()`.
final class WelcomeCloser {
    var close: (() -> Void)?
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
                   text: "Click the battery pill to see your Mac, AirPods, mouse and keyboard at a glance."),
        WelcomeTip(symbol: "keyboard.fill", title: "From Anywhere",
                   text: "⌃⌥N opens the panel and ⌃⌥V your clipboard history. Settings live in the menu-bar icon."),
    ]
}

/// Notchy-style tip cards, shown inside the welcome island after "Get Started".
struct WelcomeTipsView: View {
    @Binding var index: Int
    let onFinish: () -> Void

    private var tip: WelcomeTip { WelcomeTip.all[index] }
    private var isLast: Bool { index == WelcomeTip.all.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tip.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))
                Text(tip.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            Text(tip.text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 34, alignment: .topLeading)
            dots
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<WelcomeTip.all.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == index ? 0.9 : 0.25))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Skip", action: onFinish)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer()
            if index > 0 {
                Button { index -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressableButtonStyle())
            }
            Button {
                if isLast { onFinish() } else { index += 1 }
            } label: {
                Text(isLast ? "Done" : "Next")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 26)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }
}
