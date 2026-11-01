import AppKit
import CoreImage
import Foundation
import ImageIO
import os
import PDFKit
import UniformTypeIdentifiers
import Vision
import DynaNotchCore

/// Drop Alchemy (CONTRACTS §6.15): turns a file into a cutout, its text, a smaller copy or another format — all on
/// this Mac. New files go next to the original and onto the shelf; text goes to the clipboard.
final class AlchemyService {
    static let shared = AlchemyService()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "alchemy")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.alchemy", qos: .userInitiated)
    private(set) var running = 0          // main queue
    private(set) var last = "none"        // main queue

    private struct Failure: Error { let message: String }

    private init() {}

    /// state.json `alchemy`.
    var state: [String: Any] { ["running": running, "last": last] }

    func run(_ action: AlchemyAction, on url: URL) {
        guard action.accepts(fileExtension: url.pathExtension) else {
            finish(action, url, .failure(Failure(message: "\(action.title) works on images\(action == .text || action == .shrink ? " and PDFs" : "")")))
            return
        }
        running += 1
        queue.async { [weak self] in
            guard let self = self else { return }
            let result: Result<String, Error>
            do {
                result = .success(try self.perform(action, on: url))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { self.finish(action, url, result) }
        }
    }

    // MARK: Main queue

    private func finish(_ action: AlchemyAction, _ url: URL, _ result: Result<String, Error>) {
        if running > 0 { running -= 1 }
        switch result {
        case .success(let output):
            if action == .text {
                ClipboardService.shared.copyText(output)
                let count = output.count
                last = "text \(count) chars from \(url.lastPathComponent)"
                ScreenRecorder.notify(title: count == 0 ? "No text found" : "Text copied",
                                      body: count == 0 ? url.lastPathComponent : "\(count) characters from \(url.lastPathComponent)",
                                      symbol: "text.viewfinder", category: .downloads)
            } else {
                let out = URL(fileURLWithPath: output)
                ShelfService.shared.add(urls: [out])
                last = "\(action.rawValue) → \(out.lastPathComponent)"
                ScreenRecorder.notify(title: action.detail, body: out.lastPathComponent, symbol: action.symbol,
                                      category: .downloads)
            }
        case .failure(let error):
            let message = (error as? Failure)?.message ?? error.localizedDescription
            last = "failed \(action.rawValue): \(message)"
            logger.error("alchemy \(action.rawValue, privacy: .public) failed: \(message, privacy: .public)")
            ScreenRecorder.notify(title: "\(action.title) didn't work", body: message, symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Work (utility queue)

    /// Returns the output path, or the text for `.text`.
    private func perform(_ action: AlchemyAction, on url: URL) throws -> String {
        let isPDF = url.pathExtension.lowercased() == "pdf"
        if action == .text { return isPDF ? try pdfText(url) : try recognizeText(url) }
        let folder = url.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let transparent = action == .shrink && !isPDF && hasTransparency(url)
        guard let name = action.outputName(for: url.lastPathComponent, existing: existing,
                                           keepsTransparency: transparent) else {
            throw Failure(message: "No output name")
        }
        let out = folder.appendingPathComponent(name)
        switch action {
        case .cutout: try cutout(url, to: out)
        case .shrink: try isPDF ? shrinkPDF(url, to: out) : shrinkImage(url, to: out)
        case .png: try convert(url, to: out, type: .png)
        case .jpeg: try convert(url, to: out, type: .jpeg)
        case .text: break
        }
        return out.path
    }

    private func cgImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure(message: "Couldn't read the image")
        }
        return image
    }

    private func hasTransparency(_ url: URL) -> Bool {
        guard let image = try? cgImage(url) else { return false }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Couldn't write \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure(message: "Couldn't write \(url.lastPathComponent)") }
    }

    private func cutout(_ url: URL, to out: URL) throws {
        let image = try cgImage(url)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw Failure(message: "No subject found in the picture")
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                         croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let masked = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure(message: "Cutout failed") }
        try write(masked, to: out, type: .png)
    }

    private func recognizeText(_ url: URL) throws -> String {
        let image = try cgImage(url)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func pdfText(_ url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else { throw Failure(message: "Couldn't open the PDF") }
        return (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shrinkImage(_ url: URL, to out: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Couldn't read the image") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 2048]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure(message: "Couldn't resize the image")
        }
        let type: UTType = out.pathExtension.lowercased() == "png" ? .png : .jpeg
        try write(small, to: out, type: type, quality: 0.75)
    }

    private func shrinkPDF(_ url: URL, to out: URL) throws {
        guard let doc = PDFDocument(url: url) else { throw Failure(message: "Couldn't open the PDF") }
        let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        guard doc.write(to: out, withOptions: options) else { throw Failure(message: "Couldn't save the smaller PDF") }
    }

    private func convert(_ url: URL, to out: URL, type: UTType) throws {
        try write(try cgImage(url), to: out, type: type)
    }
}
