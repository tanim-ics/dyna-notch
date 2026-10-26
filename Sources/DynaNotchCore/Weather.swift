import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum TemperatureUnit: String, Equatable, Hashable, CaseIterable {
    case celsius, fahrenheit

    public var title: String {
        switch self {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    public var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    /// Open-Meteo `temperature_unit` value.
    public var apiValue: String { rawValue }
}

public struct WeatherSnapshot: Equatable {
    public var temperature: Double
    public var high: Double
    public var low: Double
    public var code: Int
    public var isDay: Bool
    public var locationName: String
    public var fetchedAt: Date

    public init(temperature: Double, high: Double, low: Double, code: Int, isDay: Bool, locationName: String, fetchedAt: Date) {
        self.temperature = temperature
        self.high = high
        self.low = low
        self.code = code
        self.isDay = isDay
        self.locationName = locationName
        self.fetchedAt = fetchedAt
    }

    public var symbolName: String { WeatherCode.symbol(code: code, isDay: isDay) }
    public var summary: String { WeatherCode.summary(code: code) }
}

/// WMO weather interpretation codes (Open-Meteo).
public enum WeatherCode {
    public static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    public static func summary(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, Hail"
        default: return "Cloudy"
        }
    }
}

public enum OpenMeteoParser {
    public static func parse(_ data: Data, locationName: String, now: Date) -> WeatherSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let current = dict["current"] as? [String: Any],
              let temperature = JSONValue.double(current["temperature_2m"]) else { return nil }
        let code = JSONValue.int(current["weather_code"])
        let isDay = current["is_day"].map { JSONValue.int($0) != 0 } ?? true
        let daily = dict["daily"] as? [String: Any]
        let high = (daily?["temperature_2m_max"] as? [Any])?.first.flatMap { JSONValue.double($0) } ?? temperature
        let low = (daily?["temperature_2m_min"] as? [Any])?.first.flatMap { JSONValue.double($0) } ?? temperature
        return WeatherSnapshot(temperature: temperature, high: high, low: low, code: code, isDay: isDay,
                               locationName: locationName, fetchedAt: now)
    }

    public static func parseGeocoding(_ data: Data) -> (latitude: Double, longitude: Double, name: String)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let results = dict["results"] as? [[String: Any]],
              let first = results.first,
              let lat = JSONValue.double(first["latitude"]),
              let lon = JSONValue.double(first["longitude"]) else { return nil }
        return (lat, lon, first["name"] as? String ?? "")
    }
}
