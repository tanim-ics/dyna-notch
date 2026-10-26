import AppKit
import AVFoundation
import Combine
import os

/// Front camera preview for the Mirror tab. Runs only while the tab is visible.
final class CameraService: ObservableObject {
    enum Access { case notDetermined, denied, granted }

    static let shared = CameraService()

    let session = AVCaptureSession()
    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var isRunning = false
    /// Set when no camera is connected or the input could not be created.
    @Published private(set) var errorMessage: String?
    @Published private(set) var deviceName: String?

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "Camera")
    private let sessionQueue = DispatchQueue(label: "com.tanim.dynanotch.camera", qos: .userInitiated)
    private var isConfigured = false
    /// Whether the tab currently wants the camera (start/stop may race with the access prompt).
    private var wanted = false
    private var stoppedAt: Date?

    /// True while the Mirror tab uses the camera and for a few seconds after, so the camera-in-use
    /// guard can ignore our own on/off transitions (PrivacyMonitor polls every 1.5 s).
    var isOwnUse: Bool {
        if wanted || isRunning { return true }
        if let stoppedAt = stoppedAt { return Date().timeIntervalSince(stoppedAt) < 4 }
        return false
    }

    private init() {
        access = Self.currentAccess()
    }

    func start() {
        wanted = true
        access = Self.currentAccess()
        switch access {
        case .granted:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.access = granted ? .granted : .denied
                    if granted && self.wanted { self.startSession() }
                }
            }
        case .denied:
            break
        }
    }

    func stop() {
        if wanted { stoppedAt = Date() }
        wanted = false
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.stoppedAt = Date()
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private static func currentAccess() -> Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isConfigured {
                guard self.configure() else { return }
            }
            // A stop() issued meanwhile is queued behind us on the same serial queue.
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    /// Runs on `sessionQueue`.
    private func configure() -> Bool {
        let device = AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                mediaType: .video, position: .unspecified).devices.first
        guard let camera = device else {
            DispatchQueue.main.async { self.errorMessage = "No camera found" }
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.beginConfiguration()
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = "Camera is unavailable" }
                return false
            }
            session.commitConfiguration()
            isConfigured = true
            let name = camera.localizedName
            DispatchQueue.main.async {
                self.errorMessage = nil
                self.deviceName = name
            }
            return true
        } catch {
            logger.error("Camera input failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.errorMessage = "Camera is unavailable" }
            return false
        }
    }
}
