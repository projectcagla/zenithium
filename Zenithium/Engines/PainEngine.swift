//
//  PainEngine.swift
//  Zenithium
//
//  What a pain log can honestly be compared against. Faz 32.
//
//  One question only: were the days before a logged entry heavier than the days before an
//  unlogged one? That is a comparison between two things Zenithium already owns, which is
//  exactly the boundary §12 draws. Anything about *why* is outside it.
//

import Foundation

enum PainEngine {

    /// The window before an entry that counts as "the load leading up to it".
    ///
    /// Forty-eight hours: delayed-onset soreness peaks between one and two days out, so a
    /// same-day window would miss most of what it is looking for and a week-long one would
    /// dilute it.
    static let lookbackHours: Double = 48

    /// Below this many entries for a region there is nothing to compare.
    static let minimumEntries = 3

    /// How much higher the pre-entry load must be before the difference is reported.
    ///
    /// Two TRIMP-scale strain points, and a relative check alongside it: a 0.3 difference on
    /// a base of 12 is noise, and a 2.0 difference on a base of 2 is one hard session.
    static let minimumLoadDifference: Double = 2.0
    static let minimumRelativeDifference: Double = 0.25

    /// Insights per region, strongest first.
    static func insights(
        entries: [PainEntry],
        dailyLoads: [DailyLoad],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [PainInsight] {
        let loadsByDay = Dictionary(
            dailyLoads.map { (calendar.startOfDay(for: $0.dayStart), $0.load) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !loadsByDay.isEmpty else { return [] }

        let entryDays = Set(entries.map { calendar.startOfDay(for: $0.loggedAt) })
        let grouped = Dictionary(grouping: entries, by: \.muscle)

        return grouped.compactMap { muscle, muscleEntries -> PainInsight? in
            guard muscleEntries.count >= minimumEntries else { return nil }

            let severities = muscleEntries.map { Double($0.severity) }
            let meanSeverity = MathSupport.mean(severities) ?? 0
            let hasSevere = muscleEntries.contains { $0.severity >= PainEntry.clinicianThreshold }

            let loadedBefore = muscleEntries.compactMap {
                precedingLoad(of: $0.loggedAt, loadsByDay: loadsByDay, calendar: calendar)
            }

            // The control group is every day with load data that carried *no* entry at all.
            // Comparing against days that had an entry for a different region would put the
            // same heavy Tuesday on both sides of the comparison.
            let otherwise = loadsByDay.keys
                .filter { !entryDays.contains($0) }
                .compactMap { precedingLoad(of: $0, loadsByDay: loadsByDay, calendar: calendar) }

            guard let before = MathSupport.mean(loadedBefore),
                  let control = MathSupport.mean(otherwise), control > 0 else { return nil }

            let difference = before - control
            let follows = difference >= minimumLoadDifference
                && difference / control >= minimumRelativeDifference

            return PainInsight(
                muscle: muscle,
                entryCount: muscleEntries.count,
                meanSeverity: meanSeverity,
                loadBefore: before,
                loadOtherwise: control,
                followsLoad: follows,
                hasSevereEntry: hasSevere
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasSevereEntry != rhs.hasSevereEntry { return lhs.hasSevereEntry }
            return lhs.meanSeverity > rhs.meanSeverity
        }
    }

    /// Total load across the lookback window ending at an instant.
    static func precedingLoad(
        of date: Date,
        loadsByDay: [Date: Double],
        calendar: Calendar
    ) -> Double? {
        let end = calendar.startOfDay(for: date)
        let days = Int(lookbackHours / 24)
        var total = 0.0
        var found = false

        for offset in 1...max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            guard let load = loadsByDay[day] else { continue }
            total += load
            found = true
        }
        return found ? total : nil
    }

    /// Left/right imbalance for a region, when both sides have been logged.
    ///
    /// Reported as a count and a difference in mean severity, never as a conclusion about
    /// asymmetry — one-sided entries have too many ordinary explanations.
    static func lateralityImbalance(entries: [PainEntry], muscle: MuscleGroup) -> String? {
        let relevant = entries.filter { $0.muscle == muscle }
        let left = relevant.filter { $0.laterality == .left }
        let right = relevant.filter { $0.laterality == .right }
        guard left.count + right.count >= minimumEntries else { return nil }
        guard left.count != right.count else { return nil }

        let dominant = left.count > right.count ? "sol" : "sağ"
        let dominantCount = max(left.count, right.count)
        let otherCount = min(left.count, right.count)
        return "\(muscle.displayName) kayıtlarının \(dominantCount)'i \(dominant) tarafta, \(otherCount)'i diğer tarafta."
    }
}
