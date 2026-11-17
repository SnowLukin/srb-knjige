import SwiftUI
import AppKit
import KnjigeCore

struct InvoicesView: View {
    @EnvironmentObject var store: Store
    @State private var selection = Set<UUID>()
    @State private var editing: Invoice?
    @State private var confirmDelete: Set<UUID>?

    private var rows: [Invoice] {
        store.data.invoices
            .filter { Dates.year($0.serviceDate) == store.year }
            .sorted { $0.serviceDate > $1.serviceDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Инвойсы", subtitle: "Счета клиенту. Выручка признаётся по курсу НБС на дату оказания услуги.") {
                Button { editing = store.newInvoice() } label: { Label("Новый инвойс", systemImage: "plus") }
                    .keyboardShortcut("n")
                    .disabled(store.data.clients.isEmpty)
            }
            if store.data.clients.isEmpty {
                InfoBox(text: "Сначала добавь клиента в «Настройках» → «Клиенты» (например, Deel или компанию заказчика — того, кому ты выставляешь счёт).", tint: .orange)
                    .padding()
            }
            let acc = store.accounting
            Table(rows, selection: $selection) {
                TableColumn("Номер") { (inv: Invoice) in Text(inv.number) }
                    .width(min: 70, ideal: 90)
                TableColumn("Дата услуги") { (inv: Invoice) in Text(Dates.display(inv.serviceDate)) }
                    .width(90)
                TableColumn("Клиент") { (inv: Invoice) in Text(store.data.client(inv.clientId)?.name ?? "—") }
                TableColumn("Сумма") { (inv: Invoice) in
                    Text(Money.string(inv.amount, inv.currency)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("Курс") { (inv: Invoice) in
                    Text(acc.rates.invoiceRate(inv).map { Money.plain($0, maxFraction: 4) } ?? "нет курса")
                        .foregroundStyle(acc.rates.invoiceRate(inv) == nil ? .orange : .secondary)
                        .monospacedDigit()
                }
                .width(80)
                TableColumn("В динарах") { (inv: Invoice) in
                    Text(acc.invoiceRSD(inv).map { Money.rsd($0) } ?? "—").monospacedDigit()
                }
                .width(min: 100, ideal: 120)
                TableColumn("Статус") { (inv: Invoice) in
                    let st = acc.status(of: inv)
                    if st.isPaid {
                        Label("Оплачен", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if st.paid > 0 {
                        Text("Остаток \(Money.string(st.outstanding, inv.currency))").foregroundStyle(.orange)
                    } else {
                        Text("Ждёт оплаты").foregroundStyle(.secondary)
                    }
                }
                .width(min: 110, ideal: 140)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let id = ids.first, let inv = store.data.invoice(id) {
                    Button("Изменить") { editing = inv }
                    Button("Сохранить PDF…") { InvoicePDF.export(inv, store: store) }
                    Button("Дублировать на следующий месяц") { editing = duplicate(inv) }
                    Divider()
                }
                Button("Удалить", role: .destructive) { confirmDelete = ids }
            } primaryAction: { ids in
                if let id = ids.first { editing = store.data.invoice(id) }
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("Инвойсов за \(String(store.year)) нет", systemImage: "doc.text",
                                           description: Text("Создай первый инвойс кнопкой «Новый инвойс»."))
                }
            }
        }
        .sheet(item: $editing) { inv in
            InvoiceEditor(invoice: inv) { store.saveInvoice($0) }
                .environmentObject(store)
        }
        .confirmationDialog("Удалить выбранные инвойсы?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Удалить", role: .destructive) {
                if let ids = confirmDelete { store.delete(ids, in: \.invoices) }
                confirmDelete = nil
            }
        } message: {
            Text("Поступления, привязанные к ним, останутся, но потеряют связь с инвойсом.")
        }
    }

    private func duplicate(_ inv: Invoice) -> Invoice {
        var copy = store.newInvoice()
        copy.clientId = inv.clientId
        copy.amount = inv.amount
        copy.currency = inv.currency
        copy.description = inv.description
        let next = Dates.adding(months: 1, to: inv.serviceDate)
        copy.serviceDate = Dates.lastDay(ofMonth: Dates.month(next), year: Dates.year(next))
        copy.issueDate = copy.serviceDate
        copy.dueDate = Dates.adding(days: 15, to: copy.issueDate)
        copy.number = store.suggestedInvoiceNumber(for: copy.issueDate)
        return copy
    }
}

struct InvoiceEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Invoice
    let onSave: (Invoice) -> Void

    init(invoice: Invoice, onSave: @escaping (Invoice) -> Void) {
        _draft = State(initialValue: invoice)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Инвойс") {
                    TextField("Номер", text: $draft.number)
                    Picker("Клиент", selection: $draft.clientId) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.data.clients) { c in Text(c.name).tag(UUID?.some(c.id)) }
                    }
                    DayPicker(title: "Дата выставления", date: $draft.issueDate)
                    DayPicker(title: "Дата оказания услуги (datum prometa)", date: $draft.serviceDate)
                    OptionalDatePicker(title: "Срок оплаты", date: $draft.dueDate, defaultDate: Dates.adding(days: 15, to: draft.issueDate))
                }
                Section("Сумма") {
                    TextField("Описание услуги", text: $draft.description, axis: .vertical)
                    HStack {
                        DecimalField("Сумма", value: $draft.amount)
                        Picker("", selection: $draft.currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    RateRow(title: "Курс НБС на дату услуги", currency: draft.currency, date: draft.serviceDate, rate: $draft.rateAtService)
                    if let rsd = Accounting(data: store.data).invoiceRSD(draft) {
                        ValueRow(label: "Выручка в динарах", value: Money.rsd(rsd, fraction: 2), bold: true)
                    }
                }
                Section("Примечание и файлы") {
                    TextField("Заметка (не печатается)", text: $draft.notes, axis: .vertical)
                    AttachmentsEditor(ids: $draft.attachmentIds)
                }
                Section {
                    InfoBox(text: "Для иностранного клиента инвойс не проходит через SEF (система е-фактур нужна для сербских компаний). Номер должен идти по порядку без пропусков. Дата услуги обычно — последний день месяца, за который ты выставляешь счёт.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Сохранить PDF…") { InvoicePDF.export(draft, store: store) }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.number.isEmpty || draft.amount <= 0)
            }
            .padding()
        }
        .frame(width: 600, height: 720)
    }
}
