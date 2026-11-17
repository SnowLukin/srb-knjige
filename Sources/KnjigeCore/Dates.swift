import Foundation

/// Все даты считаем в часовом поясе Белграда, чтобы курс НБС брался на правильный день.
public enum Dates {
    public static let timeZone = TimeZone(identifier: "Europe/Belgrade") ?? .current

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        return c
    }()

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = timeZone
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    /// "2026-11-17"
    public static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    public static func fromISO(_ string: String) -> Date? {
        guard let d = isoFormatter.date(from: string) else { return nil }
        return noon(d)
    }

    /// "17.11.2026"
    public static func display(_ date: Date?) -> String {
        guard let date else { return "—" }
        return displayFormatter.string(from: date)
    }

    public static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps) ?? Date()
    }

    /// Полдень того же дня — так дата не «съезжает» при смене часовых поясов.
    public static func noon(_ date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return make(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    public static func year(_ date: Date) -> Int { calendar.component(.year, from: date) }
    public static func month(_ date: Date) -> Int { calendar.component(.month, from: date) }

    public static func isSameMonth(_ date: Date, year: Int, month: Int) -> Bool {
        Self.year(date) == year && Self.month(date) == month
    }

    public static func lastDay(ofMonth month: Int, year: Int) -> Date {
        let first = make(year, month, 1)
        let range = calendar.range(of: .day, in: .month, for: first) ?? 1..<29
        return make(year, month, range.upperBound - 1)
    }

    /// Если срок выпадает на выходной — переносим на понедельник (праздники не учитываются).
    public static func nextWorkingDay(_ date: Date) -> Date {
        var d = date
        while calendar.isDateInWeekend(d) {
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    public static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func adding(months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    public static let monthNames = ["январь", "февраль", "март", "апрель", "май", "июнь",
                                    "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]

    public static func monthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "\(month)" }
        return monthNames[month - 1]
    }
}

/// Форматирование денег.
public enum Money {
    private static func formatter(fraction: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ru_RU")
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        return f
    }

    private static let f2 = formatter(fraction: 2)
    private static let f0 = formatter(fraction: 0)

    public static func string(_ value: Decimal, _ currency: Currency, fraction: Int = 2) -> String {
        let f = fraction == 0 ? f0 : f2
        let number = f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        switch currency {
        case .RSD: return "\(number) RSD"
        case .EUR: return "\(number) €"
        case .USD: return "$\(number)"
        }
    }

    public static func rsd(_ value: Decimal, fraction: Int = 0) -> String {
        string(value, .RSD, fraction: fraction)
    }

    /// Разбор суммы, введённой пользователем: «5 100,50», «5100.50», «5.100,50».
    public static func parse(_ text: String) -> Decimal? {
        OCRParser.normalizeAmount(text)
    }

    /// Разбор курса: «117,1734» или «117.1734» — один разделитель всегда десятичный.
    public static func parseRate(_ text: String) -> Decimal? {
        let s = text.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        guard s.filter({ $0 == "." }).count <= 1, s.contains(where: \.isNumber) else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Число без валюты для полей ввода: «5100,5».
    public static func plain(_ value: Decimal, maxFraction: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ru_RU")
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxFraction
        f.decimalSeparator = ","
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
