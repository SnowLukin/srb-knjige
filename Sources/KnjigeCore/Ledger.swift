import Foundation

/// Счета, которые использует приложение. Коды по умолчанию взяты из сербского плана счетов
/// для микропредприятий, но их ОБЯЗАТЕЛЬНО нужно сверить (Настройки → Счета).
public enum AccountKey: String, Codable, CaseIterable, Identifiable, Sendable, CodingKeyRepresentable {
    case foreignCustomers      // Клиенты за рубежом (дебиторка)
    case domesticCustomers     // Клиенты в Сербии
    case businessAccountRSD    // Динарный бизнес-счёт
    case businessAccountFX     // Валютный бизнес-счёт
    case foreignServiceRevenue // Выручка от услуг на иностранном рынке
    case domesticServiceRevenue
    case fxGains               // Положительные курсовые разницы
    case fxLosses              // Отрицательные курсовые разницы
    case bankFees              // Расходы на платёжный оборот и комиссии
    case salaryGross           // Расходы на зарплату (бруто 1)
    case salaryEmployerContrib // Взносы за счёт работодателя
    case netSalaryPayable      // Обязательства по нетто-зарплате
    case salaryTaxPayable      // Обязательства по налогу на зарплату
    case employeeContribPayable
    case employerContribPayable
    case servicesExpense       // Прочие услуги (бухгалтер, юрадрес и т. п.)
    case rentExpense
    case materialsExpense      // Софт, мелкая техника
    case otherExpense
    case ownerDrawings         // Изъятия предпринимателя
    case profitTaxAdvance      // Авансы налога на прибыль предпринимателя

    public var id: String { rawValue }
}

public struct LedgerAccount: Codable, Equatable, Sendable {
    public var code: String
    public var name: String
    public var nameRu: String

    public init(code: String, name: String, nameRu: String) {
        self.code = code
        self.name = name
        self.nameRu = nameRu
    }

    public static let defaults: [AccountKey: LedgerAccount] = [
        .foreignCustomers: .init(code: "204", name: "Kupci u inostranstvu", nameRu: "Клиенты за рубежом"),
        .domesticCustomers: .init(code: "202", name: "Kupci u zemlji", nameRu: "Клиенты в Сербии"),
        .businessAccountRSD: .init(code: "241", name: "Tekući (poslovni) računi", nameRu: "Бизнес-счёт RSD"),
        .businessAccountFX: .init(code: "244", name: "Devizni račun", nameRu: "Валютный бизнес-счёт"),
        .foreignServiceRevenue: .init(code: "614", name: "Prihodi od prodaje usluga na inostranom tržištu", nameRu: "Выручка от услуг (зарубеж)"),
        .domesticServiceRevenue: .init(code: "612", name: "Prihodi od prodaje usluga na domaćem tržištu", nameRu: "Выручка от услуг (Сербия)"),
        .fxGains: .init(code: "663", name: "Pozitivne kursne razlike", nameRu: "Положительные курсовые разницы"),
        .fxLosses: .init(code: "563", name: "Negativne kursne razlike", nameRu: "Отрицательные курсовые разницы"),
        .bankFees: .init(code: "553", name: "Troškovi platnog prometa", nameRu: "Банковские комиссии"),
        .salaryGross: .init(code: "520", name: "Troškovi zarada i naknada zarada (bruto)", nameRu: "Зарплата (бруто 1)"),
        .salaryEmployerContrib: .init(code: "521", name: "Troškovi poreza i doprinosa na zarade na teret poslodavca", nameRu: "Взносы работодателя"),
        .netSalaryPayable: .init(code: "450", name: "Obaveze za neto zarade", nameRu: "Нетто-зарплата к выплате"),
        .salaryTaxPayable: .init(code: "451", name: "Obaveze za porez na zarade", nameRu: "Налог на зарплату к уплате"),
        .employeeContribPayable: .init(code: "452", name: "Obaveze za doprinose na zarade na teret zaposlenog", nameRu: "Взносы работника к уплате"),
        .employerContribPayable: .init(code: "453", name: "Obaveze za doprinose na zarade na teret poslodavca", nameRu: "Взносы работодателя к уплате"),
        .servicesExpense: .init(code: "539", name: "Troškovi ostalih usluga", nameRu: "Прочие услуги"),
        .rentExpense: .init(code: "533", name: "Troškovi zakupnina", nameRu: "Аренда"),
        .materialsExpense: .init(code: "512", name: "Troškovi ostalog materijala", nameRu: "Материалы, софт, мелкая техника"),
        .otherExpense: .init(code: "559", name: "Ostali nematerijalni troškovi", nameRu: "Прочие расходы"),
        .ownerDrawings: .init(code: "?", name: "Podizanje sredstava preduzetnika", nameRu: "Изъятия предпринимателя"),
        .profitTaxAdvance: .init(code: "?", name: "Akontacija poreza na prihod od samostalne delatnosti", nameRu: "Аванс налога на прибыль")
    ]
}

public struct JournalLine: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var account: AccountKey
    public var debit: Decimal
    public var credit: Decimal
}

public struct JournalEntry: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var description: String
    public var lines: [JournalLine]
    /// Предупреждение, если для операции не хватает данных (например, нет курса).
    public var warning: String?

    public var totalDebit: Decimal { lines.reduce(0) { $0 + $1.debit } }
    public var totalCredit: Decimal { lines.reduce(0) { $0 + $1.credit } }
    public var isBalanced: Bool { (totalDebit - totalCredit).roundedTo(2) == 0 }
}

/// Строит журнал двойной записи из операций.
public struct LedgerBuilder {
    public let data: AppData
    public let rates: RateBook

    public init(data: AppData) {
        self.data = data
        self.rates = RateBook(data: data)
    }

    public func entries(year: Int) -> [JournalEntry] {
        var result: [JournalEntry] = []

        for invoice in data.invoices where Dates.year(invoice.serviceDate) == year {
            result.append(invoiceEntry(invoice))
        }
        for receipt in data.receipts where Dates.year(receipt.date) == year {
            result.append(receiptEntry(receipt))
        }
        for conversion in data.conversions where Dates.year(conversion.date) == year {
            result.append(conversionEntry(conversion))
        }
        for expense in data.expenses where Dates.year(expense.date) == year && expense.deductible {
            result.append(expenseEntry(expense))
        }
        for salary in data.salaries where salary.year == year {
            result.append(contentsOf: salaryEntries(salary))
        }
        for payment in data.taxPayments where Dates.year(payment.date) == year {
            result.append(taxPaymentEntry(payment))
        }
        for draw in data.ownerDraws where Dates.year(draw.date) == year {
            result.append(JournalEntry(
                date: draw.date,
                description: "Перевод на личный счёт" + (draw.note.isEmpty ? "" : ": \(draw.note)"),
                lines: [
                    JournalLine(account: .ownerDrawings, debit: draw.amountRSD, credit: 0),
                    JournalLine(account: .businessAccountRSD, debit: 0, credit: draw.amountRSD)
                ]))
        }
        return result.sorted { $0.date < $1.date }
    }

    func revenueAccount(for invoice: Invoice) -> (customer: AccountKey, revenue: AccountKey) {
        let foreign = data.client(invoice.clientId)?.isForeign ?? true
        return foreign ? (.foreignCustomers, .foreignServiceRevenue) : (.domesticCustomers, .domesticServiceRevenue)
    }

    func invoiceEntry(_ invoice: Invoice) -> JournalEntry {
        let rate = rates.invoiceRate(invoice)
        let rsd = ((rate ?? 0) * invoice.amount).roundedTo(2)
        let accounts = revenueAccount(for: invoice)
        let clientName = data.client(invoice.clientId)?.name ?? "клиент"
        return JournalEntry(
            date: invoice.serviceDate,
            description: "Инвойс \(invoice.number) — \(clientName), \(Money.string(invoice.amount, invoice.currency))",
            lines: [
                JournalLine(account: accounts.customer, debit: rsd, credit: 0),
                JournalLine(account: accounts.revenue, debit: 0, credit: rsd)
            ],
            warning: rate == nil ? "Нет курса НБС на дату оказания услуги" : nil)
    }

    func receiptEntry(_ receipt: Receipt) -> JournalEntry {
        let fx = Accounting(data: data).receiptFX(receipt)
        var lines: [JournalLine] = []
        let cash: AccountKey = receipt.currency == .RSD ? .businessAccountRSD : .businessAccountFX
        let customer: AccountKey = {
            if let inv = data.invoice(receipt.invoiceId) { return revenueAccount(for: inv).customer }
            return .foreignCustomers
        }()
        lines.append(JournalLine(account: cash, debit: fx.receivedRSD, credit: 0))
        if fx.feeRSD > 0 {
            lines.append(JournalLine(account: .bankFees, debit: fx.feeRSD, credit: 0))
        }
        lines.append(JournalLine(account: customer, debit: 0, credit: fx.clearedReceivableRSD))
        if fx.difference > 0 {
            lines.append(JournalLine(account: .fxGains, debit: 0, credit: fx.difference))
        } else if fx.difference < 0 {
            lines.append(JournalLine(account: .fxLosses, debit: -fx.difference, credit: 0))
        }
        var warning: String? = nil
        if receipt.invoiceId == nil { warning = "Поступление не привязано к инвойсу" }
        if fx.missingRate { warning = "Нет курса НБС" }
        return JournalEntry(
            date: receipt.date,
            description: "Поступление \(Money.string(receipt.amount, receipt.currency)) от \(receipt.source)",
            lines: lines,
            warning: warning)
    }

    func conversionEntry(_ c: Conversion) -> JournalEntry {
        let fx = Accounting(data: data).conversionFX(c)
        var lines = [
            JournalLine(account: .businessAccountRSD, debit: c.rsdReceived, credit: 0),
            JournalLine(account: .businessAccountFX, debit: 0, credit: fx.bookValueRSD)
        ]
        if fx.difference > 0 {
            lines.append(JournalLine(account: .fxGains, debit: 0, credit: fx.difference))
        } else if fx.difference < 0 {
            lines.append(JournalLine(account: .fxLosses, debit: -fx.difference, credit: 0))
        }
        return JournalEntry(
            date: c.date,
            description: "Продажа \(Money.string(c.foreignAmount, c.currency)) банку",
            lines: lines,
            warning: fx.missingRate ? "Нет курса НБС" : nil)
    }

    func expenseAccount(_ category: ExpenseCategory) -> AccountKey {
        switch category {
        case .accountant, .legalAddress, .translation: return .servicesExpense
        case .bankFees: return .bankFees
        case .software, .equipment: return .materialsExpense
        case .rent: return .rentExpense
        case .other: return .otherExpense
        }
    }

    func expenseEntry(_ e: Expense) -> JournalEntry {
        let rsd = Accounting(data: data).expenseRSD(e)
        return JournalEntry(
            date: e.date,
            description: "Расход: \(e.description.isEmpty ? e.category.title : e.description)",
            lines: [
                JournalLine(account: expenseAccount(e.category), debit: rsd ?? 0, credit: 0),
                JournalLine(account: .businessAccountRSD, debit: 0, credit: rsd ?? 0)
            ],
            warning: rsd == nil ? "Нет курса НБС" : nil)
    }

    func salaryEntries(_ s: SalaryPayment) -> [JournalEntry] {
        let p = data.parameters(for: s.year)
        let b = SalaryCalculator.breakdown(gross: s.gross, parameters: p)
        let date = Dates.lastDay(ofMonth: s.month, year: s.year)
        var entries = [JournalEntry(
            date: date,
            description: "Начисление личной зарплаты за \(Dates.monthName(s.month)) \(s.year)",
            lines: [
                JournalLine(account: .salaryGross, debit: b.gross, credit: 0),
                JournalLine(account: .salaryEmployerContrib, debit: b.employerContributions, credit: 0),
                JournalLine(account: .netSalaryPayable, debit: 0, credit: b.net),
                JournalLine(account: .salaryTaxPayable, debit: 0, credit: b.salaryTax),
                JournalLine(account: .employeeContribPayable, debit: 0, credit: b.employeeContributions),
                JournalLine(account: .employerContribPayable, debit: 0, credit: b.employerContributions)
            ])]
        if let paid = s.paidDate {
            entries.append(JournalEntry(
                date: paid,
                description: "Выплата зарплаты за \(Dates.monthName(s.month)) и уплата налога и взносов",
                lines: [
                    JournalLine(account: .netSalaryPayable, debit: b.net, credit: 0),
                    JournalLine(account: .salaryTaxPayable, debit: b.salaryTax, credit: 0),
                    JournalLine(account: .employeeContribPayable, debit: b.employeeContributions, credit: 0),
                    JournalLine(account: .employerContribPayable, debit: b.employerContributions, credit: 0),
                    JournalLine(account: .businessAccountRSD, debit: 0, credit: b.net + b.totalToState)
                ]))
        }
        return entries
    }

    func taxPaymentEntry(_ t: TaxPayment) -> JournalEntry {
        let debitAccount: AccountKey
        switch t.kind {
        case .salaryTaxAndContributions:
            // Налог и взносы с зарплаты уже закрываются записью «Выплата зарплаты», если указана дата выплаты.
            debitAccount = .salaryTaxPayable
        case .profitAdvance, .profitFinal, .annualIncomeTax:
            debitAccount = .profitTaxAdvance
        case .ecoTax, .other:
            debitAccount = .otherExpense
        }
        return JournalEntry(
            date: t.date,
            description: "Уплата: \(t.kind.title)",
            lines: [
                JournalLine(account: debitAccount, debit: t.amountRSD, credit: 0),
                JournalLine(account: .businessAccountRSD, debit: 0, credit: t.amountRSD)
            ],
            warning: t.kind == .salaryTaxAndContributions
                ? "Не дублируй: если у зарплаты указана дата выплаты, налог и взносы уже учтены"
                : nil)
    }

    /// Обороты и сальдо по счетам за год.
    public func trialBalance(year: Int) -> [(key: AccountKey, debit: Decimal, credit: Decimal)] {
        var sums: [AccountKey: (Decimal, Decimal)] = [:]
        for entry in entries(year: year) {
            for line in entry.lines {
                let current = sums[line.account] ?? (0, 0)
                sums[line.account] = (current.0 + line.debit, current.1 + line.credit)
            }
        }
        return AccountKey.allCases.compactMap { key in
            guard let s = sums[key] else { return nil }
            return (key, s.0, s.1)
        }
    }
}
