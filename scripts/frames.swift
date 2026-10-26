// swift frames.swift <video> <outdir> [step-seconds=2] — extract JPEG frames with AVFoundation (no ffmpeg needed).
import AVFoundation
import AppKit
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let out = a[2]; let step = a.count > 3 ? Double(a[3]) ?? 2 : 2
let duration = CMTimeGetSeconds(asset.duration)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: 1400, height: 1400)
var t = 0.0, i = 0
while t < duration {
    if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
       let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
        try? data.write(to: URL(fileURLWithPath: String(format: "%@/f%04d_%06.1f.jpg", out, i, t))); i += 1
    }
    t += step
}
print("duration \(duration)s, \(i) frames")
