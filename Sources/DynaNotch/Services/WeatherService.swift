import Combine
import CoreLocation
import Foundation
import os
import DynaNotchCore

/// Current weather from Open-Meteo for the configured city (or the Mac's location).
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: String = ""

    private struct Place {
        var latitude: Double
        var longitude: Double
        var name: String
    }

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "weather")
    private let session: URLSession
    private var started = false
    private var timer: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var geocodeCache: [String: Place] = [:]   // lowercased city → place (main queue)
    private var locator: OneShotLocator?
    private var generation = 0                         // bumps on every refresh; stale callbacks are dropped

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config)
    }

    // MARK: Public API

    func start() {
        guard !started else { return }
        started = true

        timer = Timer.publish(every: 30 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }

        let settings = AppSettings.shared
        settingsObserver = Publishers.CombineLatest(settings.$weatherCity.removeDuplicates(),
                                                    settings.$temperatureUnit.removeDuplicates())
            .dropFirst()
            .debounce(for: .milliseconds(800), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }

        refresh()
    }

    func refresh() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.generation += 1
            let gen = self.generation
            let city = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if city.isEmpty {
                self.resolveCurrentLocation(generation: gen)
            } else {
                self.resolveCity(city, generation: gen)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: Location resolution (main queue)

    private func resolveCity(_ city: String, generation gen: Int) {
        let key = city.lowercased()
        if let place = geocodeCache[key] {
            fetchForecast(place, generation: gen)
            return
        }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
        ]
        guard let url = components?.url else { return }
        setStatus("Updating…", generation: gen)
        get(url) { [weak self] data in
            guard let self = self, gen == self.generation else { return }
            guard let data = data else {
                self.setStatus("Offline", generation: gen)
                return
            }
            guard let result = OpenMeteoParser.parseGeocoding(data) else {
                self.setStatus("City not found", generation: gen)
                return
            }
            let place = Place(latitude: result.latitude, longitude: result.longitude, name: result.name)
            self.geocodeCache[key] = place
            self.fetchForecast(place, generation: gen)
        }
    }

    private func resolveCurrentLocation(generation gen: Int) {
        setStatus("Locating…", generation: gen)
        let locator = OneShotLocator { [weak self] location in
            guard let self = self, gen == self.generation else { return }
            self.locator = nil
            guard let location = location else {
                self.setStatus("Set a city in Settings", generation: gen)
                return
            }
            let coordinate = location.coordinate
            CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                DispatchQueue.main.async {
                    guard let self = self, gen == self.generation else { return }
                    let name = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Current Location"
                    self.fetchForecast(Place(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name),
                                       generation: gen)
                }
            }
        }
        self.locator = locator
        locator.start()
    }

    // MARK: Forecast

    private func fetchForecast(_ place: Place, generation gen: Int) {
        let unit = AppSettings.shared.temperatureUnit
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
        ]
        guard let url = components?.url else { return }
        setStatus("Updating…", generation: gen)
        get(url) { [weak self] data in
            guard let self = self, gen == self.generation else { return }
            let now = Date()
            guard let data = data else {
                self.setStatus("Offline", generation: gen)
                return
            }
            guard let snapshot = OpenMeteoParser.parse(data, locationName: place.name, now: now) else {
                self.setStatus("Weather unavailable", generation: gen)
                return
            }
            self.snapshot = snapshot
            self.setStatus("Updated " + WeatherService.timeFormatter.string(from: now), generation: gen)
        }
    }

    // MARK: Helpers

    private func setStatus(_ text: String, generation gen: Int) {
        guard gen == generation, status != text else { return }
        status = text
    }

    /// GET with a completion on the main queue; nil on transport error or non-2xx.
    private func get(_ url: URL, completion: @escaping (Data?) -> Void) {
        let logger = self.logger
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                logger.debug("weather request failed: \(error.localizedDescription, privacy: .public)")
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(code)
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }
}

/// One-shot CoreLocation fix. Completion is called exactly once, on the main queue.
private final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    private var requested = false

    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        handle(manager.authorizationStatus)
        // Safety net: never leave the UI "Locating…" forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.finish(nil)
        }
    }

    private func handle(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        default:
            if !requested {
                requested = true
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.handle(manager.authorizationStatus) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        DispatchQueue.main.async { self.finish(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        guard let completion = completion else { return }
        self.completion = nil
        manager.delegate = nil
        completion(location)
    }
}
