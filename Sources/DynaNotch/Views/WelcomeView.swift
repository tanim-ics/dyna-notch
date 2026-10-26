import SwiftUI
import AppKit
import DynaNotchCore

/// First-launch greeting: the handwritten "hello" draws itself, then "Welcome to DynaNotch".
struct WelcomeView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var helloLifted = false
    @State private var showsWelcome = false

    private static let gradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 1.0),
                 Color(red: 1.0, green: 0.33, blue: 0.6), Color(red: 1.0, green: 0.55, blue: 0.25)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI)
            Color.black.opacity(0.62)

            VStack(spacing: 0) {
                HelloShape()
                    .trim(from: 0, to: drawn)
                    .stroke(WelcomeView.gradient,
                            style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                    .frame(width: 520, height: 246)
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 1.0).opacity(0.35), radius: 24)
                    .scaleEffect(helloLifted ? 0.62 : 1)
                    .offset(y: helloLifted ? -40 : 0)

                if showsWelcome {
                    welcome
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear(perform: play)
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Text("Welcome to DynaNotch")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("Your notch, reimagined — music, timers, clipboard and more, one hover away.")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button(action: onFinish) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 30)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 22)
        }
        .offset(y: -30)
    }

    private func play() {
        if reduceMotion {
            drawn = 1
            withAnimation(.easeInOut(duration: 0.3).delay(0.8)) {
                helloLifted = true
                showsWelcome = true
            }
            return
        }
        withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: 2.8)) { drawn = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { helloLifted = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.25)) { showsWelcome = true }
        }
    }
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

/// Notchy-style tip card shown under the notch after the welcome.
struct WelcomeTipsView: View {
    let onFinish: () -> Void

    @State private var index = 0

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
        .padding(16)
        .frame(width: 330)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow)
                Color.black.opacity(0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        )
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
