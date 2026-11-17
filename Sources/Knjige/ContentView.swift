import SwiftUI
import KnjigeCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, invoices, receipts, conversions, expenses, salary, taxes, journal, importFiles, report, settings, help
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Обзор"
        case .invoices: return "Инвойсы"
        case .receipts: return "Поступления"
        case .conversions: return "Конвертации"
        case .expenses: return "Расходы"
        case .salary: return "Зарплата"
        case .taxes: return "Налоги и сроки"
        case .journal: return "Журнал (книги)"
        case .importFiles: return "Импорт скринов и PDF"
        case .report: return "Годовой отчёт"
        case .settings: return "Настройки"
        case .help: return "Как это работает"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .invoices: return "doc.text"
        case .receipts: return "arrow.down.circle"
        case .conversions: return "arrow.left.arrow.right.circle"
        case .expenses: return "cart"
        case .salary: return "person.crop.circle.badge.checkmark"
        case .taxes: return "calendar.badge.exclamationmark"
        case .journal: return "books.vertical"
        case .importFiles: return "doc.viewfinder"
        case .report: return "chart.bar.doc.horizontal"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                row(.overview)
                Section("Операции") {
                    row(.invoices)
                    row(.receipts)
                    row(.conversions)
                    row(.expenses)
                }
                Section("Обязательства") {
                    row(.salary)
                    row(.taxes)
                }
                Section("Учёт") {
                    row(.journal)
                    row(.report)
                    row(.importFiles)
                }
                Section {
                    row(.settings)
                    row(.help)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Picker("Год", selection: $store.year) {
                            ForEach(store.availableYears, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .frame(width: 110)
                    }
                }
        }
        .alert("Ошибка", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onAppear {
            if store.data.profile.businessName.isEmpty { selection = .settings }
        }
    }

    private func row(_ s: AppSection) -> some View {
        NavigationLink(value: s) {
            Label(s.title, systemImage: s.icon)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewView(selection: $selection)
        case .invoices: InvoicesView()
        case .receipts: ReceiptsView()
        case .conversions: ConversionsView()
        case .expenses: ExpensesView()
        case .salary: SalaryView()
        case .taxes: TaxesView()
        case .journal: JournalView()
        case .importFiles: ImportView()
        case .report: ReportView()
        case .settings: SettingsView()
        case .help: HelpView()
        }
    }
}
