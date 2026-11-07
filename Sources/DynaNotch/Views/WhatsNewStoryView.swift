import SwiftUI
import AppKit
import DynaNotchCore

/// What's New as Stories (CONTRACTS §6.21): the island grows out of the notch, one feature per slide with segmented
/// progress bars on top. Click → next, click the left third → back, hold → pause, ← → Esc. The closing card says
/// "Got it" after an update, or offers "Update Now" with download progress before one.
struct WhatsNewStoryView: View {
    let notch: NotchMetrics
    @ObservedObject var model: StoryModel
    var closer = WelcomeCloser()
    /// The island has shrunk back into the notch: close the window.
    let onClosed: () -> Void

    static let storySize = CGSize(width: 520, height: 318)

    static func canvasSize(notch: NotchMetrics) -> CGSize {
        CGSize(width: storySize.width + 80, height: notch.height + storySize.height + 60)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var pressStart: Date?

    private var islandSize: CGSize {
        open ? CGSize(width: WhatsNewStoryView.storySize.width, height: notch.height + WhatsNewStoryView.storySize.height)
             : CGSize(width: notch.width + 12, height: notch.height)
    }

    private var shape: IslandShape {
        open ? IslandShape(isPill: false, topRadius: 14, bottomRadius: 34)
             : IslandShape(isPill: false, topRadius: 6, bottomRadius: 9)
    }

    private var accent: Color {
        model.isFinal ? (model.mode == .update ? .blue : .green) : StoryColor.named(model.slides[model.index].feature.color)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(open ? 0.45 : 0), radius: 22, y: 10)
                if open {
                    // A soft wash of the slide's colour behind everything.
                    RadialGradient(colors: [accent.opacity(0.32), .clear], center: .init(x: 0.2, y: 0.55),
                                   startRadius: 10, endRadius: 360)
                        .animation(.easeInOut(duration: 0.5), value: model.index)
                    content
                        .padding(.top, notch.height + 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(spring) { open = true }
                model.start()
            }
        }
        .uiTestID("whatsnew.story")
    }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            StoryProgressBars(model: model)
            header
            ZStack(alignment: .topLeading) {
                Group {
                    if model.isFinal {
                        StoryFinalCard(model: model, onDone: close)
                    } else {
                        StorySlideView(slide: model.slides[model.index], accent: accent)
                    }
                }
                .id(model.index)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(press, including: model.isFinal ? .subviews : .all)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.88),
                       value: model.index)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.mode == .update ? "COMING IN \(model.version)" : "NEW IN \(model.version)")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(WelcomeView.gradient))
            if let headline = model.headline {
                Text(headline)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .uiTestID("whatsnew.close")
        }
    }

    private var footer: some View {
        HStack {
            Text(model.isFinal ? " " : (model.paused ? "Paused — let go to continue" : "Click for next · hold to pause"))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
            if !model.isFinal {
                Text("\(model.index + 1) / \(model.slides.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.45))
                Button("Skip") { model.go(to: model.slides.count) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.leading, 8)
                    .uiTestID("whatsnew.skip")
            }
        }
    }

    /// Press and hold pauses; a short press is a tap: left third goes back, the rest forward. Swipes work too.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                guard pressStart == nil else { return }
                pressStart = Date()
                model.setPaused(true)
            }
            .onEnded { value in
                let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                pressStart = nil
                model.setPaused(false)
                if value.translation.width < -40 {
                    model.next()
                } else if value.translation.width > 40 {
                    model.previous()
                } else if held < 0.3 {
                    let width = WhatsNewStoryView.storySize.width - 48
                    value.startLocation.x < width / 3 ? model.previous() : model.next()
                }
            }
    }

    /// Esc, ×, Got it, Later: shrink back into the notch, then close the window.
    private func close() {
        guard open else { return }
        model.stop()
        withAnimation(spring) { open = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 0.45), execute: onClosed)
    }
}

/// One segment per slide (and the closing card): done = full, current = filling, upcoming = empty.
struct StoryProgressBars: View {
    @ObservedObject var model: StoryModel

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: model.paused || model.isFinal)) { context in
            let current = min(1, max(0, model.elapsed(at: context.date) / StoryModel.slideDuration))
            HStack(spacing: 4) {
                ForEach(0..<model.count, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(Color.white.opacity(0.92))
                                .frame(width: geo.size.width * fill(i, current: current))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Slide \(model.index + 1) of \(model.count)")
    }

    private func fill(_ i: Int, current: Double) -> CGFloat {
        if i < model.index { return 1 }
        if i > model.index { return 0 }
        return model.isFinal ? 1 : CGFloat(current)
    }
}

struct StorySlideView: View {
    let slide: StorySlide
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .shadow(color: accent.opacity(0.55), radius: 22)
                Image(systemName: slide.feature.symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text(slide.feature.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(slide.feature.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The last card: "Got it" after an update, "Update Now" with progress before one.
struct StoryFinalCard: View {
    @ObservedObject var model: StoryModel
    @EnvironmentObject var updates: UpdateService
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                Circle()
                    .fill(model.mode == .update ? AnyShapeStyle(WelcomeView.gradient) : AnyShapeStyle(Color.green))
                    .shadow(color: (model.mode == .update ? Color.purple : Color.green).opacity(0.5), radius: 22)
                Image(systemName: model.mode == .update ? "arrow.down" : "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                controls
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var title: String {
        guard model.mode == .update else { return "You're all set" }
        switch updates.status {
        case .downloading: return "Downloading…"
        case .installing: return "Installing…"
        case .failed: return "Update didn't finish"
        default: return "DynaNotch \(model.version) is ready"
        }
    }

    private var detail: String {
        guard model.mode == .update else {
            return "That's what's new in DynaNotch \(model.version). Replay it any time from the menu bar or Settings → About."
        }
        switch updates.status {
        case .downloading, .installing: return "DynaNotch restarts by itself in a moment. Your settings and permissions stay."
        case .failed(let message): return message
        default: return "Takes a few seconds, then DynaNotch restarts. Your settings and permissions stay."
        }
    }

    @ViewBuilder
    private var controls: some View {
        if model.mode == .whatsNew {
            StoryButton(title: "Got it", prominent: true, action: onDone)
                .uiTestID("whatsnew.done")
        } else {
            switch updates.status {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Color.white)
                    .frame(width: 220)
            case .installing:
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.white)
                    .frame(width: 220)
            default:
                HStack(spacing: 10) {
                    StoryButton(title: isFailed ? "Try Again" : "Update Now", prominent: true) { updates.install() }
                        .uiTestID("whatsnew.update")
                    StoryButton(title: "Later", prominent: false, action: onDone)
                        .uiTestID("whatsnew.later")
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = updates.status { return true }
        return false
    }
}

struct StoryButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

enum StoryColor {
    static func named(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "gray": return .gray
        default: return .purple
        }
    }
}
