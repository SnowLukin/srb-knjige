import SwiftUI
import KnjigeCore

struct ReceiptsView: View {
    @EnvironmentObject var store: Store
    @State private var selection = Set<UUID>()
    @State private var editing: Receipt?

    private var rows: [Receipt] {
        store.data.receipts.filter { Dates.year($0.date) == store.year }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Поступления", subtitle: "Деньги, пришедшие на бизнес-счёт. Курсовая разница считается автоматически.") {
                Button { editing = newReceipt() } label: { Label("Новое поступление", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
            let acc = store.accounting
            Table(rows, selection: $selection) {
                TableColumn("Дата") { (r: Receipt) in Text(Dates.display(r.date)) }.width(90)
                TableColumn("Источник") { (r: Receipt) in Text(r.source) }
                TableColumn("Зачислено") { (r: Receipt) in Text(Money.string(r.amount, r.currency)).monospacedDigit() }
                TableColumn("Комиссия") { (r: Receipt) in
                    Text(r.fee == 0 ? "—" : Money.string(r.fee, r.currency)).monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("В динарах") { (r: Receipt) in
                    let fx = acc.receiptFX(r)
                    Text(fx.missingRate ? "нет курса" : Money.rsd(fx.receivedRSD))
                        .foregroundStyle(fx.missingRate ? .orange : .primary).monospacedDigit()
                }
                TableColumn("Курсовая разница") { (r: Receipt) in
                    let fx = acc.receiptFX(r)
                    Text(fx.missingRate ? "—" : Money.rsd(fx.difference, fraction: 2))
                        .foregroundStyle(fx.difference >= 0 ? .green : .red).monospacedDigit()
                }
                TableColumn("Инвойс") { (r: Receipt) in Text(store.data.invoice(r.invoiceId)?.number ?? "не привязан") }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, ids.count == 1, let r = store.data.receipts.first(where: { $0.id == id }) {
                    Button("Изменить") { editing = r }
                }
                Button("Удалить", role: .destructive) { store.delete(ids, in: \.receipts) }
            } primaryAction: { ids in
                if let id = ids.first { editing = store.data.receipts.first { $0.id == id } }
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("Поступлений нет", systemImage: "arrow.down.circle",
                                           description: Text("Добавь вручную или загрузи скрин выплаты из Deel в разделе «Импорт»."))
                }
            }
        }
        .sheet(item: $editing) { r in
            ReceiptEditor(receipt: r) { store.upsert($0, in: \.receipts) }.environmentObject(store)
        }
    }

    private func newReceipt() -> Receipt {
        var r = Receipt()
        r.date = Dates.noon(Date())
        let acc = store.accounting
        // Привязываем к самому старому неоплаченному инвойсу.
        if let inv = store.data.invoices.sorted(by: { $0.serviceDate < $1.serviceDate }).first(where: { !acc.status(of: $0).isPaid }) {
            r.invoiceId = inv.id
            r.currency = inv.currency
            r.amount = acc.status(of: inv).outstanding
        }
        return r
    }
}

struct ReceiptEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Receipt
    let onSave: (Receipt) -> Void

    init(receipt: Receipt, onSave: @escaping (Receipt) -> Void) {
        _draft = State(initialValue: receipt)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Поступление") {
                    DayPicker(title: "Дата зачисления на счёт", date: $draft.date)
                    TextField("Откуда (Deel, клиент…)", text: $draft.source)
                    HStack {
                        DecimalField("Зачислено", value: $draft.amount)
                        Picker("", selection: $draft.currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    DecimalField("Удержанная комиссия", value: $draft.fee)
                    Text("Комиссия — разница между суммой инвойса и тем, что реально пришло (комиссия Deel, банков-посредников).")
                        .font(.caption).foregroundStyle(.secondary)
                    RateRow(title: "Курс НБС на дату зачисления", currency: draft.currency, date: draft.date, rate: $draft.rateAtReceipt)
                }
                Section("За какой инвойс") {
                    Picker("Инвойс", selection: $draft.invoiceId) {
                        Text("Не привязан").tag(UUID?.none)
                        ForEach(store.data.invoices.sorted { $0.serviceDate > $1.serviceDate }) { inv in
                            Text("\(inv.number) — \(Money.string(inv.amount, inv.currency)) (\(Dates.display(inv.serviceDate)))")
                                .tag(UUID?.some(inv.id))
                        }
                    }
                    if let inv = store.data.invoice(draft.invoiceId) {
                        let others = store.data.receipts.filter { $0.invoiceId == inv.id && $0.id != draft.id }
                        let paidBefore = others.reduce(Decimal(0)) { $0 + $1.amount + $1.fee }
                        let rest = inv.amount - paidBefore - draft.amount - draft.fee
                        ValueRow(label: "Сумма инвойса", value: Money.string(inv.amount, inv.currency))
                        if rest > 0 {
                            HStack {
                                Text("Не хватает до суммы инвойса: \(Money.string(rest, inv.currency))").foregroundStyle(.orange)
                                Spacer()
                                Button("Записать как комиссию") { draft.fee += rest }
                            }
                        } else if rest < 0 {
                            Text("Пришло больше суммы инвойса на \(Money.string(-rest, inv.currency))").foregroundStyle(.orange)
                        }
                        if inv.currency != draft.currency {
                            Text("Валюта поступления отличается от валюты инвойса — курсовая разница будет посчитана неверно.")
                                .foregroundStyle(.red).font(.caption)
                        }
                    }
                }
                Section("Расчёт") {
                    let fx = Accounting(data: store.data).receiptFX(draft)
                    if fx.missingRate {
                        Text("Нужен курс на дату зачисления и на дату услуги инвойса.").foregroundStyle(.orange)
                    } else {
                        ValueRow(label: "Зачислено в динарах", value: Money.rsd(fx.receivedRSD, fraction: 2))
                        ValueRow(label: "Комиссия в динарах (расход)", value: Money.rsd(fx.feeRSD, fraction: 2))
                        ValueRow(label: "Закрыто долга клиента (по курсу инвойса)", value: Money.rsd(fx.clearedReceivableRSD, fraction: 2))
                        ValueRow(label: fx.difference >= 0 ? "Положительная курсовая разница (доход)" : "Отрицательная курсовая разница (расход)",
                                 value: Money.rsd(fx.difference, fraction: 2), bold: true)
                    }
                }
                Section("Заметка и файлы") {
                    TextField("Заметка", text: $draft.note, axis: .vertical)
                    AttachmentsEditor(ids: $draft.attachmentIds)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.amount <= 0)
            }
            .padding()
        }
        .frame(width: 600, height: 760)
    }
}

// MARK: - Конвертации

struct ConversionsView: View {
    @EnvironmentObject var store: Store
    @State private var selection = Set<UUID>()
    @State private var editing: Conversion?

    private var rows: [Conversion] {
        store.data.conversions.filter { Dates.year($0.date) == store.year }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Конвертации", subtitle: "Продажа евро банку. Разница с курсом НБС — курсовой доход или расход.") {
                Button {
                    var c = Conversion()
                    c.date = Dates.noon(Date())
                    editing = c
                } label: { Label("Новая конвертация", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
            let acc = store.accounting
            Table(rows, selection: $selection) {
                TableColumn("Дата") { (c: Conversion) in Text(Dates.display(c.date)) }.width(90)
                TableColumn("Продано") { (c: Conversion) in Text(Money.string(c.foreignAmount, c.currency)).monospacedDigit() }
                TableColumn("Получено") { (c: Conversion) in Text(Money.rsd(c.rsdReceived, fraction: 2)).monospacedDigit() }
                TableColumn("Курс банка") { (c: Conversion) in
                    Text(c.foreignAmount > 0 ? Money.plain(c.rsdReceived / c.foreignAmount, maxFraction: 4) : "—").monospacedDigit()
                }
                TableColumn("Курс НБС") { (c: Conversion) in
                    let r = c.nbsRate ?? store.cachedRate(c.currency, c.date)
                    Text(r.map { Money.plain($0, maxFraction: 4) } ?? "нет курса").monospacedDigit()
                        .foregroundStyle(r == nil ? .orange : .primary)
                }
                TableColumn("Разница") { (c: Conversion) in
                    let fx = acc.conversionFX(c)
                    Text(fx.missingRate ? "—" : Money.rsd(fx.difference, fraction: 2))
                        .foregroundStyle(fx.difference >= 0 ? .green : .red).monospacedDigit()
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, ids.count == 1, let c = store.data.conversions.first(where: { $0.id == id }) {
                    Button("Изменить") { editing = c }
                }
                Button("Удалить", role: .destructive) { store.delete(ids, in: \.conversions) }
            } primaryAction: { ids in
                if let id = ids.first { editing = store.data.conversions.first { $0.id == id } }
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("Конвертаций нет", systemImage: "arrow.left.arrow.right.circle",
                                           description: Text("Записывай каждую продажу валюты из выписки банка."))
                }
            }
        }
        .sheet(item: $editing) { c in
            ConversionEditor(conversion: c) { store.upsert($0, in: \.conversions) }.environmentObject(store)
        }
    }
}

struct ConversionEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Conversion
    let onSave: (Conversion) -> Void

    init(conversion: Conversion, onSave: @escaping (Conversion) -> Void) {
        _draft = State(initialValue: conversion)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Конвертация") {
                    DayPicker(title: "Дата", date: $draft.date)
                    HStack {
                        DecimalField("Продано валюты", value: $draft.foreignAmount)
                        Picker("", selection: $draft.currency) {
                            ForEach(Currency.allCases.filter { $0 != .RSD }) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    DecimalField("Получено динаров", value: $draft.rsdReceived)
                    RateRow(title: "Средний курс НБС на дату", currency: draft.currency, date: draft.date, rate: $draft.nbsRate)
                    let fx = Accounting(data: store.data).conversionFX(draft)
                    if !fx.missingRate {
                        ValueRow(label: "По курсу НБС", value: Money.rsd(fx.bookValueRSD, fraction: 2))
                        ValueRow(label: fx.difference >= 0 ? "Курсовой доход" : "Курсовой расход",
                                 value: Money.rsd(fx.difference, fraction: 2), bold: true)
                    }
                }
                Section("Заметка и файлы") {
                    TextField("Заметка", text: $draft.note, axis: .vertical)
                    AttachmentsEditor(ids: $draft.attachmentIds)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.foreignAmount <= 0 || draft.rsdReceived <= 0)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
    }
}
