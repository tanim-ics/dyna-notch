import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import CoreLocation
import EventKit
import Foundation
import os

/// A plain-text report of every permission's state, app version, macOS version and code-signing requirement,
/// for Settings → Permissions → Copy Diagnostics.
enum PermissionDiagnostics {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "diagnostics")

    static func report() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var lines: [String] = []
        lines.append("DynaNotch \(version) (\(build))")
        lines.append("Bundle ID: \(bundle.bundleIdentifier ?? "none")")
        lines.append("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        lines.append("Bundle: \(bundle.bundlePath)")
        lines.append("Designated requirement: \(designatedRequirement(path: bundle.bundlePath))")
        lines.append("")
        lines.append("Permissions")
        lines.append("  Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
        lines.append("  Calendar: \(eventKit(EKEventStore.authorizationStatus(for: .event)))")
        lines.append("  Reminders: \(eventKit(EKEventStore.authorizationStatus(for: .reminder)))")
        lines.append("  Camera: \(capture(AVCaptureDevice.authorizationStatus(for: .video)))")
        lines.append("  Microphone: \(capture(AVCaptureDevice.authorizationStatus(for: .audio)))")
        lines.append("  Full Disk Access: \(fullDiskAccess() ? "granted (Focus database readable)" : "not granted")")
        lines.append("  Location: \(location(CLLocationManager().authorizationStatus))")
        lines.append("  Bluetooth: \(bluetooth(CBManager.authorization))")
        lines.append("  Screen Recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")")
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    /// `codesign -d -r- <bundle>` with a 3 s timeout.
    private static func designatedRequirement(path: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-d", "-r-", path]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do {
            try task.run()
        } catch {
            logger.error("codesign failed: \(error.localizedDescription, privacy: .public)")
            return "unavailable (\(error.localizedDescription))"
        }
        // Small output: read it all (also prevents the pipe from filling up), then wait for exit.
        var data = Data()
        let reader = DispatchQueue.global(qos: .userInitiated)
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
            return "timed out"
        }
        _ = readDone.wait(timeout: .now() + 1)
        let text = String(data: data, encoding: .utf8) ?? ""
        let requirement = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("designated =>") }
        if let requirement = requirement { return String(requirement.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespaces) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "none" : trimmed.replacingOccurrences(of: "\n", with: " · ")
    }

    private static func eventKit(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: return "granted (full access)"
        case .writeOnly: return "write-only"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    private static func capture(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    private static func location(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        default: return "granted"
        }
    }

    private static func bluetooth(_ status: CBManagerAuthorization) -> String {
        switch status {
        case .allowedAlways: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    /// Full Disk Access probe: the Focus database folder can only be listed with FDA.
    private static func fullDiskAccess() -> Bool {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/DoNotDisturb/DB")
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}
