import Foundation

/// Exact additive accounting in score points, along the straight path between weighted
/// z-vectors. This decomposes a mathematical model, not physiological causation.
enum RecoveryChangeEngine {
    static func compare(previousScore: Double, previousOnCurrentBaseline: RecoveryOutput,
                        current: RecoveryOutput) -> RecoveryChange? {
        guard previousScore.isFinite, (1...100).contains(previousScore),
              let before = previousOnCurrentBaseline.score, let after = current.score,
              before.isFinite, after.isFinite else { return nil }
        let old = Dictionary(uniqueKeysWithValues: previousOnCurrentBaseline.drivers.map { ($0.driver, $0.contribution) })
        let new = Dictionary(uniqueKeysWithValues: current.drivers.map { ($0.driver, $0.contribution) })
        let zBefore = old.values.reduce(0, +)
        let zAfter = new.values.reduce(0, +)
        let zDelta = zAfter - zBefore
        let slope = abs(zDelta) > 1e-10 ? (after - before) / zDelta
            : (before <= 1 || before >= 100 ? 0 : EngineConstants.Recovery.logisticSlope * before * (1 - before / 100))
        let contributions = RecoveryDriver.allCases.compactMap { driver -> RecoveryChange.Contribution? in
            guard old[driver] != nil || new[driver] != nil else { return nil }
            return .init(driver: driver, points: ((new[driver] ?? 0) - (old[driver] ?? 0)) * slope,
                coverageChanged: (old[driver] == nil) != (new[driver] == nil))
        }
        return RecoveryChange(previousScore: previousScore, currentScore: after, contributions: contributions,
            baselineAndModelPoints: after - previousScore - contributions.reduce(0) { $0 + $1.points })
    }
}
