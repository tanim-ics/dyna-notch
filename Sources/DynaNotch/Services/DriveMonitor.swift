import AppKit
import Foundation
import Combine

/// External volumes mounting / unmounting (internal disks, disk images of the system and network shares are ignored).
final class DriveMonitor {
    static let shared = DriveMonitor()

    let events = PassthroughSubject<(name: String, mounted: Bool), Never>()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    /// Volumes we announced as mounted (unmount notifications can no longer read resource values).
    private var externalVolumes: [String: String] = [:]   // path → name

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        // Seed with what is already mounted so unmounting a drive plugged in before launch is still reported.
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
                                      .volumeLocalizedNameKey, .volumeIsLocalKey]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            if let name = DriveMonitor.externalName(of: url) { externalVolumes[url.path] = name }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didMountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handle(note, mounted: true) }
            .store(in: &cancellables)
        center.publisher(for: NSWorkspace.didUnmountNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handle(note, mounted: false) }
            .store(in: &cancellables)
    }

    private func handle(_ note: Notification, mounted: Bool) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        if mounted { DMGInstaller.shared.volumeMounted(url) } else { DMGInstaller.shared.volumeUnmounted(url) }
        if mounted {
            guard let name = DriveMonitor.externalName(of: url) else { return }
            externalVolumes[url.path] = name
            events.send((name: name, mounted: true))
        } else {
            guard let name = externalVolumes.removeValue(forKey: url.path) else { return }
            events.send((name: name, mounted: false))
        }
    }

    /// Display name if the volume is a local external / removable drive, else nil.
    private static func externalName(of url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
                                         .volumeLocalizedNameKey, .volumeIsLocalKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        if values.volumeIsLocal == false { return nil }   // network shares
        let external = values.volumeIsInternal == false
            || values.volumeIsRemovable == true
            || values.volumeIsEjectable == true
        guard external else { return nil }
        // Mounted installer / app disk images are ejectable but live in /Volumes as well; keep them — Notchy shows them too.
        return values.volumeLocalizedName ?? url.lastPathComponent
    }
}
