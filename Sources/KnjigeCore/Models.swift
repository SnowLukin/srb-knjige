import Foundation

// MARK: - Базовые типы

public enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    case EUR, USD, RSD
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .EUR: return "€"
        case .USD: return "$"
        case .RSD: return "RSD"
        }
    }
}

/// Профиль предузетника — данные, которые печатаются в инвойсах и нужны для отчётов.
public struct BusinessProfile: Codable, Equatable, Sendable {
    public var ownerName: String = ""
    /// Название ИП так, как оно записано в APR (например «Ivan Petrov PR Računarsko programiranje Beograd»).
    public var businessName: String = ""
    public var pib: String = ""
    public var maticniBroj: String = ""
    public var address: String = ""
    public var city: String = "Beograd"
    public var activityCode: String = "6201"
    public var registrationDate: Date? = nil
    public var bankName: String = ""
    public var iban: String = ""
    public var swift: String = ""
    public var email: String = ""
    public var invoicePrefix: String = ""
    public var nextInvoiceNumber: Int = 1
    /// Дата окончания ВНЖ — чтобы напомнить о продлении.
    public var residencePermitExpiry: Date? = nil

    public init() {}
}

public struct Client: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String = ""
    public var address: String = ""
    public var country: String = ""
    public var registrationNumber: String = ""
    public var email: String = ""
    public var defaultCurrency: Currency = .EUR
    /// Иностранный клиент: его оборот не входит в порог НДС 8 млн RSD.
    public var isForeign: Bool = true

    public init() {}
}

/// Инвойс (faktura), выставленный клиенту.
public struct Invoice: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var number: String = ""
    public var issueDate: Date = Date()
    /// Дата оказания услуги (datum prometa). Выручка в динарах считается по курсу НБС на эту дату.
    public var serviceDate: Date = Date()
    public var dueDate: Date? = nil
    public var clientId: UUID? = nil
    public var description: String = "Software development services"
    public var amount: Decimal = 0
    public var currency: Currency = .EUR
    /// Средний курс НБС на дату оказания услуги (RSD за 1 единицу валюты). nil — взять из кэша курсов.
    public var rateAtService: Decimal? = nil
    public var notes: String = ""
    public var attachmentIds: [UUID] = []

    public init() {}
}

/// Поступление денег на бизнес-счёт (например, выплата от Deel).
public struct Receipt: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    /// Сумма, фактически зачисленная на счёт.
    public var amount: Decimal = 0
    public var currency: Currency = .EUR
    public var invoiceId: UUID? = nil
    /// Удержанная комиссия (Deel, банк-корреспондент) в валюте поступления.
    public var fee: Decimal = 0
    public var rateAtReceipt: Decimal? = nil
    public var source: String = "Deel"
    public var note: String = ""
    public var attachmentIds: [UUID] = []

    public init() {}
}

/// Продажа валюты банку (конвертация EUR → RSD).
public struct Conversion: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    public var foreignAmount: Decimal = 0
    public var currency: Currency = .EUR
    /// Сколько динаров зачислил банк.
    public var rsdReceived: Decimal = 0
    /// Средний курс НБС на дату конвертации.
    public var nbsRate: Decimal? = nil
    public var note: String = ""
    public var attachmentIds: [UUID] = []

    public init() {}
}

public enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case accountant, legalAddress, bankFees, software, equipment, rent, translation, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .accountant: return "Бухгалтер / консультации"
        case .legalAddress: return "Юрадрес"
        case .bankFees: return "Банк и комиссии"
        case .software: return "Софт и подписки"
        case .equipment: return "Техника"
        case .rent: return "Аренда помещения"
        case .translation: return "Переводы и нотариус"
        case .other: return "Прочее"
        }
    }
}

public struct Expense: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    public var description: String = ""
    public var category: ExpenseCategory = .other
    public var amount: Decimal = 0
    public var currency: Currency = .RSD
    public var rate: Decimal? = nil
    /// Признаётся ли налоговой как расход ИП. Личные траты сюда не вносить.
    public var deductible: Bool = true
    public var supplier: String = ""
    public var attachmentIds: [UUID] = []

    public init() {}
}

/// Личная зарплата предузетника за месяц.
public struct SalaryPayment: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var year: Int
    public var month: Int
    /// Бруто 1 (до вычета взносов работника и налога).
    public var gross: Decimal
    public var paidDate: Date? = nil
    public var note: String = ""

    public init(year: Int, month: Int, gross: Decimal) {
        self.year = year
        self.month = month
        self.gross = gross
    }
}

public enum TaxKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case salaryTaxAndContributions, profitAdvance, profitFinal, annualIncomeTax, ecoTax, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .salaryTaxAndContributions: return "Налог и взносы с зарплаты (PPP-PD)"
        case .profitAdvance: return "Аванс налога на прибыль"
        case .profitFinal: return "Доплата налога на прибыль за год"
        case .annualIncomeTax: return "Годовой налог на доход"
        case .ecoTax: return "Эко-налог"
        case .other: return "Прочее"
        }
    }
}

public struct TaxPayment: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    public var kind: TaxKind = .profitAdvance
    public var amountRSD: Decimal = 0
    /// За какой месяц/год платёж (для удобства).
    public var periodYear: Int? = nil
    public var periodMonth: Int? = nil
    public var note: String = ""
    public var attachmentIds: [UUID] = []

    public init() {}
}

/// Перевод с бизнес-счёта на личный сверх зарплаты (изъятие).
public struct OwnerDraw: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date = Date()
    public var amountRSD: Decimal = 0
    public var note: String = ""

    public init() {}
}

/// Файл, загруженный в приложение (скрин, PDF выписки, счёт).
public struct Attachment: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    /// Имя файла внутри папки приложения.
    public var storedFileName: String
    public var originalName: String
    public var addedAt: Date = Date()
    public var recognizedText: String? = nil

    public init(storedFileName: String, originalName: String) {
        self.storedFileName = storedFileName
        self.originalName = originalName
    }
}

/// Оценка на год для авансовой декларации PPDG-1S.
public struct AdvanceEstimate: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var year: Int
    public var estimatedRevenueRSD: Decimal
    public var estimatedExpensesRSD: Decimal
    /// С какого месяца платится аванс (для первого года — месяц регистрации).
    public var firstMonth: Int = 1

    public init(year: Int, estimatedRevenueRSD: Decimal, estimatedExpensesRSD: Decimal, firstMonth: Int = 1) {
        self.year = year
        self.estimatedRevenueRSD = estimatedRevenueRSD
        self.estimatedExpensesRSD = estimatedExpensesRSD
        self.firstMonth = firstMonth
    }
}

// MARK: - Все данные приложения

public struct AppData: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var profile = BusinessProfile()
    public var clients: [Client] = []
    public var invoices: [Invoice] = []
    public var receipts: [Receipt] = []
    public var conversions: [Conversion] = []
    public var expenses: [Expense] = []
    public var salaries: [SalaryPayment] = []
    public var taxPayments: [TaxPayment] = []
    public var ownerDraws: [OwnerDraw] = []
    public var attachments: [Attachment] = []
    public var estimates: [AdvanceEstimate] = []
    public var yearParameters: [YearParameters] = YearParameters.defaults
    /// Кэш средних курсов НБС: ключ "EUR-2026-11-17" → RSD за 1 единицу.
    public var rates: [String: Decimal] = [:]
    public var accounts: [AccountKey: LedgerAccount] = LedgerAccount.defaults

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, profile, clients, invoices, receipts, conversions, expenses, salaries
        case taxPayments, ownerDraws, attachments, estimates, yearParameters, rates, accounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profile = try c.decodeIfPresent(BusinessProfile.self, forKey: .profile) ?? BusinessProfile()
        clients = try c.decodeIfPresent([Client].self, forKey: .clients) ?? []
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        receipts = try c.decodeIfPresent([Receipt].self, forKey: .receipts) ?? []
        conversions = try c.decodeIfPresent([Conversion].self, forKey: .conversions) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        salaries = try c.decodeIfPresent([SalaryPayment].self, forKey: .salaries) ?? []
        taxPayments = try c.decodeIfPresent([TaxPayment].self, forKey: .taxPayments) ?? []
        ownerDraws = try c.decodeIfPresent([OwnerDraw].self, forKey: .ownerDraws) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        estimates = try c.decodeIfPresent([AdvanceEstimate].self, forKey: .estimates) ?? []
        yearParameters = try c.decodeIfPresent([YearParameters].self, forKey: .yearParameters) ?? YearParameters.defaults
        rates = try c.decodeIfPresent([String: Decimal].self, forKey: .rates) ?? [:]
        let storedAccounts = try c.decodeIfPresent([AccountKey: LedgerAccount].self, forKey: .accounts) ?? [:]
        var merged = LedgerAccount.defaults
        for (key, value) in storedAccounts { merged[key] = value }
        accounts = merged
    }

    // MARK: Поиск

    public func client(_ id: UUID?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    public func invoice(_ id: UUID?) -> Invoice? {
        guard let id else { return nil }
        return invoices.first { $0.id == id }
    }

    public func attachment(_ id: UUID) -> Attachment? {
        attachments.first { $0.id == id }
    }

    public func parameters(for year: Int) -> YearParameters {
        if let exact = yearParameters.first(where: { $0.year == year }) { return exact }
        // Нет параметров на этот год — берём ближайший предыдущий (и показываем предупреждение в UI).
        let earlier = yearParameters.filter { $0.year < year }.max { $0.year < $1.year }
        return earlier ?? yearParameters.max { $0.year < $1.year } ?? YearParameters.y2026
    }

    public func hasExactParameters(for year: Int) -> Bool {
        yearParameters.contains { $0.year == year }
    }

    public func estimate(for year: Int) -> AdvanceEstimate? {
        estimates.first { $0.year == year }
    }
}
