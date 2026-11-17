import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KnjigeCore

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Настройки")
            TabView {
                ProfileSettings().tabItem { Text("Профиль ИП") }
                ClientsSettings().tabItem { Text("Клиенты") }
                EstimateSettings().tabItem { Text("Авансовая декларация") }
                ParametersSettings().tabItem { Text("Налоговые параметры") }
                AccountsSettings().tabItem { Text("План счетов") }
                DataSettings().tabItem { Text("Данные") }
            }
            .padding()
        }
    }
}

// MARK: - Профиль

struct ProfileSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section("Предузетник") {
                TextField("Имя и фамилия", text: $store.data.profile.ownerName)
                TextField("Полное название из APR", text: $store.data.profile.businessName, prompt: Text("Ivan Petrov PR Računarsko programiranje Beograd"))
                TextField("ПИБ", text: $store.data.profile.pib)
                TextField("Матични број (МБ)", text: $store.data.profile.maticniBroj)
                TextField("Код деятельности", text: $store.data.profile.activityCode)
                OptionalDatePicker(title: "Дата регистрации в APR", date: $store.data.profile.registrationDate)
            }
            Section("Адрес и контакты") {
                TextField("Адрес (улица, дом)", text: $store.data.profile.address)
                TextField("Город", text: $store.data.profile.city)
                TextField("Email для инвойсов", text: $store.data.profile.email)
            }
            Section("Банк (печатается в инвойсе)") {
                TextField("Банк", text: $store.data.profile.bankName)
                TextField("IBAN валютного счёта", text: $store.data.profile.iban)
                TextField("SWIFT / BIC", text: $store.data.profile.swift)
            }
            Section("Инвойсы") {
                TextField("Префикс номера", text: $store.data.profile.invoicePrefix, prompt: Text("например INV-"))
                Stepper("Следующий номер: \(store.data.profile.nextInvoiceNumber)",
                        value: $store.data.profile.nextInvoiceNumber, in: 1...100_000)
                Text("Номер будет вида «\(store.suggestedInvoiceNumber())». Нумерация идёт по порядку без пропусков.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ВНЖ") {
                OptionalDatePicker(title: "ВНЖ действует до", date: $store.data.profile.residencePermitExpiry)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Клиенты

struct ClientsSettings: View {
    @EnvironmentObject var store: Store
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(selection: $selection) {
                    ForEach(store.data.clients) { c in
                        Text(c.name.isEmpty ? "Без названия" : c.name).tag(c.id)
                    }
                }
                HStack {
                    Button {
                        var c = Client()
                        c.name = "Новый клиент"
                        store.data.clients.append(c)
                        selection = c.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection { store.delete([id], in: \.clients); selection = nil }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, maxWidth: 260)

            if let id = selection, let index = store.data.clients.firstIndex(where: { $0.id == id }) {
                Form {
                    TextField("Название", text: $store.data.clients[index].name)
                    TextField("Адрес", text: $store.data.clients[index].address, axis: .vertical)
                    TextField("Страна", text: $store.data.clients[index].country)
                    TextField("Рег. номер / VAT ID", text: $store.data.clients[index].registrationNumber)
                    TextField("Email", text: $store.data.clients[index].email)
                    Picker("Валюта по умолчанию", selection: $store.data.clients[index].defaultCurrency) {
                        ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Иностранный клиент", isOn: $store.data.clients[index].isForeign)
                    Text("Оборот с иностранными клиентами не входит в порог НДС 8 млн RSD. Если Deel — твой контрагент по договору, указывай его реквизиты; если договор напрямую с компанией — её.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .frame(minWidth: 380)
            } else {
                ContentUnavailableView("Выбери клиента", systemImage: "person.2")
                    .frame(minWidth: 380, maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Авансовая декларация

struct EstimateSettings: View {
    @EnvironmentObject var store: Store
    @State private var revenue: Decimal? = nil
    @State private var expenses: Decimal? = nil
    @State private var firstMonth = 1
    @State private var monthlyEUR: Decimal? = nil

    var body: some View {
        Form {
            Section("Прогноз на \(String(store.year)) год (PPDG-1S)") {
                HStack {
                    DecimalField("Помощник: доход в месяц, €", value: $monthlyEUR)
                    Button("Посчитать") { estimateFromMonthly() }
                }
                DecimalField("Ожидаемая выручка за год, RSD", value: $revenue)
                DecimalField("Ожидаемые расходы за год, RSD (включая зарплату бруто 2)", value: $expenses)
                Picker("Аванс платится с месяца", selection: $firstMonth) {
                    ForEach(1...12, id: \.self) { Text(Dates.monthName($0)).tag($0) }
                }
                if let r = revenue, let e = expenses {
                    let p = store.data.parameters(for: store.year)
                    let profit = max(r - e, 0)
                    let months = max(12 - firstMonth + 1, 1)
                    ValueRow(label: "Прибыль по прогнозу", value: Money.rsd(profit))
                    ValueRow(label: "Налог 10 % за год", value: Money.rsd((profit * p.profitTaxRate).roundedTo(0)))
                    ValueRow(label: "Аванс в месяц", value: Money.rsd((profit * p.profitTaxRate / Decimal(months)).roundedTo(0)), bold: true)
                }
                HStack {
                    Spacer()
                    Button("Сохранить прогноз") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(revenue == nil || expenses == nil)
                }
            }
            Section {
                InfoBox(text: "Авансовая PPDG-1S подаётся в течение 15 дней после регистрации, дальше — вместе с годовой декларацией до 15 апреля. Налоговая по ней выносит решение с суммой ежемесячного аванса. Прогноз можно менять в течение года, подав новую декларацию. Сильно занижать прогноз не стоит: разница доплачивается по итогам года.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: store.year) { _, _ in load() }
    }

    private func load() {
        if let est = store.data.estimate(for: store.year) {
            revenue = est.estimatedRevenueRSD
            expenses = est.estimatedExpensesRSD
            firstMonth = est.firstMonth
        } else {
            revenue = nil
            expenses = nil
            let reg = store.data.profile.registrationDate
            firstMonth = (reg.map(Dates.year) == store.year) ? Dates.month(reg!) : 1
        }
    }

    private func estimateFromMonthly() {
        guard let m = monthlyEUR else { return }
        let rate = store.data.rates.filter { $0.key.hasPrefix("EUR-") }.max { $0.key < $1.key }?.value ?? Decimal(string: "117.2")!
        let months = Decimal(12 - firstMonth + 1)
        revenue = (m * rate * months).roundedTo(0)
        let p = store.data.parameters(for: store.year)
        let salary = SalaryCalculator.breakdown(gross: p.minContributionBase, parameters: p).totalCost
        expenses = (salary * months).roundedTo(0)
    }

    private func save() {
        guard let r = revenue, let e = expenses else { return }
        store.data.estimates.removeAll { $0.year == store.year }
        store.data.estimates.append(AdvanceEstimate(year: store.year, estimatedRevenueRSD: r, estimatedExpensesRSD: e, firstMonth: firstMonth))
    }
}

// MARK: - Параметры

struct ParametersSettings: View {
    @EnvironmentObject var store: Store
    @State private var selectedYear: Int?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(selection: $selectedYear) {
                    ForEach(store.data.yearParameters.sorted { $0.year > $1.year }) { p in
                        Text(String(p.year)).tag(p.year)
                    }
                }
                Button("Добавить следующий год") {
                    if let last = store.data.yearParameters.max(by: { $0.year < $1.year }) {
                        store.data.yearParameters.append(last.copied(to: last.year + 1))
                        selectedYear = last.year + 1
                    }
                }
                .padding(6)
            }
            .frame(minWidth: 180, maxWidth: 220)

            if let y = selectedYear, let i = store.data.yearParameters.firstIndex(where: { $0.year == y }) {
                Form {
                    Section("Зарплата и взносы (в месяц)") {
                        DecimalField("Минимальная база взносов", value: $store.data.yearParameters[i].minContributionBase)
                        DecimalField("Максимальная база взносов", value: $store.data.yearParameters[i].maxContributionBase)
                        DecimalField("Необлагаемая часть зарплаты", value: $store.data.yearParameters[i].nonTaxableSalary)
                        DecimalField("ПИО работник (0,14 = 14 %)", value: $store.data.yearParameters[i].employeePension, kind: .rate)
                        DecimalField("Здоровье работник", value: $store.data.yearParameters[i].employeeHealth, kind: .rate)
                        DecimalField("Безработица работник", value: $store.data.yearParameters[i].employeeUnemployment, kind: .rate)
                        DecimalField("ПИО работодатель", value: $store.data.yearParameters[i].employerPension, kind: .rate)
                        DecimalField("Здоровье работодатель", value: $store.data.yearParameters[i].employerHealth, kind: .rate)
                        DecimalField("Налог на зарплату", value: $store.data.yearParameters[i].salaryTaxRate, kind: .rate)
                    }
                    Section("Прибыль и годовой налог") {
                        DecimalField("Налог на прибыль", value: $store.data.yearParameters[i].profitTaxRate, kind: .rate)
                        DecimalField("Средняя годовая зарплата", value: $store.data.yearParameters[i].averageAnnualSalary)
                        DecimalField("Порог НДС (сербский оборот)", value: $store.data.yearParameters[i].vatThreshold)
                        DecimalField("Лимит паушала (справочно)", value: $store.data.yearParameters[i].pausalLimit)
                    }
                    Section("Источник") {
                        TextField("Откуда цифры", text: $store.data.yearParameters[i].sourceNote, axis: .vertical)
                    }
                    Section {
                        InfoBox(text: "Каждый январь меняются минимальная и максимальная база, необлагаемая часть и средняя зарплата для годового налога. Свежие цифры публикуют biznis.rs, paragraf.rs и налоговая (purs.gov.rs).")
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 420)
            } else {
                ContentUnavailableView("Выбери год", systemImage: "calendar")
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
        .onAppear { selectedYear = selectedYear ?? store.data.yearParameters.map(\.year).max() }
    }
}

// MARK: - План счетов

struct AccountsSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading) {
            InfoBox(text: "Счета, на которые раскладываются проводки. Коды с «?» нужно сверить с актуальным контным планом для предпринимателей (Pravilnik o kontnom okviru) или спросить у бухгалтера один раз — дальше всё работает само.",
                    systemImage: "exclamationmark.triangle", tint: .orange)
            Table(AccountKey.allCases) {
                TableColumn("Код") { (key: AccountKey) in
                    TextField("", text: Binding(
                        get: { store.data.accounts[key]?.code ?? "" },
                        set: { store.data.accounts[key, default: LedgerAccount.defaults[key]!].code = $0 }))
                    .monospaced()
                }
                .width(70)
                TableColumn("Название (сербское)") { (key: AccountKey) in
                    TextField("", text: Binding(
                        get: { store.data.accounts[key]?.name ?? "" },
                        set: { store.data.accounts[key, default: LedgerAccount.defaults[key]!].name = $0 }))
                }
                TableColumn("Что это") { (key: AccountKey) in
                    Text(store.data.accounts[key]?.nameRu ?? "").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Вернуть коды по умолчанию") { store.data.accounts = LedgerAccount.defaults }
            }
        }
    }
}

// MARK: - Данные

struct DataSettings: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var confirmImport: URL?

    var body: some View {
        Form {
            Section("Хранение") {
                Text("Все данные лежат на этом Маке в папке:")
                Text(store.repository.baseURL.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("data.json — операции, files — загруженные скрины и PDF, backups — ежедневные резервные копии (30 последних).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Открыть в Finder") { NSWorkspace.shared.open(store.repository.baseURL) }
            }
            Section("Резервная копия") {
                Button("Экспортировать все данные в файл…") {
                    guard let url = FileSaver.chooseSaveURL(suggestedName: "knjige-backup-\(Dates.iso(Date())).json", type: .json) else { return }
                    do { try store.repository.exportBackup(store.data, to: url) } catch { store.lastError = error.localizedDescription }
                }
                Button("Восстановить из файла…") { importing = true }
                Text("Файлы вложений в экспорт не входят — для полного переноса скопируй всю папку данных.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Курсы НБС") {
                Text("В кэше курсов: \(store.data.rates.count)")
                Button("Очистить кэш курсов") { store.data.rates = [:] }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { confirmImport = url }
        }
        .confirmationDialog("Заменить текущие данные данными из файла?", isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } })) {
            Button("Заменить", role: .destructive) {
                if let url = confirmImport {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do { store.data = try store.repository.importBackup(from: url) } catch { store.lastError = error.localizedDescription }
                }
                confirmImport = nil
            }
        } message: {
            Text("Текущие данные будут заменены. Если сомневаешься, сначала сделай экспорт.")
        }
    }
}
