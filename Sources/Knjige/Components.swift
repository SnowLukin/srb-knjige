import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KnjigeCore

// MARK: - Ввод чисел

enum NumberKind { case money, rate }

/// Поле для суммы или курса. Понимает «5 100,50», «5100.50», «5.100,50».
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal?
    var kind: NumberKind = .money
    @State private var text: String = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Decimal?>, kind: NumberKind = .money) {
        self.title = title
        self._value = value
        self.kind = kind
    }

    init(_ title: String, value: Binding<Decimal>, kind: NumberKind = .money) {
        self.title = title
        self._value = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 })
        self.kind = kind
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(kind == .rate ? "117,1734" : "0,00"))
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: text) { _, new in
                let trimmed = new.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { value = nil; return }
                if let parsed = parse(trimmed) { value = parsed }
            }
            .onChange(of: value) { _, new in
                if !focused { text = format(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = format(value) }
            }
    }

    private func parse(_ s: String) -> Decimal? {
        kind == .rate ? Money.parseRate(s) : Money.parse(s)
    }

    private func format(_ v: Decimal?) -> String {
        guard let v else { return "" }
        return Money.plain(v, maxFraction: kind == .rate ? 6 : 2)
    }
}

/// Дата, которой может не быть.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    var defaultDate: Date = Date()

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? Dates.noon(defaultDate)) : nil }))
            if date != nil {
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = Dates.noon($0) }),
                           displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

/// DatePicker, который всегда сохраняет полдень дня (чтобы курс брался на правильную дату).
struct DayPicker: View {
    let title: String
    @Binding var date: Date
    var body: some View {
        DatePicker(title, selection: Binding(get: { date }, set: { date = Dates.noon($0) }), displayedComponents: .date)
    }
}

// MARK: - Курс НБС

struct RateRow: View {
    @EnvironmentObject var store: Store
    let title: String
    let currency: Currency
    let date: Date
    @Binding var rate: Decimal?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        if currency != .RSD {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    DecimalField(title, value: $rate, kind: .rate)
                    Button {
                        Task { await load() }
                    } label: {
                        if loading { ProgressView().controlSize(.small) } else { Text("Загрузить с НБС") }
                    }
                    .disabled(loading)
                }
                if rate == nil, let cached = store.cachedRate(currency, date) {
                    Text("Будет взят курс из кэша: \(Money.plain(cached, maxFraction: 4)) RSD за 1 \(currency.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                } else if rate == nil {
                    Text("Курса нет — нажми «Загрузить» или введи вручную со страницы nbs.rs (srednji kurs).")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do { rate = try await store.fetchRate(currency, date) } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Вложения

struct AttachmentsEditor: View {
    @EnvironmentObject var store: Store
    @Binding var ids: [UUID]
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ids, id: \.self) { id in
                if let a = store.data.attachment(id) {
                    HStack {
                        Image(systemName: icon(for: a))
                        Button(a.originalName) { NSWorkspace.shared.open(store.url(for: a)) }
                            .buttonStyle(.link)
                        Spacer()
                        Button(role: .destructive) { ids.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless)
                            .help("Отвязать файл (сам файл останется в «Импорте»)")
                    }
                }
            }
            HStack {
                Button("Прикрепить файл…") { importing = true }
                Menu("Из импорта") {
                    let free = store.unlinkedAttachments
                    if free.isEmpty { Text("Нет непривязанных файлов") }
                    ForEach(free) { a in Button(a.originalName) { ids.append(a.id) } }
                }
                .fixedSize()
                Text("или перетащи сюда").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func add(_ urls: [URL]) {
        for url in urls {
            do { ids.append(try store.addAttachment(from: url).id) } catch { store.lastError = error.localizedDescription }
        }
    }

    private func icon(for a: Attachment) -> String {
        a.storedFileName.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo"
    }
}

// MARK: - Карточки

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct InfoBox: View {
    let text: String
    var systemImage = "info.circle"
    var tint: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.08)))
    }
}

/// Строка «название — значение» для расшифровок.
struct ValueRow: View {
    let label: String
    let value: String
    var bold = false
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .fontWeight(bold ? .semibold : .regular)
    }
}

/// Заголовок раздела с кнопками справа.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.weight(.bold))
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
        }
        .padding([.horizontal, .top])
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

// MARK: - Сохранение файлов

enum FileSaver {
    @MainActor
    static func save(text: String, suggestedName: String, type: UTType = .commaSeparatedText) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // BOM, чтобы Excel правильно открыл кириллицу.
            let content = type == .commaSeparatedText ? "\u{FEFF}" + text : text
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    static func chooseSaveURL(suggestedName: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
