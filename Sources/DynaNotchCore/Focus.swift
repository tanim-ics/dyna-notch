import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct FocusState: Equatable {
    public var modeIdentifier: String?
    public var name: String
    public var symbol: String
    public var isActive: Bool { modeIdentifier != nil }

    public init(modeIdentifier: String?, name: String, symbol: String) {
        self.modeIdentifier = modeIdentifier
        self.name = name
        self.symbol = symbol
    }

    public static let inactive = FocusState(modeIdentifier: nil, name: "Focus", symbol: "moon.fill")
}

/// Parses the macOS Do Not Disturb database files (`~/Library/DoNotDisturb/DB/*.json`).
public enum FocusParser {
    private static let known: [(key: String, name: String, symbol: String)] = [
        ("default", "Do Not Disturb", "moon.fill"),
        ("sleep", "Sleep", "bed.double.fill"),
        ("driving", "Driving", "car.fill"),
        ("work", "Work", "briefcase.fill"),
        ("personal", "Personal", "person.fill"),
        ("reading", "Reading", "book.fill"),
        ("fitness", "Fitness", "figure.run"),
        ("gaming", "Gaming", "gamecontroller.fill"),
        ("mindfulness", "Mindfulness", "brain.head.profile"),
    ]

    /// Assertions.json → data[0].storeAssertionRecords[0].assertionDetails.assertionDetailsModeIdentifier
    /// (nil when no records).
    public static func activeModeIdentifier(assertionsJSON: Data) -> String? {
        guard let first = firstDataEntry(assertionsJSON),
              let records = first["storeAssertionRecords"] as? [Any],
              let record = records.first as? [String: Any],
              let details = record["assertionDetails"] as? [String: Any],
              let identifier = details["assertionDetailsModeIdentifier"] as? String,
              !identifier.isEmpty else {
            return nil
        }
        return identifier
    }

    /// ModeConfigurations.json → data[0].modeConfigurations[id].mode.{name,symbolImageName}; falls back to known ids.
    public static func state(assertionsJSON: Data, configurationsJSON: Data?) -> FocusState {
        guard let identifier = activeModeIdentifier(assertionsJSON: assertionsJSON) else { return .inactive }
        let fallback = fallbackInfo(for: identifier)
        var name = fallback.name
        var symbol = fallback.symbol
        if let configData = configurationsJSON,
           let first = firstDataEntry(configData),
           let configurations = first["modeConfigurations"] as? [String: Any],
           let configuration = configurations[identifier] as? [String: Any],
           let mode = configuration["mode"] as? [String: Any] {
            if let n = mode["name"] as? String, !n.isEmpty { name = n }
            if let s = mode["symbolImageName"] as? String, !s.isEmpty { symbol = s }
        }
        return FocusState(modeIdentifier: identifier, name: name, symbol: symbol)
    }

    static func fallbackInfo(for identifier: String) -> (name: String, symbol: String) {
        let lower = identifier.lowercased()
        for entry in known where lower.contains(entry.key) {
            return (entry.name, entry.symbol)
        }
        return ("Focus", "moon.fill")
    }

    private static func firstDataEntry(_ json: Data) -> [String: Any]? {
        guard !json.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: json, options: []),
              let root = object as? [String: Any],
              let data = root["data"] as? [Any],
              let first = data.first as? [String: Any] else {
            return nil
        }
        return first
    }
}
