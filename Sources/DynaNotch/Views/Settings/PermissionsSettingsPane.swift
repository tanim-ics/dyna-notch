import SwiftUI
import AppKit
import Combine
import Foundation
import EventKit
import AVFoundation
import CoreLocation
import CoreBluetooth
import DynaNotchCore

/// Best-effort, side-effect-free permission checks.
enum PermissionStatus {
    case granted, denied, notDetermined

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }

    var title: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .notDetermined: return "Not requested"
        }
    }
}

enum PermissionProbe {
    private static let locationManager = CLLocationManager()

    static var accessibility: PermissionStatus {
        Permissions.accessibilityGranted ? .granted : .denied
    }

    static var fullDiskAccess: PermissionStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [home + "/Library/DoNotDisturb/DB", home + "/Library/Safari"]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil { return .granted }
        }
        return .denied
    }

    /// EventKit raw values: 0 notDetermined, 1 restricted, 2 denied, 3 fullAccess (authorized), 4 writeOnly.
    static func eventKit(_ type: EKEntityType) -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: type).rawValue {
        case 3: return .granted
        case 0: return .notDetermined
        default: return .denied
        }
    }

    static var camera: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static var location: PermissionStatus {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static var bluetooth: PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

struct PermissionsSettingsPane: View {
    @EnvironmentObject var calendar: CalendarService

    @State private var tick = 0
    @State private var showHelp = false
    private let poll = SettingsTicker.tick

    var body: some View {
        let _ = tick   // re-evaluated by the poll so statuses stay live
        SettingsPageView(page: .permissions) {
            Section {
                PermissionRow(symbol: "accessibility", color: .blue, title: "Accessibility",
                              detail: "Replace the volume / brightness HUD and paste from the clipboard.",
                              status: PermissionProbe.accessibility, anchor: "Privacy_Accessibility") {
                    Permissions.requestAccessibility()
                }
                PermissionRow(symbol: "externaldrive.fill", color: .gray, title: "Full Disk Access",
                              detail: "Detect the current Focus mode. Only the Focus database is read.",
                              status: PermissionProbe.fullDiskAccess, anchor: "Privacy_AllFiles", request: nil)
                PermissionRow(symbol: "calendar", color: .red, title: "Calendar",
                              detail: "Up Next, event alerts and meeting alerts.",
                              status: PermissionProbe.eventKit(.event), anchor: "Privacy_Calendars") {
                    calendar.requestAccess()
                }
                PermissionRow(symbol: "checklist", color: .orange, title: "Reminders",
                              detail: "List, add and complete reminders in the Reminders tab.",
                              status: PermissionProbe.eventKit(.reminder), anchor: "Privacy_Reminders") {
                    RemindersService.shared.requestAccess()
                }
                PermissionRow(symbol: "web.camera.fill", color: .green, title: "Camera",
                              detail: "The Mirror tab. The picture never leaves your Mac.",
                              status: PermissionProbe.camera, anchor: "Privacy_Camera") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { tick += 1 }
                    }
                }
                PermissionRow(symbol: "location.fill", color: .blue, title: "Location",
                              detail: "Weather when no city is set. Looked up once, roughly.",
                              status: PermissionProbe.location, anchor: "Privacy_LocationServices", request: nil)
                PermissionRow(symbol: "antenna.radiowaves.left.and.right", color: .blue, title: "Bluetooth",
                              detail: "Battery levels of connected accessories.",
                              status: PermissionProbe.bluetooth, anchor: "Privacy_Bluetooth", request: nil)
            } header: {
                Text("Permissions")
            } footer: {
                SettingsFooter("DynaNotch only asks for what a feature needs. Each feature works without the others.")
            }
            Section {
                SettingRow(symbol: "stethoscope", color: .teal, title: "Copy Diagnostics",
                           detail: "Copies every permission's state, the app and macOS version and the code signature, to paste into a bug report.") {
                    CopyButton(title: "Copy") { PermissionDiagnostics.report() }
                        .uiTestID("setting-copyDiagnostics")
                }
                DisclosureGroup(isExpanded: $showHelp) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remove DynaNotch from the list in System Settings, add it again, then restart DynaNotch. This is often needed after rebuilding the app, because macOS ties the permission to the exact build.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Accessibility Settings…") { Permissions.openAccessibilitySettings() }
                            Button("Restart DynaNotch") { GeneralSettingsPane.restart() }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    SettingLabel(symbol: "questionmark.circle.fill", color: .gray, title: "Still Not Working?",
                                 detail: "A permission shows Granted but the feature doesn't work.")
                }
            }
        }
        .onReceive(poll) { _ in tick += 1 }
    }
}
