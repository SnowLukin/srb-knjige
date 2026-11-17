import SwiftUI
import KnjigeCore

struct ExpensesView: View {
    @EnvironmentObject var store: Store
    @State private var selection = Set<UUID>()
    @State private var editing: Expense?

    private var rows: [Expense] {
        store.data.expenses.filter { Dates.year($0.date) == store.year }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Расходы", subtitle: "Расходы бизнеса уменьшают прибыль. Личные траты сюда не вносить.") {
                Button {
                    var e = Expense()
                    e.date = Dates.noon(Date())
                    editing = e
                } label: { Label("Новый расход", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
            let acc = store.accounting
            Table(rows, selection: $selection) {
                TableColumn("Дата") { (e: Expense) in Text(Dates.display(e.date)) }.width(90)
                TableColumn("Описание") { (e: Expense) in Text(e.description) }
                TableColumn("Категория") { (e: Expense) in Text(e.category.title) }
                TableColumn("Сумма") { (e: Expense) in Text(Money.string(e.amount, e.currency)).monospacedDigit() }
                TableColumn("В динарах") { (e: Expense) in
                    Text(acc.expenseRSD(e).map { Money.rsd($0) } ?? "нет курса").monospacedDigit()
                }
                TableColumn("Учитывается") { (e: Expense) in
                    Image(systemName: e.deductible ? "checkmark" : "minus").foregroundStyle(e.deductible ? .green : .secondary)
                }
                .width(90)
                TableColumn("Файл") { (e: Expense) in
                    Image(systemName: e.attachmentIds.isEmpty ? "exclamationmark.triangle" : "paperclip")
                        .foregroundStyle(e.attachmentIds.isEmpty ? .orange : .secondary)
                        .help(e.attachmentIds.isEmpty ? "Нет подтверждающего документа" : "Документ прикреплён")
                }
                .width(50)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, ids.count == 1, let e = store.data.expenses.first(where: { $0.id == id }) {
                    Button("Изменить") { editing = e }
                }
                Button("Удалить", role: .destructive) { store.delete(ids, in: \.expenses) }
            } primaryAction: { ids in
                if let id = ids.first { editing = store.data.expenses.first { $0.id == id } }
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("Расходов нет", systemImage: "cart",
                                           description: Text("Бухгалтер, юрадрес, комиссии банка, софт, техника для работы."))
                }
            }
        }
        .sheet(item: $editing) { e in
            ExpenseEditor(expense: e) { store.upsert($0, in: \.expenses) }.environmentObject(store)
        }
    }
}

struct ExpenseEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Expense
    let onSave: (Expense) -> Void

    init(expense: Expense, onSave: @escaping (Expense) -> Void) {
        _draft = State(initialValue: expense)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Расход") {
                    DayPicker(title: "Дата", date: $draft.date)
                    TextField("Описание", text: $draft.description)
                    TextField("Поставщик", text: $draft.supplier)
                    Picker("Категория", selection: $draft.category) {
                        ForEach(ExpenseCategory.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        DecimalField("Сумма", value: $draft.amount)
                        Picker("", selection: $draft.currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    RateRow(title: "Курс НБС на дату", currency: draft.currency, date: draft.date, rate: $draft.rate)
                    Toggle("Расход бизнеса (уменьшает прибыль)", isOn: $draft.deductible)
                    if draft.category == .equipment {
                        InfoBox(text: "Техника дороже порога основного средства амортизируется несколько лет, а не списывается сразу. Приложение пока списывает её целиком — для дорогой покупки уточни у бухгалтера или в Pravilnik o amortizaciji.", tint: .orange)
                    }
                }
                Section("Документ") {
                    AttachmentsEditor(ids: $draft.attachmentIds)
                    Text("Расход признаётся только с документом: счёт (račun/faktura) на ИП с его ПИБ или чек.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 560, height: 620)
    }
}
