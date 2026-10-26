import AppKit
import Combine
import CoreGraphics
import Foundation
import os

/// JSON persistence helpers for small app data files (App Support) and `dn.data.*` UserDefaults blobs.
enum AppDataStore {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "datastore")
    private static let ioQueue = DispatchQueue(label: "com.tanim.dynanotch.datastore", qos: .utility)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DynaNotch", isDirectory: true)
    }

    static func url(_ file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    static func loadFile<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let data = try? Data(contentsOf: url(file)) else { return nil }
        do {
            return try decoder().decode(type, from: data)
        } catch {
            logger.error("\(file, privacy: .public) unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Encodes on the caller's thread, writes atomically on a background queue.
    static func saveFile<T: Encodable>(_ value: T, file: String) {
        let data: Data
        do {
            data = try encoder().encode(value)
        } catch {
            logger.error("could not encode \(file, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let target = url(file)
        let dir = directory
        ioQueue.async {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            } catch {
                logger.error("could not save \(file, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func loadDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder().decode(type, from: data)
    }

    static func saveDefaults<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Is the user at the Mac? Tracks screen lock / display sleep / system sleep and HID idle time.
final class UserPresence {
    static let shared = UserPresence()

    /// Fires on the main queue when the user comes back (unlock, wake).
    let returned = PassthroughSubject<Void, Never>()

    private(set) var isLocked = false
    private(set) var isAsleep = false
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Locked, display or system asleep.
    var isAway: Bool { isLocked || isAsleep }

    /// Seconds since the last keyboard / mouse / trackpad event.
    var idleSeconds: TimeInterval {
        let anyInput = CGEventType(rawValue: UInt32.max) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func start() {
        guard !started else { return }
        started = true

        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.isLocked = true }
            .store(in: &cancellables)
        distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isLocked = false
                self?.signalReturn()
            }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspace.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.isAsleep = true }
                .store(in: &cancellables)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspace.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isAsleep = false
                    self?.signalReturn()
                }
                .store(in: &cancellables)
        }
    }

    private func signalReturn() {
        guard !isAway else { return }
        returned.send(())
    }
}
