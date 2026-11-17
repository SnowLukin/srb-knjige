import Foundation

/// Экспорт в CSV (открывается в Numbers/Excel) — для бухгалтера или собственной проверки.
public enum CSVExport {
    static func escape(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func number(_ d: Decimal) -> String {
        // Запятая как десятичный разделитель — так ждут европейские Numbers/Excel; разделитель полей — «;».
        NSDecimalNumber(decimal: d.roundedTo(2)).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    static func row(_ fields: [String]) -> String { fields.map(escape).joined(separator: ";") }

    public static func journal(_ entries: [JournalEntry], accounts: [AccountKey: LedgerAccount]) -> String {
        var lines = [row(["Дата", "Описание", "Счёт", "Название счёта", "Дебет", "Кредит"])]
        for e in entries {
            for l in e.lines {
                let acc = accounts[l.account] ?? LedgerAccount.defaults[l.account]!
                lines.append(row([Dates.display(e.date), e.description, acc.code, acc.name,
                                  l.debit == 0 ? "" : number(l.debit), l.credit == 0 ? "" : number(l.credit)]))
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func invoices(_ data: AppData) -> String {
        let acc = Accounting(data: data)
        var lines = [row(["Номер", "Дата выставления", "Дата услуги", "Клиент", "Сумма", "Валюта", "Курс НБС", "Сумма RSD", "Оплачено", "Остаток"])]
        for inv in data.invoices.sorted(by: { $0.serviceDate < $1.serviceDate }) {
            let st = acc.status(of: inv)
            let rate = acc.rates.invoiceRate(inv)
            lines.append(row([inv.number, Dates.display(inv.issueDate), Dates.display(inv.serviceDate),
                              data.client(inv.clientId)?.name ?? "", number(inv.amount), inv.currency.rawValue,
                              rate.map(number) ?? "", acc.invoiceRSD(inv).map(number) ?? "",
                              number(st.paid), number(st.outstanding)]))
        }
        return lines.joined(separator: "\n")
    }

    public static func receipts(_ data: AppData) -> String {
        let acc = Accounting(data: data)
        var lines = [row(["Дата", "Источник", "Сумма", "Валюта", "Комиссия", "Курс НБС", "Сумма RSD", "Курсовая разница RSD", "Инвойс"])]
        for r in data.receipts.sorted(by: { $0.date < $1.date }) {
            let fx = acc.receiptFX(r)
            lines.append(row([Dates.display(r.date), r.source, number(r.amount), r.currency.rawValue, number(r.fee),
                              acc.rates.receiptRate(r).map(number) ?? "", number(fx.receivedRSD), number(fx.difference),
                              data.invoice(r.invoiceId)?.number ?? ""]))
        }
        return lines.joined(separator: "\n")
    }

    public static func expenses(_ data: AppData) -> String {
        let acc = Accounting(data: data)
        var lines = [row(["Дата", "Описание", "Категория", "Поставщик", "Сумма", "Валюта", "Сумма RSD", "Учитывается"])]
        for e in data.expenses.sorted(by: { $0.date < $1.date }) {
            lines.append(row([Dates.display(e.date), e.description, e.category.title, e.supplier, number(e.amount),
                              e.currency.rawValue, acc.expenseRSD(e).map(number) ?? "", e.deductible ? "да" : "нет"]))
        }
        return lines.joined(separator: "\n")
    }
}

/// Текстовая годовая сводка — то, что понадобится для PPDG-1S/PB 2 и годового отчёта.
public enum AnnualReport {
    public static func text(year: Int, data: AppData) -> String {
        let acc = Accounting(data: data)
        let f = acc.taxForecast(year: year)
        let s = f.summary
        let p = data.parameters(for: year)
        var out: [String] = []
        out.append("ГОДОВАЯ СВОДКА \(year) — \(data.profile.businessName)")
        out.append("ПИБ \(data.profile.pib), МБ \(data.profile.maticniBroj)")
        out.append("")
        out.append("ДОХОДЫ")
        out.append("  Выручка от услуг: \(Money.rsd(s.revenueRSD, fraction: 2))")
        out.append("    из них зарубежные клиенты: \(Money.rsd(s.revenueForeignRSD, fraction: 2))")
        out.append("    из них сербские клиенты: \(Money.rsd(s.revenueDomesticRSD, fraction: 2))")
        out.append("  Положительные курсовые разницы: \(Money.rsd(s.fxGainsRSD, fraction: 2))")
        out.append("РАСХОДЫ")
        out.append("  Личная зарплата (бруто 2): \(Money.rsd(s.salaryCostRSD, fraction: 2))")
        out.append("  Отрицательные курсовые разницы: \(Money.rsd(s.fxLossesRSD, fraction: 2))")
        out.append("  Комиссии: \(Money.rsd(s.feesRSD, fraction: 2))")
        out.append("  Прочие расходы: \(Money.rsd(s.expensesRSD, fraction: 2))")
        out.append("")
        out.append("ПРИБЫЛЬ: \(Money.rsd(s.profit, fraction: 2))")
        out.append("Налог на прибыль \(NSDecimalNumber(decimal: p.profitTaxRate * 100).intValue) %: \(Money.rsd(f.profitTax, fraction: 2))")
        out.append("Уплачено авансов: \(Money.rsd(s.advancesPaidRSD, fraction: 2))")
        out.append(f.remainingProfitTax >= 0
                   ? "К доплате до 15 апреля: \(Money.rsd(f.remainingProfitTax, fraction: 2))"
                   : "Переплата: \(Money.rsd(-f.remainingProfitTax, fraction: 2))")
        out.append("")
        out.append("Налог и взносы с зарплаты за год: \(Money.rsd(s.salaryToStateRSD, fraction: 2))")
        out.append("Годовой налог на доход (оценка): \(Money.rsd(f.annualIncomeTax.tax, fraction: 2))")
        out.append("ВСЕГО налогов и взносов: \(Money.rsd(f.totalTaxes, fraction: 2))")
        if s.missingRates > 0 {
            out.append("")
            out.append("⚠️ Операций без курса НБС: \(s.missingRates) — итоги неполные.")
        }
        out.append("")
        out.append("Это расчёт приложения, а не официальный отчёт. Формы PPDG-1S, PB 2 и финансовый отчёт APR заполняются на их порталах.")
        return out.joined(separator: "\n")
    }
}
