import Foundation

/// Drop Alchemy (CONTRACTS §6.15): what a file dropped on a zone turns into.
public enum AlchemyAction: String, Equatable, CaseIterable {
    case cutout, text, shrink, png, jpeg

    public var title: String {
        switch self {
        case .cutout: return "Cutout"
        case .text: return "Text"
        case .shrink: return "Shrink"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    public var detail: String {
        switch self {
        case .cutout: return "Remove the background"
        case .text: return "Copy the text in it"
        case .shrink: return "Make it smaller"
        case .png: return "Convert to PNG"
        case .jpeg: return "Convert to JPEG"
        }
    }

    public var symbol: String {
        switch self {
        case .cutout: return "person.crop.rectangle.badge.plus"
        case .text: return "text.viewfinder"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .png, .jpeg: return "photo.on.rectangle.angled"
        }
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    public func accepts(fileExtension ext: String) -> Bool {
        let e = ext.lowercased()
        if AlchemyAction.imageExtensions.contains(e) { return true }
        return e == "pdf" && (self == .text || self == .shrink)
    }

    /// Output file name next to the input; nil for `.text` (it goes to the clipboard). Shrink makes a JPEG unless the
    /// picture has transparency (`keepsTransparency`), which stays PNG; PDFs stay PDFs.
    public func outputName(for input: String, existing: Set<String>, keepsTransparency: Bool = false) -> String? {
        let base = (input as NSString).deletingPathExtension
        let ext = (input as NSString).pathExtension.lowercased()
        let name: String
        let outExt: String
        switch self {
        case .text: return nil
        case .cutout: name = "\(base) (cutout)"; outExt = "png"
        case .shrink: name = "\(base) (small)"; outExt = ext == "pdf" ? "pdf" : (keepsTransparency ? "png" : "jpg")
        case .png: name = base; outExt = "png"
        case .jpeg: name = base; outExt = "jpg"
        }
        var candidate = "\(name).\(outExt)"
        var n = 2
        while existing.contains(candidate) || candidate == input {
            candidate = "\(name) \(n).\(outExt)"
            n += 1
        }
        return candidate
    }
}
