import AppKit
import Combine
import Foundation
import SwiftUI
import os
import DynaNotchCore

/// Settings → Files → App install offer: when a disk image mounts with exactly one app at its root, shows a notification
/// island and a small window offering to copy the app to /Applications (never overwriting without asking, an
/// existing copy goes to the Trash), then ejects the image. Fed by `DriveMonitor`.
final class DMGInstaller: ObservableObject {
    static let shared = DMGInstaller()

    enum Phase: Equatable {
        case offer
        case confirmReplace
        case installing
        case done
        case failed(String)
    }

    struct Offer: Equatable {
        let appURL: URL          // the .app inside the mounted image
        let volumeURL: URL
        var appName: String { appURL.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var offer: Offer?
    @Published private(set) var phase: Phase = .offer

    /// Destination folder; `DYNANOTCH_INSTALL_DIR` redirects it (tests).
    static var applicationsURL: URL {
        if let path = ProcessInfo.processInfo.environment["DYNANOTCH_INSTALL_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    /// For scripted UI tests (`dynanotch://ui/click?window=dmg…` once wired in AppDelegate).
    var testWindow: NSWindow? { window }

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "dmg")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.dmg", qos: .userInitiated)
    private var window: NSPanel?

    private init() {}

    var destinationURL: URL? {
        offer.map { DMGInstaller.applicationsURL.appendingPathComponent($0.appURL.lastPathComponent) }
    }

    // MARK: Detection (called on main by DriveMonitor)

    func volumeMounted(_ volumeURL: URL) {
        guard AppSettings.shared.dmgInstallOffer else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            guard DMGInstaller.isDiskImage(volumeURL), let app = DMGInstaller.singleApp(in: volumeURL) else { return }
            // Already running from /Applications with the same name? Still offer — it may be an update.
            DispatchQueue.main.async {
                guard AppSettings.shared.dmgInstallOffer else { return }
                self.present(Offer(appURL: app, volumeURL: volumeURL))
            }
        }
    }

    func volumeUnmounted(_ volumeURL: URL) {
        guard let offer = offer, offer.volumeURL.standardizedFileURL.path == volumeURL.standardizedFileURL.path,
              phase == .offer || phase == .confirmReplace else { return }
        close()
    }

    // MARK: Actions (main queue, from the alert view)

    func install() {
        guard let offer = offer, let destination = destinationURL else { return }
        if FileManager.default.fileExists(atPath: destination.path), phase != .confirmReplace {
            phase = .confirmReplace
            return
        }
        let replacing = phase == .confirmReplace
        phase = .installing
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if replacing, fm.fileExists(atPath: destination.path) {
                    try fm.trashItem(at: destination, resultingItemURL: nil)
                }
                try fm.copyItem(at: offer.appURL, to: destination)
                self.logger.info("installed \(offer.appName, privacy: .public) to \(destination.path, privacy: .public)")
                let ejected = DMGInstaller.detach(offer.volumeURL)
                if !ejected { self.logger.error("could not eject \(offer.volumeURL.path, privacy: .public)") }
                DispatchQueue.main.async {
                    self.phase = .done
                    ScreenRecorder.notify(title: "\(offer.appName) installed",
                                          body: ejected ? "Disk image ejected" : "In Applications",
                                          symbol: "checkmark.circle.fill", category: .downloads)
                }
            } catch {
                self.logger.error("install failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    func openInstalled() {
        if let destination = destinationURL { NSWorkspace.shared.open(destination) }
        close()
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        offer = nil
        phase = .offer
    }

    // MARK: Private

    private func present(_ new: Offer) {
        if phase == .installing { return }   // one at a time
        offer = new
        phase = .offer
        ScreenRecorder.notify(title: "Install \(new.appName)?", body: "Disk image mounted", symbol: "arrow.down.app.fill",
                              category: .downloads)
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                                styleMask: [.titled, .closable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.title = "Install App"
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: DMGInstallView(installer: self))
            window = panel
        }
        guard let panel = window else { return }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 60))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["DYNANOTCH_DMG_AUTOCONFIRM"] == "1" {
            // Scripted test: press Install (and Replace) like a user would.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.install()
                if self?.phase == .confirmReplace { self?.install() }
            }
        }
    }

    /// `hdiutil detach` (fast, unlike NSWorkspace's eject which can wait ~15 s); falls back to NSWorkspace.
    static func detach(_ volumeURL: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", volumeURL.path, "-quiet"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        if (try? task.run()) != nil {
            task.waitUntilExit()
            if task.terminationStatus == 0 { return true }
        }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
            return true
        } catch {
            return false
        }
    }

    /// True when `hdiutil info` lists the volume as the mount point of an attached image.
    static func isDiskImage(_ volumeURL: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return false }
        let target = volumeURL.standardizedFileURL.path
        for image in images {
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                if let mount = entity["mount-point"] as? String, URL(fileURLWithPath: mount).standardizedFileURL.path == target {
                    return true
                }
            }
        }
        return false
    }

    /// The only visible `.app` directly inside the volume (symlinks such as "Applications" ignored), else nil.
    static func singleApp(in volumeURL: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: volumeURL, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        let apps = items.filter { url in
            url.pathExtension.lowercased() == "app"
                && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        }
        return apps.count == 1 ? apps.first : nil
    }
}
