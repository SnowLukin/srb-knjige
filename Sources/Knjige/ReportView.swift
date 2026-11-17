import SwiftUI
import AppKit
import KnjigeCore

struct ReportView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let text = AnnualReport.text(year: store.year, data: store.data)
        let s = store.accounting.summary(year: store.year)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Годовой отчёт \(String(store.year))", subtitle: "Итоги для годовой декларации PPDG-1S, налогового баланса и финансового отчёта в APR.") {
                Button("Скопировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Menu("Экспорт CSV") {
                    Button("Инвойсы") { FileSaver.save(text: CSVExport.invoices(store.data), suggestedName: "Инвойсы.csv") }
                    Button("Поступления") { FileSaver.save(text: CSVExport.receipts(store.data), suggestedName: "Поступления.csv") }
                    Button("Расходы") { FileSaver.save(text: CSVExport.expenses(store.data), suggestedName: "Расходы.csv") }
                }
                .fixedSize()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(title: "Выручка", value: Money.rsd(s.revenueRSD))
                        StatTile(title: "Расходы", value: Money.rsd(s.totalCosts))
                        StatTile(title: "Прибыль", value: Money.rsd(s.profit), tint: s.profit >= 0 ? .green : .red)
                    }
                    monthly(year: store.year)
                    Card(title: "Текстовая сводка") {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Card(title: "Что подать после конца года") {
                        Text("""
                        1. До 31 марта — финансовый отчёт (bilans stanja, bilans uspeha) в APR. Нужна квалифицированная электронная подпись. Цифры — из оборотно-сальдовой ведомости в «Журнале».
                        2. До 15 апреля — годовая PPDG-1S и налоговый баланс PB 2 в ePorezi. Доплатить разницу налога на прибыль.
                        3. До 15 мая — годовой налог на доход (PPDG-2R), если доход больше порога.
                        4. Новая авансовая декларация на следующий год обычно подаётся вместе с годовой — внеси прогноз в «Настройках».
                        """)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
        }
    }

    private func monthly(year: Int) -> some View {
        let acc = store.accounting
        return Card(title: "По месяцам") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Месяц").gridColumnAlignment(.leading)
                    Text("Выручка")
                    Text("Расходы")
                    Text("Прибыль нарастающим")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(1...12, id: \.self) { m in
                    let cumulative = acc.summary(year: year, throughMonth: m)
                    let previous = m > 1 ? acc.summary(year: year, throughMonth: m - 1) : YearSummary(year: year)
                    GridRow {
                        Text(Dates.monthName(m).capitalized)
                        Text(Money.rsd(cumulative.revenueRSD - previous.revenueRSD))
                        Text(Money.rsd(cumulative.totalCosts - previous.totalCosts))
                        Text(Money.rsd(cumulative.profit))
                    }
                    .monospacedDigit()
                }
            }
        }
    }
}
