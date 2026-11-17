import Foundation

/// Справочник курсов: берёт курс из самой операции или из кэша курсов НБС.
public struct RateBook: Sendable {
    public let cache: [String: Decimal]

    public init(data: AppData) { self.cache = data.rates }

    public static func key(_ currency: Currency, _ date: Date) -> String {
        "\(currency.rawValue)-\(Dates.iso(date))"
    }

    public func rate(_ currency: Currency, on date: Date) -> Decimal? {
        if currency == .RSD { return 1 }
        return cache[Self.key(currency, date)]
    }

    public func invoiceRate(_ invoice: Invoice) -> Decimal? {
        invoice.rateAtService ?? rate(invoice.currency, on: invoice.serviceDate)
    }

    public func receiptRate(_ receipt: Receipt) -> Decimal? {
        receipt.rateAtReceipt ?? rate(receipt.currency, on: receipt.date)
    }
}

public struct ReceiptFX: Equatable, Sendable {
    /// Зачисленная сумма в динарах по курсу на дату поступления.
    public var receivedRSD: Decimal
    /// Комиссия в динарах по курсу на дату поступления.
    public var feeRSD: Decimal
    /// Сколько дебиторки (долга клиента) закрывается — по курсу на дату инвойса.
    public var clearedReceivableRSD: Decimal
    /// Курсовая разница: > 0 доход, < 0 расход.
    public var difference: Decimal
    public var missingRate: Bool
}

public struct ConversionFX: Equatable, Sendable {
    /// Стоимость проданной валюты по среднему курсу НБС.
    public var bookValueRSD: Decimal
    /// Разница между тем, что дал банк, и средним курсом (обычно отрицательная).
    public var difference: Decimal
    public var missingRate: Bool
}

public struct InvoiceStatus: Equatable, Sendable {
    public var paid: Decimal
    public var fees: Decimal
    public var outstanding: Decimal
    public var isPaid: Bool { outstanding <= 0 }
}

public struct YearSummary: Equatable, Sendable {
    public var year: Int
    public var revenueRSD: Decimal = 0
    public var revenueForeignRSD: Decimal = 0
    public var revenueDomesticRSD: Decimal = 0
    public var fxGainsRSD: Decimal = 0
    public var fxLossesRSD: Decimal = 0
    public var feesRSD: Decimal = 0
    public var expensesRSD: Decimal = 0
    public var salaryCostRSD: Decimal = 0
    public var salaryNetRSD: Decimal = 0
    public var salaryToStateRSD: Decimal = 0
    public var advancesPaidRSD: Decimal = 0
    public var missingRates: Int = 0

    public init(year: Int) { self.year = year }

    public var totalIncome: Decimal { revenueRSD + fxGainsRSD }
    public var totalCosts: Decimal { fxLossesRSD + feesRSD + expensesRSD + salaryCostRSD }
    public var profit: Decimal { totalIncome - totalCosts }

    public func profitTax(rate: Decimal) -> Decimal { (max(profit, 0) * rate).roundedTo(2) }
}

public struct Accounting: Sendable {
    public let data: AppData
    public let rates: RateBook

    public init(data: AppData) {
        self.data = data
        self.rates = RateBook(data: data)
    }

    // MARK: Отдельные операции

    public func invoiceRSD(_ invoice: Invoice) -> Decimal? {
        guard let r = rates.invoiceRate(invoice) else { return nil }
        return (invoice.amount * r).roundedTo(2)
    }

    public func expenseRSD(_ e: Expense) -> Decimal? {
        if e.currency == .RSD { return e.amount }
        guard let r = e.rate ?? rates.rate(e.currency, on: e.date) else { return nil }
        return (e.amount * r).roundedTo(2)
    }

    public func receiptFX(_ receipt: Receipt) -> ReceiptFX {
        let receiptRate = rates.receiptRate(receipt)
        let invoiceRate: Decimal? = {
            if let inv = data.invoice(receipt.invoiceId) { return rates.invoiceRate(inv) }
            return receiptRate // без инвойса считаем, что курсовой разницы нет
        }()
        guard let rr = receiptRate, let ir = invoiceRate else {
            return ReceiptFX(receivedRSD: 0, feeRSD: 0, clearedReceivableRSD: 0, difference: 0, missingRate: true)
        }
        let received = (receipt.amount * rr).roundedTo(2)
        let fee = (receipt.fee * rr).roundedTo(2)
        let cleared = ((receipt.amount + receipt.fee) * ir).roundedTo(2)
        return ReceiptFX(receivedRSD: received, feeRSD: fee, clearedReceivableRSD: cleared,
                         difference: received + fee - cleared, missingRate: false)
    }

    public func conversionFX(_ c: Conversion) -> ConversionFX {
        guard let r = c.nbsRate ?? rates.rate(c.currency, on: c.date) else {
            return ConversionFX(bookValueRSD: 0, difference: 0, missingRate: true)
        }
        let book = (c.foreignAmount * r).roundedTo(2)
        return ConversionFX(bookValueRSD: book, difference: c.rsdReceived - book, missingRate: false)
    }

    public func status(of invoice: Invoice) -> InvoiceStatus {
        let related = data.receipts.filter { $0.invoiceId == invoice.id }
        let paid = related.reduce(Decimal(0)) { $0 + $1.amount }
        let fees = related.reduce(Decimal(0)) { $0 + $1.fee }
        return InvoiceStatus(paid: paid, fees: fees, outstanding: invoice.amount - paid - fees)
    }

    // MARK: Итоги за год

    public func summary(year: Int, throughMonth: Int = 12) -> YearSummary {
        var s = YearSummary(year: year)
        func inPeriod(_ d: Date) -> Bool { Dates.year(d) == year && Dates.month(d) <= throughMonth }

        for inv in data.invoices where inPeriod(inv.serviceDate) {
            guard let rsd = invoiceRSD(inv) else { s.missingRates += 1; continue }
            s.revenueRSD += rsd
            if data.client(inv.clientId)?.isForeign ?? true { s.revenueForeignRSD += rsd } else { s.revenueDomesticRSD += rsd }
        }
        for r in data.receipts where inPeriod(r.date) {
            let fx = receiptFX(r)
            if fx.missingRate { s.missingRates += 1; continue }
            if fx.difference > 0 { s.fxGainsRSD += fx.difference } else { s.fxLossesRSD -= fx.difference }
            s.feesRSD += fx.feeRSD
        }
        for c in data.conversions where inPeriod(c.date) {
            let fx = conversionFX(c)
            if fx.missingRate { s.missingRates += 1; continue }
            if fx.difference > 0 { s.fxGainsRSD += fx.difference } else { s.fxLossesRSD -= fx.difference }
        }
        for e in data.expenses where inPeriod(e.date) && e.deductible {
            guard let rsd = expenseRSD(e) else { s.missingRates += 1; continue }
            s.expensesRSD += rsd
        }
        let p = data.parameters(for: year)
        for sal in data.salaries where sal.year == year && sal.month <= throughMonth {
            let b = SalaryCalculator.breakdown(gross: sal.gross, parameters: p)
            s.salaryCostRSD += b.totalCost
            s.salaryNetRSD += b.net
            s.salaryToStateRSD += b.totalToState
        }
        for t in data.taxPayments where t.kind == .profitAdvance {
            let y = t.periodYear ?? Dates.year(t.date)
            if y == year { s.advancesPaidRSD += t.amountRSD }
        }
        return s
    }

    /// Ежемесячный аванс налога на прибыль по авансовой декларации PPDG-1S.
    public func monthlyAdvance(year: Int) -> Decimal? {
        guard let est = data.estimate(for: year) else { return nil }
        let p = data.parameters(for: year)
        let months = max(12 - est.firstMonth + 1, 1)
        let profit = max(est.estimatedRevenueRSD - est.estimatedExpensesRSD, 0)
        return (profit * p.profitTaxRate / Decimal(months)).roundedTo(0)
    }

    /// Оборот за последние 365 дней по сербским клиентам — для порога НДС.
    public func domesticTurnoverLast365(asOf date: Date = Date()) -> Decimal {
        let from = Dates.adding(days: -365, to: date)
        return data.invoices
            .filter { $0.serviceDate > from && $0.serviceDate <= date && !(data.client($0.clientId)?.isForeign ?? true) }
            .compactMap { invoiceRSD($0) }
            .reduce(0, +)
    }

    /// Весь оборот за последние 365 дней (для справки).
    public func totalTurnoverLast365(asOf date: Date = Date()) -> Decimal {
        let from = Dates.adding(days: -365, to: date)
        return data.invoices
            .filter { $0.serviceDate > from && $0.serviceDate <= date }
            .compactMap { invoiceRSD($0) }
            .reduce(0, +)
    }

    /// Оборот бизнес-счёта за последние 6 месяцев — нужен для продления ВНЖ.
    public func receiptsLast6Months(asOf date: Date = Date()) -> Decimal {
        let from = Dates.adding(months: -6, to: date)
        return data.receipts
            .filter { $0.date > from && $0.date <= date }
            .compactMap { r -> Decimal? in
                guard let rate = rates.receiptRate(r) else { return nil }
                return (r.amount * rate).roundedTo(2)
            }
            .reduce(0, +)
    }

    /// Полный налоговый прогноз на год.
    public func taxForecast(year: Int) -> TaxForecast {
        let s = summary(year: year)
        let p = data.parameters(for: year)
        let profitTax = s.profitTax(rate: p.profitTaxRate)
        let income = s.salaryNetRSD + max(s.profit - profitTax, 0)
        let annual = AnnualIncomeTax.estimate(income: income, parameters: p)
        return TaxForecast(summary: s, profitTax: profitTax, annualIncomeTax: annual,
                           salaryToState: s.salaryToStateRSD,
                           remainingProfitTax: profitTax - s.advancesPaidRSD)
    }
}

public struct TaxForecast: Equatable, Sendable {
    public var summary: YearSummary
    public var profitTax: Decimal
    public var annualIncomeTax: AnnualIncomeTaxEstimate
    public var salaryToState: Decimal
    /// > 0 — доплатить до 15 апреля следующего года, < 0 — переплата.
    public var remainingProfitTax: Decimal

    public var totalTaxes: Decimal { profitTax + annualIncomeTax.tax + salaryToState }
}
