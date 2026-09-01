//
//  SleepDebtEngine.swift
//  Zenithium
//
//  Sleep owed, and the clock's weekly drift. Yol haritası v4, C4.
//
//  ## The ledger
//
//  Each night contributes `need − slept`, and the window's contributions are summed. Two
//  choices in that sentence are worth defending.
//
//  **Surplus counts, but not fully.** A ten-hour Saturday does not undo two five-hour
//  weeknights: the recovery literature is consistent that extended sleep repays some of a
//  deficit and not all of it, and a ledger that let a long lie-in zero out a bad week would
//  tell people something comfortable and false. Surplus is credited at
//  `surplusRepaymentFraction`.
//
//  **The window rolls and does not reset.** A fourteen-day window is long enough that a
//  single bad night does not dominate and short enough that a month-old deficit is not still
//  being carried. Nothing here claims the debt is *gone* after fourteen days — only that the
//  ledger stops counting it, which is a statement about the ledger.
//
//  ## Social jetlag
//
//  Wittmann and Roenneberg's measure: mid-sleep on free days minus mid-sleep on work days.
//  Free days are taken as Saturday and Sunday, which is an assumption and is named as one —
//  `ASSUMPTION SLEEP-2` — because shift workers and much of the world do not have that week.
//  It is reported as a number of hours the clock moves, never as a verdict.
//
//  §1 applies throughout: this reports hours, and never tells anybody to go to bed.
//

import Foundation

enum SleepDebtEngine {

    /// How far back the ledger looks.
    static let windowDays = 14

    /// Below this many nights the ledger is shown as provisional rather than as a number.
    ///
    /// Defined by `SleepDebtLedger`, which owns the question of when it is meaningful.
    static var minimumNights: Int { SleepDebtLedger.minimumNights }

    /// Each side of the social-jetlag comparison needs at least this many nights.
    static var minimumSideNights: Int { SocialJetlag.minimumSideNights }

    /// How much of a long night is credited against earlier debt.
    ///
    /// Recovery sleep repays part of a deficit rather than all of it — reaction time and
    /// alertness recover incompletely after a single extended night. Half is a deliberately
    /// round number: the literature supports "some but not all", and a more precise constant
    /// would be false precision.
    static let surplusRepaymentFraction: Double = 0.5

    /// A night shorter than this is treated as a gap in the record rather than as sleep.
    static let minimumCredibleSleepHours: Double = 2

    // MARK: - Ledger

    /// The rolling ledger over `days`.
    static func ledger(
        days: [BiometricDaySnapshot],
        needHours: Double,
        now: Date,
        calendar: Calendar
    ) -> SleepDebtLedger {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let window = days
            .filter { $0.dayStart >= start && $0.dayStart <= now }
            .sorted { $0.dayStart < $1.dayStart }

        var nightly: [SleepDebtNight] = []
        for day in window {
            let slept = TimeConversion.hours(fromSeconds: day.sleepDurationSeconds)
            // A night the watch barely saw is missing data, not a night with no sleep in it.
            // Counting it as an eight-hour deficit would be the ledger's loudest lie.
            guard slept >= minimumCredibleSleepHours else { continue }
            nightly.append(
                SleepDebtNight(
                    dayStart: day.dayStart,
                    sleptHours: slept,
                    shortfallHours: needHours - slept
                )
            )
        }

        let total = nightly.reduce(0.0) { running, night in
            night.shortfallHours >= 0
                ? running + night.shortfallHours
                : running + night.shortfallHours * surplusRepaymentFraction
        }

        return SleepDebtLedger(
            hours: max(0, total),
            nights: nightly.count,
            windowDays: windowDays,
            nightly: nightly,
            needHours: needHours
        )
    }

    // MARK: - Social jetlag

    /// The drift between free-day and work-day mid-sleep.
    ///
    /// ASSUMPTION SLEEP-2: free days are Saturday and Sunday. Wrong for shift workers and
    /// for much of the world, which is why the result carries the night counts on each side
    /// and the screen says which days it treated as free.
    static func socialJetlag(
        days: [BiometricDaySnapshot],
        now: Date,
        calendar: Calendar
    ) -> SocialJetlag? {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var workday: [Double] = []
        var freeDay: [Double] = []

        for day in days where day.dayStart >= start && day.dayStart <= now {
            guard let midpoint = day.sleepMidpointMinutes,
                  TimeConversion.hours(fromSeconds: day.sleepDurationSeconds) >= minimumCredibleSleepHours
            else { continue }
            // The record's day is the wake day, so its mid-sleep belongs to the night before.
            if isFreeDay(day.dayStart, calendar: calendar) {
                freeDay.append(midpoint)
            } else {
                workday.append(midpoint)
            }
        }

        // Circular means, because mid-sleep near midnight wraps: a 23:50 midpoint and a 00:10
        // one average to midnight, not to noon.
        guard let workMean = MathSupport.circularMean(workday, period: 1_440),
              let freeMean = MathSupport.circularMean(freeDay, period: 1_440) else { return nil }

        return SocialJetlag(
            workdayMidpointMinutes: workMean,
            freeDayMidpointMinutes: freeMean,
            workdayNights: workday.count,
            freeDayNights: freeDay.count
        )
    }

    /// Whether a wake day follows a free night — Saturday and Sunday mornings.
    static func isFreeDay(_ dayStart: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: dayStart)
        // 1 is Sunday and 7 is Saturday in every Gregorian calendar Foundation vends.
        return weekday == 1 || weekday == 7
    }

    // MARK: - Copy

    /// One sentence for the ledger. Hours, never an instruction (§1).
    static func summary(for ledger: SleepDebtLedger) -> String {
        guard ledger.isReliable else {
            return "Defter için henüz yeterli gece yok — \(ledger.nights)/\(minimumNights)."
        }
        guard ledger.hours >= 0.5 else {
            return "Son \(ledger.windowDays) günde uyku ihtiyacının gerisinde değilsin."
        }
        return "Son \(ledger.windowDays) günde \(ZenithiumFormat.metric(ledger.hours, digits: 1)) saat birikmiş — gecelik \(ZenithiumFormat.metric(ledger.needHours, digits: 1)) saatlik ihtiyaca göre."
    }

    /// One sentence for the drift. A measurement, not a verdict.
    static func summary(for jetlag: SocialJetlag) -> String {
        guard jetlag.isReliable else {
            return "Hafta içi ve hafta sonu karşılaştırması için yeterli gece yok."
        }
        let hours = abs(jetlag.hours)
        guard hours >= 0.25 else {
            return "Uyku orta noktan hafta içi ve hafta sonu neredeyse aynı."
        }
        let direction = jetlag.hours > 0 ? "geç" : "erken"
        return "Hafta sonları uyku orta noktan \(ZenithiumFormat.metric(hours, digits: 1)) saat daha \(direction)."
    }
}
