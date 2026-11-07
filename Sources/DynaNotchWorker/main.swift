// DynaNotchWorker — decodes untrusted files (images, PDFs) for Drop Alchemy, away from the app (docs/SECURITY.md).
// The app runs it inside a macOS sandbox: no network, no writes except the output file, no permissions, pasteboard,
// Keychain or Apple Events. A file that exploits an image / PDF decoder lands here, with nothing to steal.
//
//   DynaNotchWorker alchemy <cutout|text|shrink|png|jpeg> <input> <outdir>
//   stdout: the text (text) or the path of the file written in <outdir>; failures: exit 1, message on stderr.
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

struct Failure: Error { let message: String }

func cgImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
        throw Failure(message: "Couldn't read the image")
    }
    return image
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw Failure(message: "Couldn't write \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw Failure(message: "Couldn't write \(url.lastPathComponent)") }
}

func cutout(_ url: URL, to out: URL) throws {
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

func recognizeText(_ url: URL) throws -> String {
    let image = try cgImage(url)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

func pdfText(_ url: URL) throws -> String {
    guard let doc = PDFDocument(url: url) else { throw Failure(message: "Couldn't open the PDF") }
    return (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func shrinkImage(_ url: URL, to out: URL) throws {
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

func shrinkPDF(_ url: URL, to out: URL) throws {
    guard let doc = PDFDocument(url: url) else { throw Failure(message: "Couldn't open the PDF") }
    let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
    guard doc.write(to: out, withOptions: options) else { throw Failure(message: "Couldn't save the smaller PDF") }
}

func hasTransparency(_ url: URL) -> Bool {
    guard let image = try? cgImage(url) else { return false }
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: return false
    default: return true
    }
}

let args = CommandLine.arguments
func finish(_ text: String, code: Int32) -> Never {
    let handle = code == 0 ? FileHandle.standardOutput : FileHandle.standardError
    handle.write(Data(text.utf8))
    exit(code)
}

// DynaNotchWorker alchemy <action> <input> <outdir> → prints the text (text) or the file it wrote in <outdir>
guard args.count == 5, args[1] == "alchemy" else {
    finish("usage: DynaNotchWorker alchemy <cutout|text|shrink|png|jpeg> <input> <outdir>", code: 2)
}
let input = URL(fileURLWithPath: args[3])
let outDir = URL(fileURLWithPath: args[4], isDirectory: true)
let isPDF = input.pathExtension.lowercased() == "pdf"
do {
    let out: URL
    switch args[2] {
    case "text":
        finish(isPDF ? try pdfText(input) : try recognizeText(input), code: 0)
    case "cutout":
        out = outDir.appendingPathComponent("result.png")
        try cutout(input, to: out)
    case "shrink":
        out = outDir.appendingPathComponent(isPDF ? "result.pdf" : (hasTransparency(input) ? "result.png" : "result.jpg"))
        try isPDF ? shrinkPDF(input, to: out) : shrinkImage(input, to: out)
    case "png":
        out = outDir.appendingPathComponent("result.png")
        try write(try cgImage(input), to: out, type: .png)
    case "jpeg":
        out = outDir.appendingPathComponent("result.jpg")
        try write(try cgImage(input), to: out, type: .jpeg)
    default:
        finish("unknown action", code: 2)
    }
    finish(out.path, code: 0)
} catch {
    finish((error as? Failure)?.message ?? error.localizedDescription, code: 1)
}
