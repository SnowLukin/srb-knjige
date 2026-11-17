import SwiftUI
import KnjigeCore

struct JournalView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0

    var body: some View {
        let builder = LedgerBuilder(data: store.data)
        let entries = builder.entries(year: store.year)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Журнал проводок", subtitle: "Двойная запись строится автоматически из операций. Это и есть «книги».") {
                Button("Экспорт CSV…") {
                    FileSaver.save(text: CSVExport.journal(entries, accounts: store.data.accounts),
                                   suggestedName: "Журнал \(store.year).csv")
                }
            }
            Picker("", selection: $tab) {
                Text("Проводки").tag(0)
                Text("Оборотно-сальдовая ведомость").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.horizontal)
            .padding(.bottom, 8)

            InfoBox(text: "Коды счетов взяты из сербского контного плана для предпринимателей, но часть из них нужно сверить (они помечены «?» в настройках). Проводки — помощь для понимания и для бухгалтера; официальный финансовый отчёт заполняется в APR.",
                    systemImage: "exclamationmark.triangle", tint: .orange)
                .padding(.horizontal)

            if tab == 0 {
                List {
                    ForEach(entries) { e in
                        EntryRow(entry: e, accounts: store.data.accounts)
                    }
                }
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView("Проводок за \(String(store.year)) нет", systemImage: "books.vertical")
                    }
                }
            } else {
                TrialBalanceView(rows: builder.trialBalance(year: store.year), accounts: store.data.accounts)
            }
        }
    }
}

struct EntryRow: View {
    let entry: JournalEntry
    let accounts: [AccountKey: LedgerAccount]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Dates.display(entry.date)).monospacedDigit().fontWeight(.semibold)
                Text(entry.description)
                Spacer()
                if !entry.isBalanced {
                    Label("Не сходится", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            ForEach(entry.lines) { l in
                let acc = accounts[l.account] ?? LedgerAccount.defaults[l.account]
                HStack {
                    Text(acc?.code ?? "?").monospaced().frame(width: 50, alignment: .leading)
                    Text(acc?.nameRu ?? l.account.rawValue).foregroundStyle(.secondary)
                    Spacer()
                    Text(l.debit == 0 ? "" : Money.rsd(l.debit, fraction: 2)).frame(width: 150, alignment: .trailing)
                    Text(l.credit == 0 ? "" : Money.rsd(l.credit, fraction: 2)).frame(width: 150, alignment: .trailing)
                }
                .font(.callout)
                .monospacedDigit()
                .padding(.leading, l.credit != 0 ? 24 : 0)
            }
            if let w = entry.warning {
                Text(w).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrialBalanceView: View {
    let rows: [(key: AccountKey, debit: Decimal, credit: Decimal)]
    let accounts: [AccountKey: LedgerAccount]

    var body: some View {
        ScrollView {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Счёт").gridColumnAlignment(.leading)
                    Text("Название").gridColumnAlignment(.leading)
                    Text("Дебет")
                    Text("Кредит")
                    Text("Сальдо")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(rows, id: \.key) { r in
                    let acc = accounts[r.key] ?? LedgerAccount.defaults[r.key]
                    GridRow {
                        Text(acc?.code ?? "?").monospaced()
                        Text(acc?.nameRu ?? r.key.rawValue)
                        Text(Money.rsd(r.debit, fraction: 2))
                        Text(Money.rsd(r.credit, fraction: 2))
                        Text(Money.rsd(r.debit - r.credit, fraction: 2)).fontWeight(.semibold)
                    }
                    .monospacedDigit()
                }
                Divider()
                let totalD = rows.reduce(Decimal(0)) { $0 + $1.debit }
                let totalC = rows.reduce(Decimal(0)) { $0 + $1.credit }
                GridRow {
                    Text("")
                    Text("Итого").fontWeight(.semibold)
                    Text(Money.rsd(totalD, fraction: 2))
                    Text(Money.rsd(totalC, fraction: 2))
                    Text((totalD - totalC).roundedTo(2) == 0 ? "сходится ✓" : "не сходится!")
                        .foregroundStyle((totalD - totalC).roundedTo(2) == 0 ? .green : .red)
                }
                .monospacedDigit()
            }
            .padding()
        }
    }
}
