import Foundation

public struct Deadline: Identifiable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var title: String
    public var details: String
    public var form: String?
    /// Отмечено ли как выполненное (определяется по данным, если возможно).
    public var done: Bool

    public func daysLeft(from now: Date = Date()) -> Int {
        let start = Dates.calendar.startOfDay(for: now)
        let end = Dates.calendar.startOfDay(for: date)
        return Dates.calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// Календарь обязательств предузетника на книгах с личной зарплатой.
public enum DeadlineCalendar {
    public static func deadlines(for year: Int, data: AppData) -> [Deadline] {
        var list: [Deadline] = []
        let registration = data.profile.registrationDate
        let regYear = registration.map(Dates.year)
        let regMonth = registration.map(Dates.month) ?? 1
        let firstMonth = (regYear == year) ? regMonth : 1
        let active = regYear.map { $0 <= year } ?? true

        // Старт: авансовая декларация в течение 15 дней.
        if let reg = registration, regYear == year {
            let due = Dates.nextWorkingDay(Dates.adding(days: 15, to: reg))
            list.append(Deadline(
                id: "ppdg1s-start-\(year)",
                date: due,
                title: "Авансовая декларация PPDG-1S",
                details: "В течение 15 дней после начала деятельности: прогноз доходов и расходов до конца года. По ней считается ежемесячный аванс налога на прибыль. Подаётся через ePorezi.",
                form: "PPDG-1S",
                done: data.estimate(for: year) != nil))
        }

        if active {
            for month in firstMonth...12 {
                // Аванс налога на прибыль — до 15-го следующего месяца.
                let nextMonthDate = Dates.adding(months: 1, to: Dates.make(year, month, 1))
                let ny = Dates.year(nextMonthDate), nm = Dates.month(nextMonthDate)
                let advanceDue = Dates.nextWorkingDay(Dates.make(ny, nm, 15))
                let advancePaid = data.taxPayments.contains {
                    $0.kind == .profitAdvance && ($0.periodYear ?? Dates.year($0.date)) == year
                        && ($0.periodMonth ?? Dates.month($0.date)) == month
                }
                list.append(Deadline(
                    id: "advance-\(year)-\(month)",
                    date: advanceDue,
                    title: "Аванс налога на прибыль за \(Dates.monthName(month))",
                    details: "Платёж по решению из авансовой декларации PPDG-1S. Сумма — в разделе «Налоги и сроки».",
                    form: nil,
                    done: advancePaid))

                // Личная зарплата: PPP-PD подаётся в день выплаты; если не выплатил — до конца следующего месяца с минимальной базы.
                let salary = data.salaries.first { $0.year == year && $0.month == month }
                let salaryDue = Dates.nextWorkingDay(Dates.lastDay(ofMonth: nm, year: ny))
                list.append(Deadline(
                    id: "salary-\(year)-\(month)",
                    date: salaryDue,
                    title: "Зарплата за \(Dates.monthName(month)): PPP-PD и взносы",
                    details: "PPP-PD подаётся в день выплаты зарплаты, вместе с уплатой налога и взносов. Если зарплату за месяц не выплатил — крайний срок конец следующего месяца, взносы считаются с минимальной базы.",
                    form: "PPP-PD",
                    done: salary?.paidDate != nil))
            }
        }

        // Годовые обязательства за предыдущий год (если ИП работало в прошлом году).
        if let regYear, regYear < year {
            let prev = year - 1
            list.append(Deadline(
                id: "apr-\(year)",
                date: Dates.nextWorkingDay(Dates.make(year, 3, 31)),
                title: "Годовой финансовый отчёт в APR за \(prev)",
                details: "Bilans stanja и bilans uspeha через приложение APR, подпись — квалифицированная электронная подпись. Сбор 570 RSD. Срок по данным biznis.rs — 31 марта; проверь актуальный срок на сайте APR.",
                form: "RGFI",
                done: false))
            list.append(Deadline(
                id: "ppdg1s-annual-\(year)",
                date: Dates.nextWorkingDay(Dates.make(year, 4, 15)),
                title: "Годовая декларация PPDG-1S и PB 2 за \(prev)",
                details: "Итоговая декларация по налогу на прибыль и налоговый баланс. До этой же даты доплачивается разница налога за год.",
                form: "PPDG-1S + PB 2",
                done: false))
            list.append(Deadline(
                id: "ppdg2r-\(year)",
                date: Dates.nextWorkingDay(Dates.make(year, 5, 15)),
                title: "Годовой налог на доход за \(prev) (если превысил порог)",
                details: "Подаётся, если доход за год (нетто-зарплата + прибыль после налога) больше 3 средних годовых зарплат. Прогноз — в разделе «Налоги и сроки».",
                form: "PPDG-2R",
                done: false))
            list.append(Deadline(
                id: "eco-\(year)",
                date: Dates.nextWorkingDay(Dates.make(year, 6, 30)),
                title: "Эко-налог (со второго года деятельности)",
                details: "Платится со второго календарного года ведения бизнеса. Декларация на lpa.gov.rs. Проверь точный срок по решению.",
                form: nil,
                done: false))
        }

        // ВНЖ: продление не раньше чем за 3 месяца до окончания.
        if let expiry = data.profile.residencePermitExpiry {
            let windowOpens = Dates.adding(months: -3, to: expiry)
            if Dates.year(windowOpens) == year {
                list.append(Deadline(
                    id: "permit-\(year)",
                    date: windowOpens,
                    title: "Можно подавать на продление ВНЖ",
                    details: "Окно открывается за 3 месяца до окончания ВНЖ (\(Dates.display(expiry))). Нужна выписка с оборотом бизнес-счёта за 6 месяцев.",
                    form: nil,
                    done: false))
            }
        }

        return list.sorted { $0.date < $1.date }
    }

    /// Ближайшие невыполненные сроки.
    public static func upcoming(data: AppData, from now: Date = Date(), limit: Int = 5) -> [Deadline] {
        let y = Dates.year(now)
        let all = deadlines(for: y, data: data) + deadlines(for: y + 1, data: data)
        return Array(all.filter { !$0.done && $0.daysLeft(from: now) >= -30 }.prefix(limit))
    }
}
