//
//  BaselineState.swift
//  Zenithium
//
//  Persisted EWMA state, one row per metric. Spec §7, §4.1.
//

import Foundation
import SwiftData

@Model
final class BaselineState {

    /// `MetricKind.rawValue`. Unique — there is exactly one baseline per metric.
    @Attribute(.unique) var metricRawValue: String

    /// `μ_t` (§4.1).
    var mean: Double

    /// `V_t` (§4.1).
    var variance: Double

    /// `n`, the number of valid days folded in (§4.2.4).
    var sampleCount: Int

    /// The day of the most recent fold. A gap does not advance the EWMA (§4.2.5).
    var lastUpdated: Date?

    /// Values held while `n < 3`, before the baseline is seeded (§4.2.6).
    var seedValues: [Double]

    /// Stamped so a formula change can trigger a rebuild (§7).
    var engineVersion: Int

    var updatedAt: Date

    init(
        metric: MetricKind,
        mean: Double,
        variance: Double,
        sampleCount: Int,
        lastUpdated: Date?,
        seedValues: [Double],
        engineVersion: Int,
        updatedAt: Date
    ) {
        self.metricRawValue = metric.rawValue
        self.mean = mean
        self.variance = variance
        self.sampleCount = sampleCount
        self.lastUpdated = lastUpdated
        self.seedValues = seedValues
        self.engineVersion = engineVersion
        self.updatedAt = updatedAt
    }

    /// The metric this row tracks. Rows with an unrecognised key are ignored rather than
    /// crashing, which keeps a downgrade after a future schema addition survivable.
    var metric: MetricKind? {
        MetricKind(rawValue: metricRawValue)
    }

    /// The value type the engines consume. Returns `nil` for an unrecognised metric key.
    var snapshot: BaselineSnapshot? {
        guard let metric else { return nil }
        return BaselineSnapshot(
            metric: metric,
            mean: mean,
            variance: variance,
            sampleCount: sampleCount,
            lastUpdated: lastUpdated,
            seedValues: seedValues
        )
    }

    /// Folds an engine result back into the row.
    func apply(_ snapshot: BaselineSnapshot, engineVersion: Int, updatedAt: Date) {
        self.metricRawValue = snapshot.metric.rawValue
        self.mean = snapshot.mean
        self.variance = snapshot.variance
        self.sampleCount = snapshot.sampleCount
        self.lastUpdated = snapshot.lastUpdated
        self.seedValues = snapshot.seedValues
        self.engineVersion = engineVersion
        self.updatedAt = updatedAt
    }
}
