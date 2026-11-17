import Foundation
import SwiftUI
import AppKit
import KnjigeCore

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { persist() }
    }
    @Published var year: Int = Dates.year(Date())
    @Published var lastError: String?

    let repository: Repository

    init(repository: Repository = Repository()) {
        self.repository = repository
        var loaded = AppData()
        var loadError: String?
        do {
            loaded = try repository.load()
        } catch {
            loadError = "Не удалось прочитать данные: \(error.localizedDescription). Резервные копии лежат в папке backups."
        }
        self.data = loaded
        self.lastError = loadError
    }

    private func persist() {
        do { try repository.save(data) } catch { lastError = "Не удалось сохранить: \(error.localizedDescription)" }
    }

    var accounting: Accounting { Accounting(data: data) }

    // MARK: Общие операции со списками

    func upsert<T: Identifiable>(_ item: T, in keyPath: WritableKeyPath<AppData, [T]>) where T.ID == UUID {
        if let i = data[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
            data[keyPath: keyPath][i] = item
        } else {
            data[keyPath: keyPath].append(item)
        }
    }

    func delete<T: Identifiable>(_ ids: Set<UUID>, in keyPath: WritableKeyPath<AppData, [T]>) where T.ID == UUID {
        data[keyPath: keyPath].removeAll { ids.contains($0.id) }
    }

    // MARK: Инвойсы

    func suggestedInvoiceNumber(for date: Date = Date()) -> String {
        let p = data.profile
        let prefix = p.invoicePrefix.isEmpty ? "" : p.invoicePrefix
        return "\(prefix)\(p.nextInvoiceNumber)/\(Dates.year(date))"
    }

    func newInvoice() -> Invoice {
        var inv = Invoice()
        let today = Dates.noon(Date())
        inv.issueDate = today
        inv.serviceDate = Dates.lastDay(ofMonth: Dates.month(today), year: Dates.year(today))
        inv.dueDate = Dates.adding(days: 15, to: today)
        inv.number = suggestedInvoiceNumber(for: today)
        if let client = data.clients.first {
            inv.clientId = client.id
            inv.currency = client.defaultCurrency
        }
        // Повторяем сумму и описание последнего инвойса — обычно они одинаковые каждый месяц.
        if let last = data.invoices.max(by: { $0.serviceDate < $1.serviceDate }) {
            inv.amount = last.amount
            inv.description = last.description
            inv.currency = last.currency
            inv.clientId = last.clientId ?? inv.clientId
        }
        return inv
    }

    func saveInvoice(_ invoice: Invoice) {
        let isNew = !data.invoices.contains { $0.id == invoice.id }
        upsert(invoice, in: \.invoices)
        if isNew && invoice.number == suggestedInvoiceNumber(for: invoice.issueDate) {
            data.profile.nextInvoiceNumber += 1
        }
    }

    // MARK: Курсы

    func cachedRate(_ currency: Currency, _ date: Date) -> Decimal? {
        RateBook(data: data).rate(currency, on: date)
    }

    func fetchRate(_ currency: Currency, _ date: Date) async throws -> Decimal {
        if let cached = cachedRate(currency, date) { return cached }
        let rate = try await ExchangeRateService.middleRate(currency, on: date)
        data.rates[RateBook.key(currency, date)] = rate
        return rate
    }

    /// Загружает курсы для всех операций, где курса нет.
    func fetchMissingRates() async -> (loaded: Int, failed: Int) {
        var needed: Set<String> = []
        var requests: [(Currency, Date)] = []
        func need(_ c: Currency, _ d: Date, explicit: Decimal?) {
            guard c != .RSD, explicit == nil, cachedRate(c, d) == nil else { return }
            if needed.insert(RateBook.key(c, d)).inserted { requests.append((c, d)) }
        }
        for i in data.invoices { need(i.currency, i.serviceDate, explicit: i.rateAtService) }
        for r in data.receipts { need(r.currency, r.date, explicit: r.rateAtReceipt) }
        for c in data.conversions { need(c.currency, c.date, explicit: c.nbsRate) }
        for e in data.expenses { need(e.currency, e.date, explicit: e.rate) }
        var loaded = 0, failed = 0
        for (c, d) in requests {
            do { _ = try await fetchRate(c, d); loaded += 1 } catch { failed += 1 }
        }
        return (loaded, failed)
    }

    // MARK: Файлы

    func addAttachment(from url: URL) throws -> Attachment {
        let attachment = try repository.importFile(from: url)
        data.attachments.append(attachment)
        return attachment
    }

    func addAttachment(image: NSImage, name: String = "Скриншот") throws -> Attachment {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Knjige", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать картинку из буфера"])
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name) \(Dates.iso(Date())) \(UUID().uuidString.prefix(4)).png")
        try png.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try addAttachment(from: tmp)
    }

    func setRecognizedText(_ text: String, for id: UUID) {
        if let i = data.attachments.firstIndex(where: { $0.id == id }) {
            data.attachments[i].recognizedText = text
        }
    }

    func url(for attachment: Attachment) -> URL { repository.url(for: attachment) }

    func removeAttachment(_ id: UUID) {
        guard let a = data.attachment(id) else { return }
        repository.deleteFile(a)
        data.attachments.removeAll { $0.id == id }
    }

    /// Файлы, которые не привязаны ни к одной операции.
    var unlinkedAttachments: [Attachment] {
        var linked = Set<UUID>()
        data.invoices.forEach { linked.formUnion($0.attachmentIds) }
        data.receipts.forEach { linked.formUnion($0.attachmentIds) }
        data.conversions.forEach { linked.formUnion($0.attachmentIds) }
        data.expenses.forEach { linked.formUnion($0.attachmentIds) }
        data.taxPayments.forEach { linked.formUnion($0.attachmentIds) }
        return data.attachments.filter { !linked.contains($0.id) }.sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: Зарплата

    func salary(year: Int, month: Int) -> SalaryPayment? {
        data.salaries.first { $0.year == year && $0.month == month }
    }

    func setSalary(_ salary: SalaryPayment) {
        data.salaries.removeAll { $0.year == salary.year && $0.month == salary.month && $0.id != salary.id }
        upsert(salary, in: \.salaries)
    }

    // MARK: Годы

    var availableYears: [Int] {
        var years = Set<Int>([Dates.year(Date())])
        data.invoices.forEach { years.insert(Dates.year($0.serviceDate)) }
        data.receipts.forEach { years.insert(Dates.year($0.date)) }
        data.salaries.forEach { years.insert($0.year) }
        if let reg = data.profile.registrationDate { years.insert(Dates.year(reg)) }
        return years.sorted()
    }
}
