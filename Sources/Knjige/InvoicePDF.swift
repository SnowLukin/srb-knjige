import SwiftUI
import AppKit
import KnjigeCore

/// Печатная форма инвойса на двух языках (сербский / английский), A4.
struct InvoicePrintView: View {
    let invoice: Invoice
    let profile: BusinessProfile
    let client: Client?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.businessName.isEmpty ? profile.ownerName : profile.businessName)
                        .font(.system(size: 15, weight: .bold))
                    if !profile.address.isEmpty { Text("\(profile.address), \(profile.city), Srbija / Serbia") }
                    if !profile.pib.isEmpty { Text("PIB / Tax ID: \(profile.pib)") }
                    if !profile.maticniBroj.isEmpty { Text("MB / Reg. No: \(profile.maticniBroj)") }
                    if !profile.email.isEmpty { Text(profile.email) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("FAKTURA / INVOICE").font(.system(size: 20, weight: .bold))
                    Text("Broj / No: \(invoice.number)").font(.system(size: 12, weight: .semibold))
                }
            }

            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kupac / Bill to").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(client?.name ?? "").font(.system(size: 12, weight: .semibold))
                    if let c = client {
                        if !c.address.isEmpty { Text(c.address) }
                        if !c.country.isEmpty { Text(c.country) }
                        if !c.registrationNumber.isEmpty { Text("Reg./VAT No: \(c.registrationNumber)") }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    row("Datum izdavanja / Issue date", Dates.display(invoice.issueDate))
                    row("Datum prometa / Service date", Dates.display(invoice.serviceDate))
                    if let due = invoice.dueDate { row("Rok plaćanja / Due date", Dates.display(due)) }
                    row("Mesto izdavanja / Place of issue", profile.city)
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Opis / Description").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Iznos / Amount").frame(width: 140, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(8)
                .background(Color.gray.opacity(0.15))
                HStack(alignment: .top) {
                    Text(invoice.description).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Money.string(invoice.amount, invoice.currency)).frame(width: 140, alignment: .trailing)
                }
                .padding(8)
                Divider()
                HStack {
                    Text("Ukupno za plaćanje / Total due").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(Money.string(invoice.amount, invoice.currency)).fontWeight(.bold).frame(width: 140, alignment: .trailing)
                }
                .padding(8)
            }
            .overlay(Rectangle().stroke(Color.gray.opacity(0.4)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Instrukcije za plaćanje / Payment details").font(.system(size: 10, weight: .semibold))
                if !profile.bankName.isEmpty { Text("Banka / Bank: \(profile.bankName)") }
                if !profile.iban.isEmpty { Text("IBAN: \(profile.iban)") }
                if !profile.swift.isEmpty { Text("SWIFT/BIC: \(profile.swift)") }
                Text("Beneficiary: \(profile.businessName.isEmpty ? profile.ownerName : profile.businessName)")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Obveznik nije u sistemu PDV-a. / The supplier is not registered for VAT.")
                Text("Promet usluga inostranom licu. / Services supplied to a foreign entity.")
                Text("Faktura je punovažna bez pečata i potpisa. / This invoice is valid without stamp and signature.")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.black)
        .padding(40)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
    }
}

enum InvoicePDF {
    @MainActor
    static func render(_ invoice: Invoice, profile: BusinessProfile, client: Client?, to url: URL) -> Bool {
        let view = InvoicePrintView(invoice: invoice, profile: profile, client: client)
        let renderer = ImageRenderer(content: view)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            ok = true
        }
        return ok
    }

    @MainActor
    static func export(_ invoice: Invoice, store: Store) {
        let safeNumber = invoice.number.replacingOccurrences(of: "/", with: "-")
        guard let url = FileSaver.chooseSaveURL(suggestedName: "Invoice \(safeNumber).pdf", type: .pdf) else { return }
        if render(invoice, profile: store.data.profile, client: store.data.client(invoice.clientId), to: url) {
            NSWorkspace.shared.open(url)
        } else {
            store.lastError = "Не удалось создать PDF."
        }
    }
}
