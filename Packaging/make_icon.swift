#!/usr/bin/env swift
// make_icon.swift — renders the DynaNotch app icon into an .iconset directory.
//
// Usage:  swift Packaging/make_icon.swift build/AppIcon.iconset
//         iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
//
// Standalone: AppKit only, no external dependencies. Called by build.sh (non-fatal).

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(64)
}
let outputDir = URL(fileURLWithPath: arguments[1], isDirectory: true)

do {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
} catch {
    FileHandle.standardError.write("make_icon: cannot create \(outputDir.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    return NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

/// Draws the icon into the current graphics context, in a square of `s` points (origin bottom-left).
func drawIcon(size s: CGFloat) {
    // macOS icon grid: the rounded-square body is ~80.5 % of the canvas, centred.
    let margin = s * 0.0977
    let body = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let corner = body.width * 0.225

    // Drop shadow under the body.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
    rgba(30, 30, 46).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background: deep graphite to indigo gradient.
    if let background = NSGradient(colors: [rgba(18, 18, 26), rgba(36, 34, 64), rgba(64, 52, 128)]) {
        background.draw(in: bodyPath, angle: 90)
    }

    // Soft top sheen on the body.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    let sheenRect = NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
    if let sheen = NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 0.0),
                              ending: NSColor(calibratedWhite: 1.0, alpha: 0.08)) {
        sheen.draw(in: sheenRect, angle: 90)
    }
    NSGraphicsContext.restoreGraphicsState()

    // The island capsule, centred.
    let islandWidth = body.width * 0.74
    let islandHeight = body.width * 0.24
    let island = NSRect(x: body.midX - islandWidth / 2, y: body.midY - islandHeight / 2,
                        width: islandWidth, height: islandHeight)
    let islandPath = NSBezierPath(roundedRect: island, xRadius: islandHeight / 2, yRadius: islandHeight / 2)

    NSGraphicsContext.saveGraphicsState()
    let islandShadow = NSShadow()
    islandShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.55)
    islandShadow.shadowBlurRadius = s * 0.03
    islandShadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    islandShadow.set()
    NSColor.black.setFill()
    islandPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Subtle white highlight along the top of the capsule.
    NSGraphicsContext.saveGraphicsState()
    islandPath.addClip()
    let highlightRect = NSRect(x: island.minX, y: island.midY, width: island.width, height: island.height / 2)
    if let highlight = NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 0.0),
                                  ending: NSColor(calibratedWhite: 1.0, alpha: 0.16)) {
        highlight.draw(in: highlightRect, angle: 90)
    }
    NSGraphicsContext.restoreGraphicsState()

    // Thin rim so the capsule reads against the dark background.
    NSGraphicsContext.saveGraphicsState()
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: island.insetBy(dx: s * 0.002, dy: s * 0.002),
                           xRadius: islandHeight / 2, yRadius: islandHeight / 2)
    rim.lineWidth = max(0.5, s * 0.004)
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Small "artwork" tile on the left of the capsule.
    let art = islandHeight * 0.54
    let artRect = NSRect(x: island.minX + islandHeight * 0.30, y: island.midY - art / 2, width: art, height: art)
    let artPath = NSBezierPath(roundedRect: artRect, xRadius: art * 0.26, yRadius: art * 0.26)
    if let artGradient = NSGradient(starting: rgba(255, 94, 120), ending: rgba(255, 170, 64)) {
        artGradient.draw(in: artPath, angle: 45)
    }

    // Visualiser bars on the right, green to teal.
    let heights: [CGFloat] = [0.38, 0.72, 0.52, 0.88, 0.46]
    let barWidth = islandHeight * 0.085
    let gap = islandHeight * 0.075
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = island.maxX - islandHeight * 0.34 - totalWidth
    let maxBar = islandHeight * 0.56
    for fraction in heights {
        let h = max(barWidth, maxBar * fraction)
        let barRect = NSRect(x: x, y: island.midY - h / 2, width: barWidth, height: h)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        if let barGradient = NSGradient(starting: rgba(48, 209, 88), ending: rgba(64, 200, 224)) {
            barGradient.draw(in: barPath, angle: 90)
        }
        x += barWidth + gap
    }
}

func renderPNG(pixels: Int, to url: URL) -> Bool {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        return false
    }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return false
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    drawIcon(size: CGFloat(pixels))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        return false
    }
    do {
        try data.write(to: url)
        return true
    } catch {
        return false
    }
}

let baseSizes = [16, 32, 128, 256, 512]
var failures = 0
for base in baseSizes {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let url = outputDir.appendingPathComponent(name)
        if !renderPNG(pixels: base * scale, to: url) {
            FileHandle.standardError.write("make_icon: failed to render \(name)\n".data(using: .utf8)!)
            failures += 1
        }
    }
}

if failures > 0 {
    exit(1)
}
print("make_icon: wrote \(baseSizes.count * 2) images to \(outputDir.path)")
