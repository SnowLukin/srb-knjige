import SwiftUI
import KnjigeCore

struct TaxesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: TaxPayment?
    @State private var showDone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Налоги и сроки", subtitle: "Прогноз на год, календарь обязательств и учёт платежей.") {
                    Button {
                        var t = TaxPayment()
                        t.date = Dates.noon(Date())
                        t.periodYear = store.year
                        t.periodMonth = Dates.month(Date())
                        if let a = store.accounting.monthlyAdvance(year: store.year) { t.amountRSD = a }
                        editing = t
                    } label: { Label("Записать платёж", systemImage: "plus") }
                }
                HStack(alignment: .top, spacing: 16) {
                    forecast
                    advance
                }
                .padding(.horizontal)
                deadlines.padding(.horizontal)
                payments.padding(.horizontal)
            }
            .padding(.bottom)
        }
        .sheet(item: $editing) { t in
            TaxPaymentEditor(payment: t) { store.upsert($0, in: \.taxPayments) }.environmentObject(store)
        }
    }

    private var forecast: some View {
        let f = store.accounting.taxForecast(year: store.year)
        let s = f.summary
        let p = store.data.parameters(for: store.year)
        return Card(title: "Прогноз за \(String(store.year)) по внесённым данным") {
            VStack(spacing: 4) {
                ValueRow(label: "Доходы (выручка + курсовые доходы)", value: Money.rsd(s.totalIncome))
                ValueRow(label: "Расходы (зарплата, комиссии, курсовые, прочее)", value: Money.rsd(s.totalCosts))
                ValueRow(label: "Прибыль", value: Money.rsd(s.profit), bold: true)
                Divider()
                ValueRow(label: "Налог и взносы с зарплаты", value: Money.rsd(f.salaryToState))
                ValueRow(label: "Налог на прибыль \(Money.plain(p.profitTaxRate * 100)) %", value: Money.rsd(f.profitTax))
                ValueRow(label: "Уже заплачено авансов", value: Money.rsd(s.advancesPaidRSD))
                ValueRow(label: f.remainingProfitTax >= 0 ? "Доплата по году (до 15 апреля)" : "Переплата по году",
                         value: Money.rsd(abs(f.remainingProfitTax)))
                ValueRow(label: "Годовой налог на доход (до 15 мая след. года)", value: Money.rsd(f.annualIncomeTax.tax))
                Divider()
                ValueRow(label: "Всего налогов и взносов за год", value: Money.rsd(f.totalTaxes), bold: true)
                if s.totalIncome > 0 {
                    ValueRow(label: "Нагрузка от доходов", value: "\(Money.plain(f.totalTaxes / s.totalIncome * 100, maxFraction: 1)) %")
                }
            }
            .monospacedDigit()
            if s.missingRates > 0 {
                InfoBox(text: "У \(s.missingRates) операций нет курса НБС — они не учтены. Загрузить: меню «Данные» → «Загрузить недостающие курсы НБС».",
                        systemImage: "exclamationmark.triangle", tint: .orange)
            }
            DisclosureGroup("Как считается годовой налог на доход") {
                let a = f.annualIncomeTax
                VStack(spacing: 4) {
                    ValueRow(label: "Доход за год (нетто-зарплата + прибыль после налога)", value: Money.rsd(a.income))
                    ValueRow(label: "Порог (3 средние годовые зарплаты)", value: Money.rsd(a.threshold))
                    ValueRow(label: "Личный вычет (40 % средней зарплаты)", value: Money.rsd(a.personalDeduction))
                    ValueRow(label: "Облагаемая часть", value: Money.rsd(a.taxableIncome))
                    ValueRow(label: "10 %", value: Money.rsd(a.taxAt10))
                    ValueRow(label: "15 %", value: Money.rsd(a.taxAt15))
                }
                .monospacedDigit()
                .padding(.top, 4)
                Text("Упрощённая оценка без вычетов на иждивенцев. Платит физлицо, не ИП. Пороги объявляются в начале каждого года — обнови их в настройках.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var advance: some View {
        let acc = store.accounting
        let est = store.data.estimate(for: store.year)
        return Card(title: "Ежемесячный аванс налога на прибыль") {
            if let monthly = acc.monthlyAdvance(year: store.year), let est {
                Text(Money.rsd(monthly)).font(.title.weight(.semibold)).monospacedDigit()
                Text("в месяц, с \(Dates.monthName(est.firstMonth)) по декабрь. Платить до 15-го числа следующего месяца.")
                    .font(.callout).foregroundStyle(.secondary)
                ValueRow(label: "Прогноз выручки в PPDG-1S", value: Money.rsd(est.estimatedRevenueRSD))
                ValueRow(label: "Прогноз расходов", value: Money.rsd(est.estimatedExpensesRSD))
            } else {
                Text("Нет авансовой декларации на \(String(store.year)) год.").foregroundStyle(.secondary)
                Text("Аванс считается по прогнозу, который ты подаёшь в PPDG-1S. Внеси его в «Настройки» → «Авансовая декларация».")
                    .font(.callout)
            }
            InfoBox(text: "Сумма аванса приходит решением (rešenje) из налоговой по твоей декларации. Если решение отличается от расчёта — плати по решению и поправь прогноз здесь.")
        }
        .frame(maxWidth: 380)
    }

    private var deadlines: some View {
        let all = DeadlineCalendar.deadlines(for: store.year, data: store.data)
        let shown = showDone ? all : all.filter { !$0.done }
        return Card(title: "Календарь \(String(store.year))") {
            Toggle("Показывать выполненные", isOn: $showDone)
            if shown.isEmpty {
                Text(store.data.profile.registrationDate == nil
                     ? "Укажи дату регистрации ИП в настройках — календарь построится от неё."
                     : "Всё выполнено.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { d in
                DeadlineRow(deadline: d)
                Divider()
            }
            Text("Переносы с выходных учтены, государственные праздники — нет. Проверяй сроки в ePorezi.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var payments: some View {
        let list = store.data.taxPayments
            .filter { ($0.periodYear ?? Dates.year($0.date)) == store.year }
            .sorted { $0.date > $1.date }
        return Card(title: "Платежи в бюджет") {
            if list.isEmpty {
                Text("Платежей не записано.").foregroundStyle(.secondary)
            }
            ForEach(list) { t in
                HStack {
                    Text(Dates.display(t.date)).frame(width: 90, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(t.kind.title)
                        if let m = t.periodMonth { Text("за \(Dates.monthName(m))").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(Money.rsd(t.amountRSD, fraction: 2)).monospacedDigit()
                    Button("Изменить") { editing = t }.buttonStyle(.borderless)
                    Button(role: .destructive) { store.delete([t.id], in: \.taxPayments) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            Text("Налог и взносы с зарплаты учитываются через раздел «Зарплата» (по дате выплаты), здесь их можно записать для истории — в расчёт прибыли они второй раз не попадут.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeadlineRow: View {
    let deadline: Deadline

    var body: some View {
        let days = deadline.daysLeft()
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading) {
                Text(Dates.display(deadline.date)).fontWeight(.semibold).monospacedDigit()
                Text(deadline.done ? "готово" : daysText(days))
                    .font(.caption)
                    .foregroundStyle(statusColor(days))
            }
            .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(deadline.title).fontWeight(.medium)
                    if let form = deadline.form {
                        Text(form).font(.caption.monospaced()).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(deadline.details).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if deadline.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }

    private func statusColor(_ days: Int) -> Color {
        if deadline.done { return .green }
        if days < 0 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }

    private func daysText(_ d: Int) -> String {
        if d < 0 { return "просрочено на \(-d) дн." }
        if d == 0 { return "сегодня" }
        return "через \(d) дн."
    }
}

struct TaxPaymentEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaxPayment
    let onSave: (TaxPayment) -> Void

    init(payment: TaxPayment, onSave: @escaping (TaxPayment) -> Void) {
        _draft = State(initialValue: payment)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Вид", selection: $draft.kind) {
                    ForEach(TaxKind.allCases) { Text($0.title).tag($0) }
                }
                DayPicker(title: "Дата платежа", date: $draft.date)
                DecimalField("Сумма, RSD", value: $draft.amountRSD)
                Picker("За год", selection: Binding(get: { draft.periodYear ?? store.year }, set: { draft.periodYear = $0 })) {
                    ForEach((store.year - 2)...(store.year + 1), id: \.self) { Text(String($0)).tag($0) }
                }
                Picker("За месяц", selection: $draft.periodMonth) {
                    Text("—").tag(Int?.none)
                    ForEach(1...12, id: \.self) { Text(Dates.monthName($0)).tag(Int?.some($0)) }
                }
                TextField("Заметка", text: $draft.note)
                AttachmentsEditor(ids: $draft.attachmentIds)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.amountRSD <= 0)
            }
            .padding()
        }
        .frame(width: 520, height: 520)
    }
}
