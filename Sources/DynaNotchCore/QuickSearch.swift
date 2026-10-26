import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct SearchEngine: Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    /// Typed before the query to pick this engine ("gh swiftui").
    public var shortcut: String
    /// URL with "%@" where the encoded query goes.
    public var template: String
    public var symbol: String

    public init(id: String, name: String, shortcut: String, template: String, symbol: String = "magnifyingglass") {
        self.id = id
        self.name = name
        self.shortcut = shortcut
        self.template = template
        self.symbol = symbol
    }

    public func url(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%@", with: encoded))
    }
}

public enum QuickSearch {
    public static let builtIn: [SearchEngine] = [
        SearchEngine(id: "google", name: "Google", shortcut: "g", template: "https://www.google.com/search?q=%@", symbol: "magnifyingglass"),
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", shortcut: "ddg", template: "https://duckduckgo.com/?q=%@", symbol: "shield.lefthalf.filled"),
        SearchEngine(id: "bing", name: "Bing", shortcut: "b", template: "https://www.bing.com/search?q=%@", symbol: "b.circle"),
        SearchEngine(id: "perplexity", name: "Perplexity", shortcut: "p", template: "https://www.perplexity.ai/search?q=%@", symbol: "sparkle.magnifyingglass"),
        SearchEngine(id: "youtube", name: "YouTube", shortcut: "yt", template: "https://www.youtube.com/results?search_query=%@", symbol: "play.rectangle.fill"),
        SearchEngine(id: "github", name: "GitHub", shortcut: "gh", template: "https://github.com/search?q=%@", symbol: "chevron.left.forwardslash.chevron.right"),
        SearchEngine(id: "wikipedia", name: "Wikipedia", shortcut: "w", template: "https://en.wikipedia.org/wiki/Special:Search?search=%@", symbol: "book.closed.fill"),
        SearchEngine(id: "maps", name: "Maps", shortcut: "map", template: "https://maps.apple.com/?q=%@", symbol: "map.fill"),
        SearchEngine(id: "amazon", name: "Amazon", shortcut: "az", template: "https://www.amazon.com/s?k=%@", symbol: "cart.fill"),
        SearchEngine(id: "translate", name: "Translate", shortcut: "tr", template: "https://translate.google.com/?sl=auto&tl=en&text=%@", symbol: "character.bubble.fill"),
    ]

    public struct Resolution: Equatable {
        public var engine: SearchEngine?
        public var query: String
        public var url: URL
    }

    /// Resolves what the user typed: a URL or domain opens directly; "shortcut query" uses that engine;
    /// anything else goes to `defaultEngineID` (falls back to Google). Empty → nil.
    public static func resolve(_ input: String, engines: [SearchEngine] = builtIn, defaultEngineID: String) -> Resolution? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let direct = directURL(text) {
            return Resolution(engine: nil, query: text, url: direct)
        }
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let key = parts[0].lowercased()
            if let engine = engines.first(where: { $0.shortcut.lowercased() == key }),
               let url = engine.url(for: String(parts[1])) {
                return Resolution(engine: engine, query: String(parts[1]), url: url)
            }
        }
        let engine = engines.first(where: { $0.id == defaultEngineID }) ?? engines.first ?? builtIn[0]
        guard let url = engine.url(for: text) else { return nil }
        return Resolution(engine: engine, query: text, url: url)
    }

    /// "https://x.com", "apple.com", "localhost:3000/a" → URL; text with spaces → nil.
    static func directURL(_ text: String) -> URL? {
        guard !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: text)
        }
        let host = lower.split(separator: "/").first.map(String.init) ?? lower
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let labels = hostOnly.split(separator: ".")
        let isDomain = labels.count >= 2 && (labels.last?.count ?? 0) >= 2
            && labels.last?.allSatisfy({ $0.isLetter }) == true
            && hostOnly.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        if isDomain || hostOnly == "localhost" {
            return URL(string: "https://" + text)
        }
        return nil
    }
}
