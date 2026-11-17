import SwiftUI
import KnjigeCore

struct SalaryView: View {
    @EnvironmentObject var store: Store
    @State private var editing: SalaryPayment?
    @State private var desiredNet: Decimal? = nil

    private var params: YearParameters { store.data.parameters(for: store.year) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Личная зарплата", subtitle: "Предузетник на книгах платит себе зарплату и взносы с неё каждый месяц.") {
                    Button("Заполнить пустые месяцы минимальной") { fillMinimum() }
                }
                if !store.data.hasExactParameters(for: store.year) {
                    InfoBox(text: "Нет налоговых параметров на \(String(store.year)) год — используются параметры \(String(params.year)). Обнови их в «Настройках».",
                            systemImage: "exclamationmark.triangle", tint: .orange)
                        .padding(.horizontal)
                }
                months.padding(.horizontal)
                HStack(alignment: .top, spacing: 16) {
                    calculator
                    explanation
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .sheet(item: $editing) { s in
            SalaryEditor(salary: s, parameters: store.data.parameters(for: s.year)) { store.setSalary($0) }
        }
    }

    private var months: some View {
        Card(title: "Месяцы \(String(store.year))") {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Месяц").gridColumnAlignment(.leading)
                    Text("Бруто")
                    Text("Нетто на руки")
                    Text("Взносы")
                    Text("Налог")
                    Text("Всего государству")
                    Text("Выплачено").gridColumnAlignment(.leading)
                    Text("")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(1...12, id: \.self) { m in
                    let s = store.salary(year: store.year, month: m)
                    let b = s.map { SalaryCalculator.breakdown(gross: $0.gross, parameters: params) }
                    GridRow {
                        Text(Dates.monthName(m).capitalized)
                        Text(b.map { Money.rsd($0.gross) } ?? "—")
                        Text(b.map { Money.rsd($0.net) } ?? "—")
                        Text(b.map { Money.rsd($0.employeeContributions + $0.employerContributions) } ?? "—")
                        Text(b.map { Money.rsd($0.salaryTax) } ?? "—")
                        Text(b.map { Money.rsd($0.totalToState) } ?? "—").fontWeight(.semibold)
                        Group {
                            if let paid = s?.paidDate {
                                Label(Dates.display(paid), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if s != nil {
                                Text("не выплачено").foregroundStyle(.orange)
                            } else {
                                Text("")
                            }
                        }
                        Button(s == nil ? "Добавить" : "Изменить") {
                            editing = s ?? SalaryPayment(year: store.year, month: m, gross: params.minContributionBase)
                        }
                        .buttonStyle(.borderless)
                    }
                    .monospacedDigit()
                }
                Divider()
                let all = store.data.salaries.filter { $0.year == store.year }
                    .map { SalaryCalculator.breakdown(gross: $0.gross, parameters: params) }
                GridRow {
                    Text("Итого").fontWeight(.semibold)
                    Text(Money.rsd(all.reduce(0) { $0 + $1.gross }))
                    Text(Money.rsd(all.reduce(0) { $0 + $1.net }))
                    Text(Money.rsd(all.reduce(0) { $0 + $1.employeeContributions + $1.employerContributions }))
                    Text(Money.rsd(all.reduce(0) { $0 + $1.salaryTax }))
                    Text(Money.rsd(all.reduce(0) { $0 + $1.totalToState })).fontWeight(.semibold)
                    Text("")
                    Text("")
                }
                .monospacedDigit()
            }
        }
    }

    private var calculator: some View {
        Card(title: "Калькулятор") {
            DecimalField("Хочу на руки в месяц, RSD", value: $desiredNet)
            if let net = desiredNet, net > 0 {
                let gross = SalaryCalculator.grossForNet(net, parameters: params)
                let b = SalaryCalculator.breakdown(gross: gross, parameters: params)
                breakdownView(b)
            } else {
                Text("Минимальная зарплата (бруто = минимальная база \(Money.rsd(params.minContributionBase))):")
                    .font(.caption).foregroundStyle(.secondary)
                breakdownView(SalaryCalculator.breakdown(gross: params.minContributionBase, parameters: params))
            }
        }
        .frame(maxWidth: 420)
    }

    private func breakdownView(_ b: SalaryBreakdown) -> some View {
        VStack(spacing: 4) {
            ValueRow(label: "Бруто 1", value: Money.rsd(b.gross, fraction: 2), bold: true)
            ValueRow(label: "База для взносов", value: Money.rsd(b.contributionBase, fraction: 2))
            ValueRow(label: "ПИО работник \(pct(params.employeePension))", value: Money.rsd(b.employeePension, fraction: 2))
            ValueRow(label: "Здоровье работник \(pct(params.employeeHealth))", value: Money.rsd(b.employeeHealth, fraction: 2))
            ValueRow(label: "Безработица \(pct(params.employeeUnemployment))", value: Money.rsd(b.employeeUnemployment, fraction: 2))
            ValueRow(label: "Налог \(pct(params.salaryTaxRate)) с (бруто − \(Money.rsd(params.nonTaxableSalary)))", value: Money.rsd(b.salaryTax, fraction: 2))
            ValueRow(label: "Нетто на личный счёт", value: Money.rsd(b.net, fraction: 2), bold: true)
            Divider()
            ValueRow(label: "ПИО работодатель \(pct(params.employerPension))", value: Money.rsd(b.employerPension, fraction: 2))
            ValueRow(label: "Здоровье работодатель \(pct(params.employerHealth))", value: Money.rsd(b.employerHealth, fraction: 2))
            ValueRow(label: "Всего государству", value: Money.rsd(b.totalToState, fraction: 2), bold: true)
            ValueRow(label: "Стоимость для ИП (бруто 2, расход)", value: Money.rsd(b.totalCost, fraction: 2))
        }
        .monospacedDigit()
    }

    private var explanation: some View {
        Card(title: "Как это работает") {
            Text("""
            • Каждый месяц ИП начисляет тебе зарплату. Минимум — взносы с минимальной базы, даже если ты ничего не выплатил.
            • В день выплаты подаёшь PPP-PD в ePorezi и в тот же день платишь налог и взносы. Нетто переводишь себе на личный счёт.
            • Если за месяц зарплату не выплатил, PPP-PD с минимальной базы нужно подать до конца следующего месяца.
            • Зарплата (бруто 2) — расход ИП: уменьшает прибыль и налог на прибыль 10 %.
            • Платить зарплату больше минимума обычно невыгодно: с неё ~35 % налогов и взносов, а прибыль облагается 10 %. Остаток прибыли можно забирать после налога.
            """)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            InfoBox(text: "Уведомление о выборе личной зарплаты подаётся в налоговую при регистрации (галочка в заявлении APR) или до 15 декабря на следующий год.")
        }
    }

    private func pct(_ d: Decimal) -> String {
        "\(Money.plain(d * 100, maxFraction: 2)) %"
    }

    private func fillMinimum() {
        let reg = store.data.profile.registrationDate
        let startMonth = (reg.map(Dates.year) == store.year) ? Dates.month(reg!) : 1
        let now = Date()
        let lastMonth = Dates.year(now) == store.year ? Dates.month(now) : 12
        guard startMonth <= lastMonth else { return }
        for m in startMonth...lastMonth where store.salary(year: store.year, month: m) == nil {
            store.setSalary(SalaryPayment(year: store.year, month: m, gross: params.minContributionBase))
        }
    }
}

struct SalaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SalaryPayment
    let parameters: YearParameters
    let onSave: (SalaryPayment) -> Void

    init(salary: SalaryPayment, parameters: YearParameters, onSave: @escaping (SalaryPayment) -> Void) {
        _draft = State(initialValue: salary)
        self.parameters = parameters
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Зарплата за \(Dates.monthName(draft.month)) \(String(draft.year))") {
                    DecimalField("Бруто 1, RSD", value: $draft.gross)
                    HStack {
                        Button("Минимальная") { draft.gross = parameters.minContributionBase }
                        Spacer()
                    }
                    OptionalDatePicker(title: "Выплачена", date: $draft.paidDate)
                    TextField("Заметка", text: $draft.note)
                }
                Section("Расчёт") {
                    let b = SalaryCalculator.breakdown(gross: draft.gross, parameters: parameters)
                    ValueRow(label: "Нетто на руки", value: Money.rsd(b.net, fraction: 2), bold: true)
                    ValueRow(label: "Взносы работника", value: Money.rsd(b.employeeContributions, fraction: 2))
                    ValueRow(label: "Взносы работодателя", value: Money.rsd(b.employerContributions, fraction: 2))
                    ValueRow(label: "Налог на зарплату", value: Money.rsd(b.salaryTax, fraction: 2))
                    ValueRow(label: "Всего заплатить государству", value: Money.rsd(b.totalToState, fraction: 2), bold: true)
                    if draft.gross < parameters.minContributionBase {
                        Text("Бруто ниже минимальной базы — взносы всё равно считаются с минимума.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { onSave(draft); dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 480)
    }
}
