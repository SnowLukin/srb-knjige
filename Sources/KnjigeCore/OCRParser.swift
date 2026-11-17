import Foundation

public enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case deelPayment, bankStatement, bill, unknown
    public var title: String {
        switch self {
        case .deelPayment: return "Выплата Deel"
        case .bankStatement: return "Банковская выписка"
        case .bill: return "Счёт / чек (расход)"
        case .unknown: return "Не определено"
        }
    }
}

public struct ParsedAmount: Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var value: Decimal
    public var currency: Currency?
    public var line: String
}

public struct ParsedDocument: Equatable, Sendable {
    public var text: String
    public var kind: DocumentKind
    public var amounts: [ParsedAmount]
    public var dates: [Date]
    public var ibans: [String]

    /// Самая вероятная сумма: сначала с указанной валютой, затем самая большая.
    public var bestAmount: ParsedAmount? {
        let withCurrency = amounts.filter { $0.currency != nil }
        let pool = withCurrency.isEmpty ? amounts : withCurrency
        return pool.max { $0.value < $1.value }
    }

    public var bestDate: Date? { dates.first }
}

/// Разбирает текст, распознанный со скриншота или PDF (выплата Deel, выписка банка, чек).
public enum OCRParser {

    public static func parse(_ text: String) -> ParsedDocument {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var amounts: [ParsedAmount] = []
        var dates: [Date] = []
        var ibans: [String] = []

        for line in lines {
            let foundIbans = matches(ibanPattern, in: line)
            ibans.append(contentsOf: foundIbans.map { $0.replacingOccurrences(of: " ", with: "") })

            let (lineDates, cleaned) = extractDates(line)
            dates.append(contentsOf: lineDates)

            var withoutIban = cleaned
            for iban in foundIbans { withoutIban = withoutIban.replacingOccurrences(of: iban, with: " ") }
            let currency = detectCurrency(withoutIban)
            for token in matches(amountPattern, in: withoutIban) {
                guard let value = normalizeAmount(token), value != 0 else { continue }
                let digits = token.filter(\.isNumber).count
                // Отсекаем номера счетов, телефоны и прочие длинные числа без дробной части.
                let hasFraction = token.range(of: #"[.,]\d{1,2}$"#, options: .regularExpression) != nil
                if digits > 12 { continue }
                if !hasFraction && currency == nil && digits < 3 { continue }
                if !hasFraction && currency == nil && digits > 7 { continue }
                amounts.append(ParsedAmount(value: abs(value), currency: currency, line: line))
            }
        }

        return ParsedDocument(
            text: text,
            kind: detectKind(text),
            amounts: amounts,
            dates: unique(dates),
            ibans: Array(Set(ibans)).sorted())
    }

    // MARK: Тип документа

    public static func detectKind(_ text: String) -> DocumentKind {
        let t = text.lowercased()
        if t.contains("deel") { return .deelPayment }
        if t.contains("izvod") || t.contains("извод") || t.contains("statement") || t.contains("stanje računa") || t.contains("prethodno stanje") {
            return .bankStatement
        }
        if t.contains("faktura") || t.contains("račun") || t.contains("racun") || t.contains("invoice")
            || t.contains("receipt") || t.contains("fiskalni") || t.contains("рачун") || t.contains("фактура") {
            return .bill
        }
        return .unknown
    }

    public static func detectCurrency(_ line: String) -> Currency? {
        let l = line.lowercased()
        if l.contains("€") || l.range(of: #"\beur\b"#, options: .regularExpression) != nil || l.contains("evra") || l.contains("евро") {
            return .EUR
        }
        if l.range(of: #"\brsd\b"#, options: .regularExpression) != nil || l.range(of: #"\bdin\b\.?"#, options: .regularExpression) != nil
            || l.contains("dinara") || l.contains("динар") || l.contains("дин") {
            return .RSD
        }
        if l.contains("$") || l.range(of: #"\busd\b"#, options: .regularExpression) != nil {
            return .USD
        }
        return nil
    }

    // MARK: Суммы

    static let amountPattern = #"[-−]?\d{1,3}(?:[ \x{00A0}\x{202F}.,'’]\d{3})+(?:[.,]\d{1,2})?|[-−]?\d+[.,]\d{1,2}|\d{3,}"#

    /// «5 100,50» / «5,100.50» / «5.100,50» / «5100.50» → 5100.50
    public static func normalizeAmount(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = s.hasPrefix("-") || s.hasPrefix("−")
        s = String(s.filter { $0.isNumber || $0 == "." || $0 == "," })
        guard !s.isEmpty, s.contains(where: \.isNumber) else { return nil }

        let hasDot = s.contains("."), hasComma = s.contains(",")
        if hasDot && hasComma {
            let lastDot = s.lastIndex(of: ".")!, lastComma = s.lastIndex(of: ",")!
            if lastDot > lastComma {
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        } else if hasComma {
            if s.range(of: #"^\d+,\d{1,2}$"#, options: .regularExpression) != nil {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasDot {
            let dots = s.filter { $0 == "." }.count
            if !(dots == 1 && s.range(of: #"^\d+\.\d{1,2}$"#, options: .regularExpression) != nil) {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        }
        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    // MARK: Даты

    private static let monthsEN: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    /// Находит даты в строке и возвращает строку без них (чтобы даты не путались с суммами).
    static func extractDates(_ line: String) -> ([Date], String) {
        var found: [Date] = []
        var cleaned = line

        let patterns: [(String, (NSTextCheckingResult, NSString) -> Date?)] = [
            (#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#, { m, s in
                OCRParser.makeDate(y: s.substring(with: m.range(at: 1)), m: s.substring(with: m.range(at: 2)), d: s.substring(with: m.range(at: 3)))
            }),
            (#"\b(\d{1,2})[./](\d{1,2})[./](\d{4})\.?"#, { m, s in
                OCRParser.makeDate(y: s.substring(with: m.range(at: 3)), m: s.substring(with: m.range(at: 2)), d: s.substring(with: m.range(at: 1)))
            }),
            (#"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})"#, { m, s in
                let mon = OCRParser.monthsEN[s.substring(with: m.range(at: 1)).lowercased()] ?? 0
                return OCRParser.makeDate(y: s.substring(with: m.range(at: 3)), m: "\(mon)", d: s.substring(with: m.range(at: 2)))
            }),
            (#"\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?,?\s+(\d{4})"#, { m, s in
                let mon = OCRParser.monthsEN[s.substring(with: m.range(at: 2)).lowercased()] ?? 0
                return OCRParser.makeDate(y: s.substring(with: m.range(at: 3)), m: "\(mon)", d: s.substring(with: m.range(at: 1)))
            })
        ]

        for (pattern, builder) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = cleaned as NSString
            let results = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            for m in results {
                if let d = builder(m, ns) { found.append(d) }
            }
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        return (found, cleaned)
    }

    private static func makeDate(y: String, m: String, d: String) -> Date? {
        guard let yi = Int(y), let mi = Int(m), let di = Int(d),
              (2000...2100).contains(yi), (1...12).contains(mi), (1...31).contains(di) else { return nil }
        return Dates.make(yi, mi, di)
    }

    // MARK: IBAN

    static let ibanPattern = #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b"#

    // MARK: Утилиты

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func unique(_ dates: [Date]) -> [Date] {
        var seen = Set<String>()
        return dates.filter { seen.insert(Dates.iso($0)).inserted }
    }
}
