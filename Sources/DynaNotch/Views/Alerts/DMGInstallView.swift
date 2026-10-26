import AppKit
import SwiftUI
import DynaNotchCore

/// Small "Install <App>?" window shown by `DMGInstaller` when a disk image with one app mounts.
struct DMGInstallView: View {
    @ObservedObject var installer: DMGInstaller

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            icon
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                buttons
            }
        }
        .padding(EdgeInsets(top: 30, leading: 20, bottom: 18, trailing: 20))
        .frame(width: 380, height: 200, alignment: .topLeading)
    }

    private var appName: String { installer.offer?.appName ?? "App" }

    @ViewBuilder private var icon: some View {
        if let url = installer.offer?.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 40))
        }
    }

    private var title: String {
        switch installer.phase {
        case .offer: return "Install \(appName)?"
        case .confirmReplace: return "Replace \(appName)?"
        case .installing: return "Installing \(appName)…"
        case .done: return "\(appName) is installed"
        case .failed: return "Couldn't install \(appName)"
        }
    }

    private var message: String {
        switch installer.phase {
        case .offer:
            return "Copies it to your Applications folder, then ejects the disk image."
        case .confirmReplace:
            return "Applications already has \(appName). The old copy goes to the Trash."
        case .installing:
            return "Copying to Applications…"
        case .done:
            return "It's in your Applications folder."
        case .failed(let reason):
            return reason
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            switch installer.phase {
            case .offer:
                Button("Not Now") { installer.close() }
                    .keyboardShortcut(.cancelAction)
                    .uiTestID("dmg.notNow")
                Button("Install") { installer.install() }
                    .keyboardShortcut(.defaultAction)
                    .uiTestID("dmg.install")
            case .confirmReplace:
                Button("Cancel") { installer.close() }
                    .keyboardShortcut(.cancelAction)
                    .uiTestID("dmg.cancel")
                Button("Replace") { installer.install() }
                    .tint(.red)
                    .uiTestID("dmg.replace")
            case .installing:
                ProgressView().controlSize(.small)
            case .done:
                Button("Done") { installer.close() }
                    .keyboardShortcut(.cancelAction)
                    .uiTestID("dmg.done")
                Button("Open") { installer.openInstalled() }
                    .keyboardShortcut(.defaultAction)
                    .uiTestID("dmg.open")
            case .failed:
                Button("Close") { installer.close() }
                    .keyboardShortcut(.defaultAction)
                    .uiTestID("dmg.close")
            }
        }
    }
}
