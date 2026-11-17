import Foundation

/// Загрузка среднего курса Народного банка Сербии.
/// Источник — открытое API kurs.resenje.org, которое отдаёт официальную курсовую листу НБС.
/// Если курс не загрузился, его можно ввести вручную в любой операции.
public enum ExchangeRateService {
    public enum RateError: LocalizedError {
        case badResponse
        case noRate
        public var errorDescription: String? {
            switch self {
            case .badResponse: return "Сервис курсов не ответил. Введи курс вручную с сайта nbs.rs."
            case .noRate: return "В ответе нет среднего курса."
            }
        }
    }

    public static func url(for currency: Currency, date: Date) -> URL {
        URL(string: "https://kurs.resenje.org/api/v1/currencies/\(currency.rawValue.lowercased())/rates/\(Dates.iso(date))")!
    }

    /// Средний курс НБС (RSD за 1 единицу валюты) на дату.
    public static func middleRate(_ currency: Currency, on date: Date) async throws -> Decimal {
        if currency == .RSD { return 1 }
        var request = URLRequest(url: url(for: currency, date: date))
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RateError.badResponse }
        return try parseMiddleRate(data)
    }

    public static func parseMiddleRate(_ data: Data) throws -> Decimal {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RateError.badResponse }
        for key in ["exchange_middle", "middle", "middle_rate", "exchangeMiddle"] {
            if let n = json[key] as? NSNumber {
                return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX"))?.roundedTo(4) ?? n.decimalValue
            }
            if let s = json[key] as? String, let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) {
                return d.roundedTo(4)
            }
        }
        throw RateError.noRate
    }
}
