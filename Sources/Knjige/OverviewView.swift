import SwiftUI
import KnjigeCore

struct OverviewView: View {
    @EnvironmentObject var store: Store
    @Binding var selection: AppSection?
    @State private var loadingRates = false
    @State private var ratesMessage: String?

    var body: some View {
        let acc = store.accounting
        let forecast = acc.taxForecast(year: store.year)
        let s = forecast.summary
        let p = store.data.parameters(for: store.year)
        let otherCosts: Decimal = s.expensesRSD + s.feesRSD + s.fxLossesRSD
        let remaining: Decimal = s.totalIncome - otherCosts - forecast.totalTaxes
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: store.data.profile.businessName.isEmpty ? "Обзор" : store.data.profile.businessName,
                           subtitle: "Итоги \(String(store.year)) года по внесённым данным") {
                    Button {
                        Task {
                            loadingRates = true
                            let r = await store.fetchMissingRates()
                            loadingRates = false
                            ratesMessage = r.loaded + r.failed == 0 ? "Все курсы на месте." :
                                "Загружено курсов: \(r.loaded)" + (r.failed > 0 ? ", не удалось: \(r.failed)" : "")
                        }
                    } label: {
                        if loadingRates { ProgressView().controlSize(.small) } else { Label("Подтянуть курсы НБС", systemImage: "arrow.clockwise") }
                    }
                }
                if let ratesMessage {
                    Text(ratesMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }

                warnings(s: s, p: p).padding(.horizontal)

                HStack(spacing: 12) {
                    StatTile(title: "Выручка", value: Money.rsd(s.revenueRSD),
                             subtitle: euro(s.revenueRSD))
                    StatTile(title: "Прибыль", value: Money.rsd(s.profit), tint: s.profit >= 0 ? .primary : .red)
                    StatTile(title: "Налоги и взносы за год", value: Money.rsd(forecast.totalTaxes),
                             subtitle: s.totalIncome > 0 ? "\(Money.plain(forecast.totalTaxes / s.totalIncome * 100, maxFraction: 1)) % от доходов" : nil,
                             tint: .orange)
                    StatTile(title: "Остаётся тебе", value: Money.rsd(remaining),
                             subtitle: "после всех налогов и расходов", tint: .green)
                }
                .padding(.horizontal)

                HStack(alignment: .top, spacing: 16) {
                    upcoming
                    VStack(spacing: 16) {
                        unpaidInvoices(acc)
                        residence(acc)
                    }
                    .frame(maxWidth: 380)
                }
                .padding(.horizontal)

                if store.data.invoices.isEmpty {
                    firstSteps.padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
    }

    private func euro(_ rsd: Decimal) -> String? {
        guard let rate = store.cachedRate(.EUR, Dates.noon(Date())) ?? store.data.rates.filter({ $0.key.hasPrefix("EUR-") }).max(by: { $0.key < $1.key })?.value,
              rate > 0 else { return nil }
        return "≈ " + Money.string((rsd / rate).roundedTo(0), .EUR, fraction: 0)
    }

    @ViewBuilder private func warnings(s: YearSummary, p: YearParameters) -> some View {
        let profile = store.data.profile
        if profile.pib.isEmpty || profile.iban.isEmpty {
            InfoBox(text: "Заполни профиль ИП (ПИБ, IBAN) в «Настройках» — они печатаются в инвойсах.", systemImage: "person.crop.circle.badge.exclamationmark", tint: .orange)
        }
        if s.missingRates > 0 {
            InfoBox(text: "У \(s.missingRates) операций нет курса НБС — итоги неполные. Нажми «Подтянуть курсы НБС».", systemImage: "exclamationmark.triangle", tint: .orange)
        }
        if !store.data.hasExactParameters(for: store.year) {
            InfoBox(text: "Нет налоговых параметров на \(String(store.year)) — используются \(String(p.year)). Добавь новый год в «Настройках».", systemImage: "calendar.badge.exclamationmark", tint: .orange)
        }
        let domestic = store.accounting.domesticTurnoverLast365()
        if domestic > p.vatThreshold * Decimal(string: "0.8")! {
            InfoBox(text: "Оборот с сербскими клиентами за 12 месяцев — \(Money.rsd(domestic)). Порог НДС \(Money.rsd(p.vatThreshold)): при превышении обязательна регистрация в системе НДС.", systemImage: "exclamationmark.octagon", tint: .red)
        }
    }

    private var upcoming: some View {
        let list = DeadlineCalendar.upcoming(data: store.data, limit: 6)
        return Card(title: "Ближайшие сроки") {
            if list.isEmpty {
                Text(store.data.profile.registrationDate == nil ? "Укажи дату регистрации ИП в настройках." : "Ближайших сроков нет.")
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { d in
                DeadlineRow(deadline: d)
                Divider()
            }
            Button("Все сроки →") { selection = .taxes }.buttonStyle(.link)
        }
    }

    private func unpaidInvoices(_ acc: Accounting) -> some View {
        let unpaid = store.data.invoices.filter { !acc.status(of: $0).isPaid }.sorted { $0.serviceDate < $1.serviceDate }
        return Card(title: "Неоплаченные инвойсы") {
            if unpaid.isEmpty {
                Text("Все оплачены.").foregroundStyle(.secondary)
            }
            ForEach(unpaid) { inv in
                HStack {
                    Text(inv.number)
                    Text(Dates.display(inv.serviceDate)).foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.string(acc.status(of: inv).outstanding, inv.currency)).monospacedDigit()
                }
            }
        }
    }

    private func residence(_ acc: Accounting) -> some View {
        Card(title: "Для продления ВНЖ") {
            ValueRow(label: "Поступления за 6 месяцев", value: Money.rsd(acc.receiptsLast6Months()))
            if let exp = store.data.profile.residencePermitExpiry {
                let days = Dates.calendar.dateComponents([.day], from: Date(), to: exp).day ?? 0
                ValueRow(label: "ВНЖ действует до", value: Dates.display(exp))
                Text(days > 90 ? "Подавать на продление можно с \(Dates.display(Dates.adding(months: -3, to: exp)))."
                     : "Пора подавать на продление!")
                    .font(.caption).foregroundStyle(days > 90 ? Color.secondary : Color.red)
            } else {
                Text("Укажи дату окончания ВНЖ в настройках — напомню о продлении.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var firstSteps: some View {
        Card(title: "С чего начать") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. «Настройки» → профиль ИП: название из APR, ПИБ, МБ, адрес, банк, IBAN, дата регистрации.")
                Text("2. «Настройки» → клиенты: добавь того, кому выставляешь счёт.")
                Text("3. «Настройки» → авансовая декларация: прогноз выручки и расходов на год (тот же, что подаёшь в PPDG-1S).")
                Text("4. Каждый месяц: инвойс → поступление (скрин из Deel в «Импорт») → зарплата → аванс налога.")
                Text("5. Подробности — в разделе «Как это работает».")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Открыть настройки") { selection = .settings }
                Button("Как это работает") { selection = .help }
            }
        }
    }
}
