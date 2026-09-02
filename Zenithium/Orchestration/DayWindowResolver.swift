//
//  DayWindowResolver.swift
//  Zenithium
//
//  Resolves the physiological day and the night that precedes it. Spec §5.3 (the day boundary
//  is wake time, not midnight), §5.6 (DST and timezone travel).
//
//  ASSUMPTION DAY-1: wake-anchored by default, falling back to local 04:00 when no wake time
//  is known, so a day that was never slept through still starts.
//
//  Every date computation here goes through the injected calendar. Nothing adds 86 400 to a
//  `Date` — across a DST transition that is the wrong answer by an hour, and §5.6 requires
//  offsets in absolute time with rendering in local wall-clock.
//

import Foundation

struct DayWindowResolver: Sendable {

    let calendar: Calendar
    let boundary: DayBoundary

    init(calendar: Calendar, boundary: DayBoundary = DayBoundary.default) {
        self.calendar = calendar
        self.boundary = boundary
    }

    /// The physiological day that `date` falls inside.
    ///
    /// - Parameter wakeTime: the wake time of the day being resolved, when it is known.
    ///   With `.wakeAnchored` and no wake time, the fallback hour is used and the window is
    ///   flagged so the UI can say the boundary was estimated.
    func window(containing date: Date, wakeTime: Date?) -> DayWindow {
        switch boundary {
        case .midnight:
            let start = calendar.startOfDay(for: date)
            let end = nextDay(after: start)
            return DayWindow(
                start: start,
                end: end,
                timeZoneIdentifier: calendar.timeZone.identifier,
                dayStart: start,
                boundary: .midnight,
                usedFallbackAnchor: false
            )

        case .wakeAnchored:
            if let wakeTime, let window = wakeAnchoredWindow(containing: date, wakeTime: wakeTime) {
                return window
            }
            return fallbackWindow(containing: date)
        }
    }

    /// The window anchored on a known wake time.
    ///
    /// If `date` falls before that wake time it belongs to the *previous* physiological day —
    /// which is the whole point of the wake anchor: 01:00 is the tail of yesterday, not the
    /// start of today.
    private func wakeAnchoredWindow(containing date: Date, wakeTime: Date) -> DayWindow? {
        let anchorDay = calendar.startOfDay(for: wakeTime)
        var start = wakeTime
        var dayStart = anchorDay

        if date < wakeTime {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: anchorDay),
                  let previousWake = transpose(wakeTime, ontoDayStartingAt: previousDay) else {
                return nil
            }
            start = previousWake
            dayStart = previousDay
        }
        guard let end = nextDayPreservingWallClock(after: start) else { return nil }
        return DayWindow(
            start: start,
            end: end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            dayStart: dayStart,
            boundary: .wakeAnchored,
            usedFallbackAnchor: false
        )
    }

    /// ASSUMPTION DAY-1 — the 04:00 fallback when no sleep record exists.
    private func fallbackWindow(containing date: Date) -> DayWindow {
        let today = calendar.startOfDay(for: date)
        let hour = DayBoundary.fallbackHour
        let anchor = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today) ?? today

        let start: Date
        let dayStart: Date
        if date < anchor {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: previousDay) ?? previousDay
            dayStart = previousDay
        } else {
            start = anchor
            dayStart = today
        }
        let end = nextDayPreservingWallClock(after: start) ?? nextDay(after: start)
        return DayWindow(
            start: start,
            end: end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            dayStart: dayStart,
            boundary: .wakeAnchored,
            usedFallbackAnchor: true
        )
    }

    /// The night whose sleep belongs to a given wake day.
    ///
    /// ASSUMPTION SLEEP-1 — the window runs from 18:00 the previous evening to noon on the
    /// wake day, which is wide enough for a shifted schedule and narrow enough that an
    /// afternoon nap cannot be mistaken for the night.
    func nightWindow(forWakeDay wakeDay: Date) -> DateInterval {
        let dayStart = calendar.startOfDay(for: wakeDay)
        let start = calendar.date(
            byAdding: .hour,
            value: Int(EngineConstants.Sleep.nightWindowStartHour),
            to: dayStart
        ) ?? dayStart
        let end = calendar.date(
            byAdding: .hour,
            value: Int(EngineConstants.Sleep.nightWindowEndHour),
            to: dayStart
        ) ?? dayStart
        return DateInterval(start: start, end: max(start, end))
    }

    /// Daytime nap window preceding a night.
    /// Runs from the previous night's wake time up to the start of this night's window.
    /// If previous wake time is unknown, returns `nil`.
    func napWindow(previousWakeTime: Date?, forWakeDay wakeDay: Date) -> DateInterval? {
        guard let previousWakeTime else { return nil }
        let night = nightWindow(forWakeDay: wakeDay)
        guard previousWakeTime < night.start else { return nil }
        return DateInterval(start: previousWakeTime, end: night.start)
    }

    /// Local midnight of the day a date falls in.
    func dayStart(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The `n`-th day before a reference day, by calendar arithmetic.
    func day(byAdding days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Whether two instants fall on the same calendar day in this calendar's zone.
    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - DST-safe helpers

    /// The next local midnight after a day start. Correct across DST because the calendar,
    /// not arithmetic on seconds, decides how long the day was.
    private func nextDay(after dayStart: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    /// The same wall-clock time on the following day.
    ///
    /// On a spring-forward day this is 23 hours later in absolute time and on a fall-back day
    /// 25 — which is the behaviour §5.6 wants: the user's day still starts when they wake,
    /// whatever the clocks did overnight.
    private func nextDayPreservingWallClock(after date: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: date)
    }

    /// Moves a time-of-day onto another day, preserving hour, minute and second.
    private func transpose(_ time: Date, ontoDayStartingAt dayStart: Date) -> Date? {
        let components = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: dayStart
        )
    }
}
