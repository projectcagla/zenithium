//
//  SleepDebtIO.swift
//  Zenithium
//
//  The sleep-debt ledger's vocabulary. Yol haritası v4, C4.
//

import Foundation

/// A rolling account of sleep owed.
struct SleepDebtLedger: Sendable, Equatable {

    /// Below this many nights the ledger is provisional rather than a number.
    ///
    /// The threshold lives here rather than on the engine because it is a statement about
    /// when this value is meaningful, and because `Domain` is compiled by the watch and the
    /// widget while the engines are not — a type in `Domain` that reaches into `Engines`
    /// breaks both extension targets.
    static let minimumNights = 5

    /// Hours owed across the window, after repayment.
    let hours: Double

    /// How many nights the ledger was built from.
    let nights: Int

    /// The window's length in days, so the view can say what "rolling" means here.
    let windowDays: Int

    /// The nightly shortfall or surplus, oldest first. Negative is a surplus.
    let nightly: [SleepDebtNight]

    /// The sleep need the ledger was measured against, hours.
    let needHours: Double

    /// Whether there are enough nights for the number to mean anything.
    var isReliable: Bool { nights >= Self.minimumNights }

    /// The largest single night's shortfall, for the summary line.
    var worstNight: SleepDebtNight? { nightly.max { $0.shortfallHours < $1.shortfallHours } }
}

/// One night's contribution to the ledger.
struct SleepDebtNight: Sendable, Equatable, Hashable, Identifiable {

    let dayStart: Date

    /// Hours actually slept.
    let sleptHours: Double

    /// Need minus slept. Negative when the night was longer than the need.
    let shortfallHours: Double

    var id: Date { dayStart }
}

/// How far the weekend's sleep midpoint drifts from the working week's.
///
/// Social jetlag in the sense Wittmann and Roenneberg gave it: the difference between the
/// mid-sleep time on free days and on work days. A behavioural measurement, not a diagnosis
/// — it says the clock moved, and nothing about what that means for anybody in particular.
struct SocialJetlag: Sendable, Equatable {

    /// Each side of the comparison needs at least this many nights.
    static let minimumSideNights = 2

    /// Mid-sleep on work days, minutes after midnight.
    let workdayMidpointMinutes: Double

    /// Mid-sleep on free days, minutes after midnight.
    let freeDayMidpointMinutes: Double

    /// How many nights fed each side.
    let workdayNights: Int
    let freeDayNights: Int

    /// The shift, in hours. Positive means free days run later, which is the usual direction.
    ///
    /// Taken the short way round the clock, because mid-sleep wraps: a work-day midpoint of
    /// 23:50 and a free-day one of 00:40 differ by fifty minutes, not by twenty-three hours.
    var hours: Double {
        MathSupport.circularDifference(
            freeDayMidpointMinutes,
            workdayMidpointMinutes,
            period: 1_440
        ) / 60
    }

    /// Whether both sides have enough nights to compare.
    var isReliable: Bool {
        workdayNights >= Self.minimumSideNights && freeDayNights >= Self.minimumSideNights
    }
}
