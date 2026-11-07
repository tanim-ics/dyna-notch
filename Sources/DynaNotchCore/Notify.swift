import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct NotchNotification: Equatable {
    public var title: String
    public var body: String
    public var symbol: String
    public var duration: TimeInterval?
    /// What a click on the popup opens (`open=`, http / https only).
    public var openURL: URL?

    public init(title: String, body: String, symbol: String = "bell.fill", duration: TimeInterval? = nil,
                openURL: URL? = nil) {
        self.title = title
        self.body = body
        self.symbol = symbol
        self.duration = duration
        self.openURL = openURL
    }
}

public enum NotifyURL {
    /// dynanotch://notify?title=&body=&symbol=&duration=&open= (title or body required; duration clamped 1...30;
    /// open = http / https URL a click on the popup opens).
    public static func parse(_ url: URL) -> NotchNotification? {
        guard url.scheme?.lowercased() == "dynanotch", url.host?.lowercased() == "notify",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name.lowercased()] = item.value ?? ""
        }
        let title = (values["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (values["body"] ?? values["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else { return nil }
        var symbol = (values["symbol"] ?? "").trimmingCharacters(in: .whitespaces)
        if symbol.isEmpty { symbol = "bell.fill" }
        let duration = values["duration"].flatMap(Double.init).map { min(30, max(1, $0)) }
        return NotchNotification(title: title.isEmpty ? body : title, body: title.isEmpty ? "" : body,
                                 symbol: symbol, duration: duration, openURL: PopupTarget.openURL(values["open"]))
    }
}
