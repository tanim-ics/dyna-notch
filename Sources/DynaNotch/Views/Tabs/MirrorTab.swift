import SwiftUI
import AppKit
import AVFoundation
import DynaNotchCore

/// Mirror: a live, mirrored camera preview to check yourself before a call. Nothing is recorded.
struct MirrorTab: View {
    @EnvironmentObject var camera: CameraService

    var body: some View {
        Group {
            switch camera.access {
            case .granted:
                preview
            case .notDetermined:
                PanelEmptyState(symbol: "camera.fill", title: "Mirror",
                                detail: "Allow camera access to see yourself before a call")
            case .denied:
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "video.slash.fill", title: "No camera access",
                                    detail: "Allow DynaNotch in System Settings › Privacy & Security › Camera")
                    PanelPillButton(title: "Open System Settings", symbol: "gearshape") { camera.openSystemSettings() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                if let error = camera.errorMessage {
                    PanelEmptyState(symbol: "video.slash", title: error)
                } else {
                    CameraPreview(session: camera.session, isRunning: camera.isRunning)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if !camera.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(camera.isRunning ? PanelStyle.breakTime : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    PanelCaption(camera.isRunning ? "Live" : "Starting")
                }
                Text("Mirror")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                if let name = camera.deviceName {
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.secondary)
                        .lineLimit(2)
                }
                Text("Nothing is recorded. The camera turns off when you leave this tab.")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// AVCaptureVideoPreviewLayer host, mirrored like a real mirror.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let isRunning: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.applyMirroring()
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // Layer-hosting view: assign the layer first, then turn on wantsLayer.
            layer = CALayer()
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            applyMirroring()
        }

        /// The connection only exists once the session has an input, so this is retried on every update.
        func applyMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if !connection.isVideoMirrored {
                connection.isVideoMirrored = true
            }
        }
    }
}
