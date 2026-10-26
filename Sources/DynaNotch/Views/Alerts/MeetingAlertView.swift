import AppKit
import SwiftUI
import DynaNotchCore

/// Full-screen meeting alert: dimmed, blurred desktop; event title, time and a big Join button.
struct MeetingAlertView: View {
    let item: CalendarItem
    let url: URL
    let onJoin: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            MeetingAlertBlur()
            Color.black.opacity(0.45)
                .contentShape(Rectangle())

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 84, height: 84)
                    Image(systemName: "video.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text(statusText(now: context.date))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Text(item.title)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 720)

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(Format.clockRange(start: item.start, end: item.end))
                    if let host = serviceName {
                        Text("·")
                        Text(host)
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))

                Button(action: onJoin) {
                    HStack(spacing: 10) {
                        Image(systemName: "video.fill")
                        Text("Join")
                    }
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 260, height: 60)
                    .background(Capsule().fill(Color.green))
                    .shadow(color: Color.green.opacity(0.45), radius: 18, y: 6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 14)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 160, height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Text("Esc to dismiss")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(40)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var serviceName: String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Microsoft Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("whereby") { return "Whereby" }
        if host.contains("slack") { return "Slack Huddle" }
        if host.contains("discord") { return "Discord" }
        return host
    }

    private func statusText(now: Date) -> String {
        let seconds = item.start.timeIntervalSince(now)
        if seconds <= 0 { return "Meeting started" }
        if seconds < 60 { return "Starting in \(Int(seconds.rounded(.up))) s" }
        return "Starting " + Format.relativeMinutes(Int((seconds / 60).rounded(.up)))
    }
}

/// Behind-window blur of the desktop.
private struct MeetingAlertBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
