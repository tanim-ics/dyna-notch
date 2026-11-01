import Combine
import Foundation
import os
import DynaNotchCore

/// Smart Copy conversions (CONTRACTS §6.13): copied text → `SmartConvert` → the island. Currency rates come from
/// Frankfurter (ECB, keyless), fetched only when an amount is copied and the cached rates are older than 12 h.
final class SmartCopyService {
    static let shared = SmartCopyService()

    /// The result label after the conversion was copied.
    static let copiedLabel = "Copied"
    private static let ratesKey = "dn.data.fxRates"
    private static let ratesMaxAge: TimeInterval = 12 * 3600
    private static let ratesURL = URL(string: "https://api.frankfurter.dev/v1/latest")

    /// Main queue.
    let conversions = PassthroughSubject<SmartConversion, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "smartcopy")
    private var started = false
    private var subscription: AnyCancellable?
    private var rates: CurrencyRates?
    private var ratesFetchedAt: Date?
    private var fetching = false
    private var pending: String?
    private var last = ""

    private struct Stored: Codable {
        var rates: CurrencyRates
        var fetchedAt: Date
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        if let data = UserDefaults.standard.data(forKey: SmartCopyService.ratesKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            rates = stored.rates
            ratesFetchedAt = stored.fetchedAt
        }
        subscription = ClipboardService.shared.copiedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.handle(text) }
    }

    /// state.json `smartCopy`.
    var state: [String: Any] {
        ["last": last, "ratesDate": rates?.date ?? ""]
    }

    /// Converts copied text (also the `dynanotch://convert` hook).
    func handle(_ text: String) {
        let settings = AppSettings.shared
        guard settings.smartCopy, settings.clipboardEnabled, text.count <= SmartConvert.maxLength * 2 else { return }
        if SmartConvert.looksLikeCurrency(text), ratesAreStale {
            pending = text
            fetchRates()
            if rates == nil { return }    // shown once the rates arrive
        }
        convertAndPost(text)
    }

    func copyResult(_ result: String) {
        ClipboardService.shared.copyText(result)
    }

    // MARK: Private

    private var ratesAreStale: Bool {
        guard rates != nil, let at = ratesFetchedAt else { return true }
        return Date().timeIntervalSince(at) > SmartCopyService.ratesMaxAge
    }

    private func convertAndPost(_ text: String) {
        let context = ConvertContext(homeCurrency: AppSettings.shared.homeCurrency, rates: rates)
        guard let conversion = SmartConvert.convert(text, context: context) else { return }
        last = "\(conversion.source) → \(conversion.result)"
        conversions.send(conversion)
    }

    private func fetchRates() {
        guard !fetching, let url = SmartCopyService.ratesURL else { return }
        fetching = true
        let logger = self.logger
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let parsed = ok ? data.flatMap(CurrencyRates.parse) : nil
            if parsed == nil { logger.debug("rates fetch failed: \(error?.localizedDescription ?? "bad response", privacy: .public)") }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.fetching = false
                if let fresh = parsed {
                    let hadRates = self.rates != nil
                    self.rates = fresh
                    self.ratesFetchedAt = Date()
                    if let data = try? JSONEncoder().encode(Stored(rates: fresh, fetchedAt: Date())) {
                        UserDefaults.standard.set(data, forKey: SmartCopyService.ratesKey)
                    }
                    // Only shown now if it waited for the first rates (otherwise it was shown with the cached ones).
                    if !hadRates, let text = self.pending { self.convertAndPost(text) }
                }
                self.pending = nil
            }
        }.resume()
    }
}
