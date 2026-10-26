import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct EmojiEntry: Equatable, Identifiable, Hashable {
    public var id: String { character }
    public var character: String
    /// Lower-case Unicode name, e.g. "grinning face".
    public var name: String
    public var group: EmojiGroup

    public init(character: String, name: String, group: EmojiGroup) {
        self.character = character
        self.name = name
        self.group = group
    }
}

public enum EmojiGroup: String, Equatable, Hashable, CaseIterable {
    case smileys, people, nature, food, activities, travel, objects, symbols

    public var title: String {
        switch self {
        case .smileys: return "Smileys"
        case .people: return "People"
        case .nature: return "Nature"
        case .food: return "Food"
        case .activities: return "Activities"
        case .travel: return "Travel"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        }
    }

    public var symbol: String {
        switch self {
        case .smileys: return "face.smiling"
        case .people: return "hand.wave"
        case .nature: return "leaf"
        case .food: return "fork.knife"
        case .activities: return "soccerball"
        case .travel: return "car"
        case .objects: return "lightbulb"
        case .symbols: return "heart"
        }
    }
}

/// Emoji list built from the Unicode properties of the standard library (no data file needed).
public enum EmojiCatalog {
    static let ranges: [(ClosedRange<UInt32>, EmojiGroup)] = [
        (0x1F600...0x1F64F, .smileys), (0x1F910...0x1F92F, .smileys), (0x1F970...0x1F97A, .smileys),
        (0x1F44A...0x1F4AA, .people), (0x1F918...0x1F91F, .people), (0x1F930...0x1F93E, .people),
        (0x1F9D0...0x1F9DF, .people), (0x1F466...0x1F487, .people),
        (0x1F400...0x1F43F, .nature), (0x1F330...0x1F343, .nature), (0x1F980...0x1F9AE, .nature),
        (0x1F345...0x1F37F, .food), (0x1F950...0x1F96F, .food), (0x1F9C0...0x1F9CB, .food),
        (0x1F380...0x1F3CA, .activities), (0x1F3CF...0x1F3F0, .activities), (0x26BD...0x26BE, .activities),
        (0x1F680...0x1F6C5, .travel), (0x1F3D4...0x1F3DF, .travel), (0x1F30D...0x1F320, .travel),
        (0x1F4AB...0x1F4FC, .objects), (0x1F500...0x1F53D, .objects), (0x1F9F0...0x1F9FF, .objects),
        (0x2600...0x27BF, .symbols), (0x1F493...0x1F49F, .symbols), (0x2764...0x2764, .symbols),
    ]

    public static let all: [EmojiEntry] = {
        var seen = Set<String>()
        var result: [EmojiEntry] = []
        for (range, group) in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                      let name = scalar.properties.name else { continue }
                let character = String(Character(scalar))
                guard !seen.contains(character) else { continue }
                seen.insert(character)
                result.append(EmojiEntry(character: character, name: name.lowercased(), group: group))
            }
        }
        return result
    }()

    /// All words of the query must appear in the name (prefix of a word), e.g. "thumb up", "cat".
    public static func search(_ query: String, in entries: [EmojiEntry] = all) -> [EmojiEntry] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let nameWords = entry.name.split(whereSeparator: { $0 == " " || $0 == "-" })
            return words.allSatisfy { w in nameWords.contains(where: { $0.hasPrefix(w) }) }
        }
    }
}
