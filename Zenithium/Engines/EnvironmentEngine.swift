//
//  EnvironmentEngine.swift
//  Zenithium
//
//  Environmental context, on device. Faz 30.
//
//  ## What is here, and what is deliberately not
//
//  The roadmap named three things: daylight, altitude and time-zone shift. Two are built.
//
//  **Daylight** is the one that mattered most, and it fills a real gap. The circadian engine
//  models an alertness curve anchored on sleep timing, but light is the dominant zeitgeber —
//  so a week spent almost entirely indoors makes that curve *less* trustworthy, and the app
//  should say so rather than presenting the same confident arc.
//
//  **Time-zone shift** is cheap and genuinely useful: the day records already carry the zone
//  they were computed in, so a change is detectable without a single new read.
//
//  **Altitude is not built, and the reason is worth stating.** `CMAltimeter` reports live
//  relative altitude only; HealthKit stores no altitude history. Tracking acclimatisation
//  would mean starting a background sampling path, storing a new series and keeping it alive
//  — a substantial amount of machinery for a signal that matters to a small number of users
//  a few weeks a year. It is a real feature and it belongs in its own phase, not smuggled in
//  as a side effect of this one.
//

import Foundation

/// How reliable the circadian curve is, given how much light the user actually saw.
struct DaylightContext: Sendable, Equatable, Hashable {

    /// Mean minutes of daylight per day across the window.
    let meanMinutes: Double

    /// How many days carried a reading.
    let dayCount: Int

    /// A multiplier on the circadian curve's confidence, 0…1.
    let circadianReliability: Double

    /// Whether there was enough data to say anything.
    var hasData: Bool { dayCount >= EnvironmentEngine.minimumDaylightDays }

    var summary: String? {
        guard hasData else { return nil }
        let minutes = Int(meanMinutes.rounded())
        if circadianReliability >= 0.9 {
            return "Günde ortalama \(minutes) dakika gün ışığı alıyorsun — sirkadiyen eğrisi için sağlam bir zemin."
        }
        return "Günde ortalama \(minutes) dakika gün ışığı alıyorsun. Işık, sirkadiyen ritmin en güçlü ayarlayıcısı; bu kadar azken günün eğrisi daha az güvenilir."
    }
}

/// A change of time zone in the recent record.
struct TimeZoneShift: Sendable, Equatable, Hashable {

    let from: String
    let to: String

    /// The first day recorded in the new zone.
    let date: Date

    /// Hours moved. Positive is eastward.
    let hours: Double

    /// How long the body is usually described as taking to re-anchor.
    ///
    /// About a day per hour, and longer eastward — advancing the clock is harder than
    /// delaying it because the free-running human day runs slightly over twenty-four hours.
    var adaptationDays: Int {
        let base = abs(hours)
        return Int((hours > 0 ? base * 1.2 : base * 0.8).rounded())
    }

    var summary: String {
        let direction = hours > 0 ? "doğuya" : "batıya"
        return "\(Int(abs(hours))) saat \(direction) geçtin. Sirkadiyen ritmin yeniden oturması genelde \(adaptationDays) gün sürer; bu sürede toparlanma puanı düşük seyredebilir ve bu normaldir."
    }
}

enum EnvironmentEngine {

    /// Below this many days with a daylight reading, nothing is claimed.
    static let minimumDaylightDays = 7

    /// Daylight below which the circadian curve is treated as less anchored.
    ///
    /// Sixty minutes. Not a target and not presented as one — it is the point below which
    /// the app reduces its own confidence, which is a statement about the model rather than
    /// about the person.
    static let lowDaylightMinutes: Double = 60

    /// Daylight at or above which reliability is unpenalised.
    static let goodDaylightMinutes: Double = 120

    // MARK: - Daylight

    static func daylightContext(from samples: [VitalSample]) -> DaylightContext {
        let daylight = samples.filter { $0.sign == .timeInDaylight }.map(\.value)
        guard !daylight.isEmpty, let mean = MathSupport.mean(daylight) else {
            return DaylightContext(meanMinutes: 0, dayCount: 0, circadianReliability: 1)
        }

        // Linear between the two thresholds, floored at 0.6: even a user who never goes
        // outside still has sleep timing, which is the curve's primary anchor. Dropping
        // reliability further would overstate light's share of the model.
        let reliability: Double
        switch mean {
        case goodDaylightMinutes...: reliability = 1.0
        case ..<lowDaylightMinutes: reliability = 0.6
        default:
            let progress = (mean - lowDaylightMinutes) / (goodDaylightMinutes - lowDaylightMinutes)
            reliability = 0.6 + 0.4 * progress
        }

        return DaylightContext(
            meanMinutes: mean,
            dayCount: daylight.count,
            circadianReliability: reliability
        )
    }

    // MARK: - Time zones

    /// The most recent time-zone change in the record, if there was one.
    ///
    /// Uses the zone each day record was computed in, so no new read is needed. A change is
    /// only reported when the offset actually differs — a rename, or a zone that shares an
    /// offset, is not a journey.
    static func recentTimeZoneShift(
        in days: [BiometricDaySnapshot],
        within lastDays: Int = 14
    ) -> TimeZoneShift? {
        let ordered = days.sorted { $0.dayStart < $1.dayStart }.suffix(lastDays)
        guard ordered.count >= 2 else { return nil }

        var previous: (identifier: String, offset: Int)?
        var latest: TimeZoneShift?

        for day in ordered {
            guard let zone = TimeZone(identifier: day.timeZoneIdentifier) else { continue }
            let offset = zone.secondsFromGMT(for: day.dayStart)

            if let previous, previous.offset != offset {
                latest = TimeZoneShift(
                    from: previous.identifier,
                    to: day.timeZoneIdentifier,
                    date: day.dayStart,
                    hours: Double(offset - previous.offset) / 3600
                )
            }
            previous = (day.timeZoneIdentifier, offset)
        }
        return latest
    }

    /// Whether a shift is recent enough to still be affecting things.
    static func isAdapting(to shift: TimeZoneShift, on day: Date, calendar: Calendar) -> Bool {
        let elapsed = calendar.dateComponents([.day], from: shift.date, to: day).day ?? 0
        return elapsed >= 0 && elapsed <= shift.adaptationDays
    }
}
