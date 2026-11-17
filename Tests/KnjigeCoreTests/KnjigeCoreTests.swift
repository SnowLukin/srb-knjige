import XCTest
@testable import KnjigeCore

final class SalaryTests: XCTestCase {
    let p = YearParameters.y2026

    func testMinimumSalary2026() {
        let b = SalaryCalculator.breakdown(gross: 51_297, parameters: p)
        // Взносы работника 19,9 % и работодателя 15,15 % от 51 297.
        XCTAssertEqual(b.employeeContributions, Decimal(string: "10208.11")!)
        XCTAssertEqual(b.employerContributions, Decimal(string: "7771.50")!)
        // Налог 10 % × (51 297 − 34 221) = 1 707,60.
        XCTAssertEqual(b.salaryTax, Decimal(string: "1707.60")!)
        XCTAssertEqual(b.totalToState, Decimal(string: "19687.21")!)
        XCTAssertEqual(b.net, Decimal(string: "39381.29")!)
    }

    func testBaseIsClampedToMinimum() {
        let b = SalaryCalculator.breakdown(gross: 30_000, parameters: p)
        XCTAssertEqual(b.contributionBase, p.minContributionBase)
        XCTAssertEqual(b.salaryTax, 0)
    }

    func testGrossForNetRoundTrip() {
        let gross = SalaryCalculator.grossForNet(100_000, parameters: p)
        let net = SalaryCalculator.breakdown(gross: gross, parameters: p).net
        XCTAssertLessThan(abs((net - 100_000).doubleValue), 1)
    }
}

final class AnnualTaxTests: XCTestCase {
    func testBelowThresholdNoTax() {
        let e = AnnualIncomeTax.estimate(income: 5_000_000, parameters: .y2026)
        XCTAssertEqual(e.tax, 0)
    }

    func testAboveThreshold() {
        // Порог 5 439 096, вычет 725 212,80.
        let e = AnnualIncomeTax.estimate(income: 7_000_000, parameters: .y2026)
        XCTAssertEqual(e.threshold, 5_439_096)
        XCTAssertEqual(e.taxableIncome, Decimal(string: "835691.20")!)
        XCTAssertEqual(e.taxAt10, Decimal(string: "83569.12")!)
        XCTAssertEqual(e.taxAt15, 0)
    }
}

final class AccountingTests: XCTestCase {
    func testReceiptFXDifference() {
        var data = AppData()
        var client = Client()
        client.name = "Client"
        data.clients = [client]

        var inv = Invoice()
        inv.number = "1/2026"
        inv.clientId = client.id
        inv.amount = 5000
        inv.serviceDate = Dates.make(2026, 12, 31)
        inv.rateAtService = Decimal(string: "117.20")!
        data.invoices = [inv]

        var r = Receipt()
        r.date = Dates.make(2027, 1, 10)
        r.amount = 4980
        r.fee = 20
        r.invoiceId = inv.id
        r.rateAtReceipt = Decimal(string: "117.30")!
        data.receipts = [r]

        let fx = Accounting(data: data).receiptFX(r)
        XCTAssertEqual(fx.receivedRSD, Decimal(string: "584154.00")!)
        XCTAssertEqual(fx.feeRSD, Decimal(string: "2346.00")!)
        XCTAssertEqual(fx.clearedReceivableRSD, Decimal(string: "586000.00")!)
        XCTAssertEqual(fx.difference, Decimal(string: "500.00")!)
        XCTAssertTrue(Accounting(data: data).status(of: inv).isPaid)

        let entries = LedgerBuilder(data: data).entries(year: 2027)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isBalanced)
    }

    func testConversionLoss() {
        var c = Conversion()
        c.foreignAmount = 1000
        c.rsdReceived = 116_500
        c.nbsRate = Decimal(string: "117.2")!
        let fx = Accounting(data: AppData()).conversionFX(c)
        XCTAssertEqual(fx.difference, -700)
    }

    func testAllEntriesBalanced() {
        var data = AppData()
        var s = SalaryPayment(year: 2026, month: 12, gross: 51_297)
        s.paidDate = Dates.make(2026, 12, 30)
        data.salaries = [s]
        var e = Expense()
        e.amount = 12_000
        e.date = Dates.make(2026, 12, 5)
        data.expenses = [e]
        for entry in LedgerBuilder(data: data).entries(year: 2026) {
            XCTAssertTrue(entry.isBalanced, entry.description)
        }
    }
}

final class ParserTests: XCTestCase {
    func testAmountFormats() {
        XCTAssertEqual(OCRParser.normalizeAmount("5 100,50"), Decimal(string: "5100.50"))
        XCTAssertEqual(OCRParser.normalizeAmount("5,100.50"), Decimal(string: "5100.50"))
        XCTAssertEqual(OCRParser.normalizeAmount("5.100,50"), Decimal(string: "5100.50"))
        XCTAssertEqual(OCRParser.normalizeAmount("5100.5"), Decimal(string: "5100.5"))
        XCTAssertEqual(OCRParser.normalizeAmount("600.000"), Decimal(600_000))
        XCTAssertEqual(OCRParser.normalizeAmount("1,234,567.89"), Decimal(string: "1234567.89"))
    }

    func testRateParsing() {
        XCTAssertEqual(Money.parseRate("117,1734"), Decimal(string: "117.1734"))
        XCTAssertEqual(Money.parseRate("117.1734"), Decimal(string: "117.1734"))
    }

    func testDeelLikeScreenshot() {
        let text = """
        Deel
        Withdrawal completed
        Amount   €5,080.00
        Fee   €20.00
        Date   Dec 30, 2026
        """
        let doc = OCRParser.parse(text)
        XCTAssertEqual(doc.kind, .deelPayment)
        XCTAssertEqual(doc.bestAmount?.value, Decimal(string: "5080.00"))
        XCTAssertEqual(doc.bestAmount?.currency, .EUR)
        XCTAssertEqual(doc.bestDate.map(Dates.iso), "2026-12-30")
    }

    func testSerbianStatement() {
        let text = """
        IZVOD BR. 12
        Datum: 15.01.2027.
        Priliv   597.210,45 RSD
        """
        let doc = OCRParser.parse(text)
        XCTAssertEqual(doc.kind, .bankStatement)
        XCTAssertEqual(doc.bestAmount?.value, Decimal(string: "597210.45"))
        XCTAssertEqual(doc.bestAmount?.currency, .RSD)
        XCTAssertEqual(doc.bestDate.map(Dates.iso), "2027-01-15")
    }

    func testRateResponse() throws {
        let json = #"{"code":"EUR","date":"2026-11-17","exchange_middle":117.1734}"#.data(using: .utf8)!
        XCTAssertEqual(try ExchangeRateService.parseMiddleRate(json), Decimal(string: "117.1734"))
    }
}

final class DeadlineTests: XCTestCase {
    func testWeekendShift() {
        // 15.11.2026 — воскресенье, срок переносится на понедельник 16.11.
        let d = Dates.nextWorkingDay(Dates.make(2026, 11, 15))
        XCTAssertEqual(Dates.iso(d), "2026-11-16")
    }

    func testFirstYearCalendar() {
        var data = AppData()
        data.profile.registrationDate = Dates.make(2026, 12, 8)
        let list = DeadlineCalendar.deadlines(for: 2026, data: data)
        XCTAssertTrue(list.contains { $0.id == "ppdg1s-start-2026" })
        XCTAssertTrue(list.contains { $0.id == "salary-2026-12" })
        XCTAssertFalse(list.contains { $0.id == "salary-2026-11" })
    }
}
