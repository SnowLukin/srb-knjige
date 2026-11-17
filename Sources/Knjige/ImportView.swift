import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import KnjigeCore

struct ImportView: View {
    @EnvironmentObject var store: Store
    @State private var selectedId: UUID?
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var processing: Set<UUID> = []

    private var attachments: [Attachment] {
        store.data.attachments.sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Импорт скринов и PDF",
                       subtitle: "Скрин выплаты из Deel, выписка банка, чек — приложение распознает текст и предложит заполнить операцию.") {
                Button { pasteFromClipboard() } label: { Label("Вставить из буфера", systemImage: "doc.on.clipboard") }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button { importing = true } label: { Label("Выбрать файлы…", systemImage: "folder") }
            }
            HStack(spacing: 0) {
                list.frame(width: 270)
                Divider()
                detail.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(importFile) }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            dropZone.padding(10)
            List(selection: $selectedId) {
                ForEach(attachments) { a in
                    HStack {
                        Image(systemName: a.storedFileName.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo")
                        VStack(alignment: .leading) {
                            Text(a.originalName).lineLimit(1)
                            Text(Dates.display(a.addedAt) + (store.unlinkedAttachments.contains(a) ? " · не привязан" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if processing.contains(a.id) { ProgressView().controlSize(.small) }
                    }
                    .tag(a.id)
                    .contextMenu {
                        Button("Открыть") { NSWorkspace.shared.open(store.url(for: a)) }
                        Button("Распознать заново") { recognize(a) }
                        Divider()
                        Button("Удалить файл", role: .destructive) {
                            if selectedId == a.id { selectedId = nil }
                            store.removeAttachment(a.id)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down.on.square").font(.largeTitle).foregroundStyle(.secondary)
            Text("Перетащи сюда скриншоты или PDF").font(.callout)
            Text("или ⇧⌘V — вставить скрин из буфера").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(importFile)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedId, let a = store.data.attachment(id) {
            AttachmentAnalysis(attachment: a, processing: processing.contains(id)) { recognize(a) }
                .id(id)
        } else {
            ContentUnavailableView("Выбери файл слева", systemImage: "doc.viewfinder",
                                   description: Text("Сделай скриншот (⌃⇧⌘4 копирует в буфер), затем ⇧⌘V здесь."))
        }
    }

    // MARK: Действия

    private func importFile(_ url: URL) {
        do {
            let a = try store.addAttachment(from: url)
            selectedId = a.id
            recognize(a)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach(importFile)
            return
        }
        guard let image = NSImage(pasteboard: pb) else {
            store.lastError = "В буфере нет картинки. Сделай скриншот сочетанием ⌃⇧⌘4 (с Control — в буфер)."
            return
        }
        do {
            let a = try store.addAttachment(image: image)
            selectedId = a.id
            recognize(a)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func recognize(_ a: Attachment) {
        processing.insert(a.id)
        let url = store.url(for: a)
        Task {
            defer { processing.remove(a.id) }
            do {
                let text = try await OCR.recognize(url: url)
                store.setRecognizedText(text, for: a.id)
            } catch {
                store.lastError = "Распознавание: \(error.localizedDescription)"
            }
        }
    }
}

/// Правая панель: превью, распознанный текст и создание операции.
struct AttachmentAnalysis: View {
    @EnvironmentObject var store: Store
    let attachment: Attachment
    let processing: Bool
    let onRetry: () -> Void

    @State private var amount: Decimal? = nil
    @State private var secondAmount: Decimal? = nil
    @State private var currency: Currency = .EUR
    @State private var date: Date = Dates.noon(Date())
    @State private var kind: DocumentKind = .unknown
    @State private var showText = false
    @State private var newReceipt: Receipt?
    @State private var newExpense: Expense?
    @State private var newConversion: Conversion?

    private var parsed: ParsedDocument? {
        attachment.recognizedText.map(OCRParser.parse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(attachment.originalName).font(.title3.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Button("Открыть") { NSWorkspace.shared.open(store.url(for: attachment)) }
                }
                Preview(url: store.url(for: attachment))
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if processing {
                    HStack { ProgressView(); Text("Распознаю текст…") }
                } else if let p = parsed {
                    analysis(p)
                } else {
                    HStack {
                        Text("Текст ещё не распознан.")
                        Button("Распознать", action: onRetry)
                    }
                }
            }
            .padding()
        }
        .onAppear(perform: prefill)
        .onChange(of: attachment.recognizedText) { _, _ in prefill() }
        .sheet(item: $newReceipt) { r in
            ReceiptEditor(receipt: r) { store.upsert($0, in: \.receipts) }.environmentObject(store)
        }
        .sheet(item: $newExpense) { e in
            ExpenseEditor(expense: e) { store.upsert($0, in: \.expenses) }.environmentObject(store)
        }
        .sheet(item: $newConversion) { c in
            ConversionEditor(conversion: c) { store.upsert($0, in: \.conversions) }.environmentObject(store)
        }
    }

    @ViewBuilder private func analysis(_ p: ParsedDocument) -> some View {
        Card(title: "Что нашлось") {
            Picker("Тип документа", selection: $kind) {
                ForEach(DocumentKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 360)

            if p.amounts.isEmpty {
                Text("Сумм не найдено — введи вручную.").foregroundStyle(.orange)
            } else {
                Text("Суммы (нажми, чтобы выбрать):").font(.caption).foregroundStyle(.secondary)
                FlowChips(items: amountChips(p))
            }
            if !p.dates.isEmpty {
                Text("Даты:").font(.caption).foregroundStyle(.secondary)
                FlowChips(items: dateChips(p))
            }
            if !p.ibans.isEmpty {
                Text("IBAN: " + p.ibans.joined(separator: ", ")).font(.caption.monospaced()).textSelection(.enabled)
            }
        }

        Card(title: "Создать операцию") {
            HStack {
                DecimalField("Сумма", value: $amount)
                Picker("", selection: $currency) {
                    ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 90)
                DayPicker(title: "Дата", date: $date)
            }
            HStack(spacing: 10) {
                Button { newReceipt = makeReceipt() } label: { Label("Поступление", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .deelPayment ? .accentColor : .gray)
                Button { newExpense = makeExpense() } label: { Label("Расход", systemImage: "cart") }
                Button { newConversion = makeConversion(p) } label: { Label("Конвертация", systemImage: "arrow.left.arrow.right") }
            }
            .disabled(amount == nil)
            Text("Откроется форма с заполненными полями и прикреплённым файлом — проверь и сохрани.")
                .font(.caption).foregroundStyle(.secondary)
        }

        DisclosureGroup("Распознанный текст", isExpanded: $showText) {
            Text(p.text.isEmpty ? "(пусто)" : p.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
        Button("Распознать заново", action: onRetry).buttonStyle(.link)
    }

    private func amountChips(_ p: ParsedDocument) -> [Chip] {
        p.amounts.map { a in
            let label = a.currency.map { Money.string(a.value, $0) } ?? Money.plain(a.value)
            return Chip(label: label) {
                amount = a.value
                if let c = a.currency { currency = c }
            }
        }
    }

    private func dateChips(_ p: ParsedDocument) -> [Chip] {
        p.dates.map { d in Chip(label: Dates.display(d)) { date = d } }
    }

    private func prefill() {
        guard let p = parsed else { return }
        kind = p.kind
        if let best = p.bestAmount {
            amount = best.value
            if let c = best.currency { currency = c }
        }
        if let d = p.bestDate { date = d }
    }

    private func makeReceipt() -> Receipt {
        var r = Receipt()
        r.date = date
        r.amount = amount ?? 0
        r.currency = currency
        r.source = kind == .deelPayment ? "Deel" : ""
        r.attachmentIds = [attachment.id]
        let acc = store.accounting
        if let inv = store.data.invoices.sorted(by: { $0.serviceDate < $1.serviceDate })
            .first(where: { !acc.status(of: $0).isPaid && $0.currency == currency }) {
            r.invoiceId = inv.id
        }
        return r
    }

    private func makeExpense() -> Expense {
        var e = Expense()
        e.date = date
        e.amount = amount ?? 0
        e.currency = currency
        e.attachmentIds = [attachment.id]
        e.description = attachment.originalName
        return e
    }

    private func makeConversion(_ p: ParsedDocument) -> Conversion {
        var c = Conversion()
        c.date = date
        c.currency = currency == .RSD ? .EUR : currency
        let foreign = p.amounts.filter { $0.currency == c.currency }.map(\.value)
        let rsd = p.amounts.filter { $0.currency == .RSD }.map(\.value)
        c.foreignAmount = currency == .RSD ? (foreign.max() ?? 0) : (amount ?? 0)
        c.rsdReceived = currency == .RSD ? (amount ?? 0) : (rsd.max() ?? 0)
        c.attachmentIds = [attachment.id]
        return c
    }
}

/// Кнопки-«чипсы», переносящиеся на новую строку.
struct Chip {
    let label: String
    let action: () -> Void
}

struct FlowChips: View {
    let items: [Chip]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(item.label, action: item.action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Превью картинки или первой страницы PDF.
struct Preview: View {
    let url: URL

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary)
        }
    }

    private func loadImage() -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 800, height: 1100), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }
}
