import Foundation

/// Налоговые параметры на год. Все значения можно поправить в настройках приложения.
/// Каждый январь Сербия меняет минимальную базу взносов, необлагаемый минимум и пороги —
/// при наступлении нового года добавь параметры на него.
public struct YearParameters: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { year }
    public var year: Int

    /// Минимальная месячная база для взносов (najniža osnovica).
    public var minContributionBase: Decimal
    /// Максимальная месячная база для взносов (najviša osnovica).
    public var maxContributionBase: Decimal
    /// Необлагаемая часть зарплаты (neoporezivi iznos).
    public var nonTaxableSalary: Decimal

    // Взносы за счёт работника
    public var employeePension: Decimal      // PIO
    public var employeeHealth: Decimal       // zdravstvo
    public var employeeUnemployment: Decimal // nezaposlenost
    // Взносы за счёт работодателя
    public var employerPension: Decimal
    public var employerHealth: Decimal

    /// Налог на зарплату.
    public var salaryTaxRate: Decimal
    /// Налог на прибыль предузетника (porez na prihod od samostalne delatnosti).
    public var profitTaxRate: Decimal

    /// Средняя годовая зарплата, от которой считается годовой налог на доход.
    /// Порог = 3 × эта сумма; личный вычет = 40 % от неё.
    public var averageAnnualSalary: Decimal

    /// Порог НДС по внутреннему (сербскому) обороту за 12 месяцев.
    public var vatThreshold: Decimal
    /// Лимит паушала — для справки.
    public var pausalLimit: Decimal

    /// Откуда взяты цифры — показывается в настройках.
    public var sourceNote: String

    public var employeeContributionRate: Decimal { employeePension + employeeHealth + employeeUnemployment }
    public var employerContributionRate: Decimal { employerPension + employerHealth }

    public static let y2026 = YearParameters(
        year: 2026,
        minContributionBase: 51_297,
        maxContributionBase: 732_820,
        nonTaxableSalary: 34_221,
        employeePension: Decimal(string: "0.14")!,
        employeeHealth: Decimal(string: "0.0515")!,
        employeeUnemployment: Decimal(string: "0.0075")!,
        employerPension: Decimal(string: "0.10")!,
        employerHealth: Decimal(string: "0.0515")!,
        salaryTaxRate: Decimal(string: "0.10")!,
        profitTaxRate: Decimal(string: "0.10")!,
        averageAnnualSalary: 1_813_032,
        vatThreshold: 8_000_000,
        pausalLimit: 6_000_000,
        sourceNote: "Минимальная/максимальная база 51 297 / 732 820 RSD и необлагаемый минимум 34 221 RSD — biznis.rs, zuniclaw.com (2026). Средняя годовая зарплата — по порогу 6× = 10 878 192 RSD за 2025 год (biznis.rs). Ставки взносов — стандартные сербские; сверь с бухгалтером."
    )

    public static let defaults: [YearParameters] = [y2026]

    /// Копия параметров на следующий год — стартовая точка, которую нужно обновить вручную.
    public func copied(to newYear: Int) -> YearParameters {
        var copy = self
        copy.year = newYear
        copy.sourceNote = "Скопировано с \(year) года — обнови цифры на \(newYear) год!"
        return copy
    }
}

// MARK: - Расчёт личной зарплаты

public struct SalaryBreakdown: Equatable, Sendable {
    public var gross: Decimal
    /// База для взносов (не ниже минимальной и не выше максимальной).
    public var contributionBase: Decimal
    public var employeePension: Decimal
    public var employeeHealth: Decimal
    public var employeeUnemployment: Decimal
    public var employerPension: Decimal
    public var employerHealth: Decimal
    public var salaryTax: Decimal
    /// Нетто — уходит на твой личный счёт.
    public var net: Decimal

    public var employeeContributions: Decimal { employeePension + employeeHealth + employeeUnemployment }
    public var employerContributions: Decimal { employerPension + employerHealth }
    /// Всё, что уходит государству: налог + все взносы.
    public var totalToState: Decimal { salaryTax + employeeContributions + employerContributions }
    /// Бруто 2 — полная стоимость зарплаты для ИП (это расход, уменьшающий прибыль).
    public var totalCost: Decimal { gross + employerContributions }

    public var pensionTotal: Decimal { employeePension + employerPension }
    public var healthTotal: Decimal { employeeHealth + employerHealth }
}

public enum SalaryCalculator {
    public static func breakdown(gross: Decimal, parameters p: YearParameters) -> SalaryBreakdown {
        let base = min(max(gross, p.minContributionBase), p.maxContributionBase)
        let ePension = (base * p.employeePension).roundedTo(2)
        let eHealth = (base * p.employeeHealth).roundedTo(2)
        let eUnemployment = (base * p.employeeUnemployment).roundedTo(2)
        let rPension = (base * p.employerPension).roundedTo(2)
        let rHealth = (base * p.employerHealth).roundedTo(2)
        let taxable = max(gross - p.nonTaxableSalary, 0)
        let tax = (taxable * p.salaryTaxRate).roundedTo(2)
        let net = gross - ePension - eHealth - eUnemployment - tax
        return SalaryBreakdown(
            gross: gross,
            contributionBase: base,
            employeePension: ePension,
            employeeHealth: eHealth,
            employeeUnemployment: eUnemployment,
            employerPension: rPension,
            employerHealth: rHealth,
            salaryTax: tax,
            net: net
        )
    }

    /// Бруто, при котором нетто равно заданной сумме (если база взносов не упирается в минимум/максимум).
    public static func grossForNet(_ net: Decimal, parameters p: YearParameters) -> Decimal {
        // net = g − g·e − (g − N)·t  ⇒  g = (net − N·t) / (1 − e − t)
        let e = p.employeeContributionRate
        let t = p.salaryTaxRate
        let g = (net - p.nonTaxableSalary * t) / (1 - e - t)
        let candidate = g.roundedTo(2)
        // Если база ниже минимальной, взносы считаются с минимума — уточняем перебором.
        if candidate >= p.minContributionBase { return candidate }
        var low = Decimal(0), high = p.minContributionBase
        for _ in 0..<60 {
            let mid = ((low + high) / 2)
            if breakdown(gross: mid, parameters: p).net < net { low = mid } else { high = mid }
        }
        return high.roundedTo(2)
    }
}

// MARK: - Годовой налог на доход граждан

public struct AnnualIncomeTaxEstimate: Equatable, Sendable {
    public var income: Decimal
    public var threshold: Decimal
    public var personalDeduction: Decimal
    public var taxableIncome: Decimal
    public var taxAt10: Decimal
    public var taxAt15: Decimal
    public var tax: Decimal { taxAt10 + taxAt15 }
}

public enum AnnualIncomeTax {
    /// Оценка годового налога на доход (godišnji porez na dohodak građana).
    /// - Parameter income: нетто-зарплата за год + прибыль после налога на прибыль.
    /// Это упрощённая оценка без вычетов на иждивенцев.
    public static func estimate(income: Decimal, parameters p: YearParameters) -> AnnualIncomeTaxEstimate {
        let avg = p.averageAnnualSalary
        let threshold = avg * 3
        let deduction = (avg * Decimal(string: "0.4")!).roundedTo(2)
        let excess = max(income - threshold, 0)
        let taxable = max(excess - deduction, 0)
        // До 6 средних зарплат (то есть первые 3 средние сверх порога) — 10 %, дальше — 15 %.
        let band10 = min(taxable, avg * 3)
        let band15 = max(taxable - band10, 0)
        return AnnualIncomeTaxEstimate(
            income: income,
            threshold: threshold,
            personalDeduction: deduction,
            taxableIncome: taxable,
            taxAt10: (band10 * Decimal(string: "0.10")!).roundedTo(2),
            taxAt15: (band15 * Decimal(string: "0.15")!).roundedTo(2)
        )
    }
}

// MARK: - Decimal helpers

public extension Decimal {
    func roundedTo(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
