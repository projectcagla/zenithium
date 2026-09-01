//
//  BaselineSeries.swift
//  Zenithium
//
//  N days of daily aggregates per metric. Spec §8 (`fetchBaselineSeries(days:now:)`),
//  §4.2.5 (a missing day does not advance the EWMA — never interpolate biometrics).
//

import Foundation

/// One day's aggregate for one metric.
struct DailyMetricSample: Sendable, Equatable, Hashable {

    /// Local midnight of the day the aggregate covers, in `timeZoneIdentifier`.
    let dayStart: Date

    /// The aggregate value in the metric's canonical unit.
    let value: Double

    /// The identifier of the time zone the day was bucketed in (§5.6).
    let timeZoneIdentifier: String

    init(dayStart: Date, value: Double, timeZoneIdentifier: String) {
        self.dayStart = dayStart
        self.value = value
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// The trailing window of daily aggregates used to build or rebuild baselines.
///
/// Days with no data are simply absent — there is no placeholder, because §4.2.5 forbids
/// interpolating biometrics and requires a missing day to leave the EWMA unadvanced.
struct BaselineSeries: Sendable, Equatable {

    /// Samples keyed by metric, each already sorted ascending by `dayStart`.
    let samplesByMetric: [MetricKind: [DailyMetricSample]]

    /// The first day the query covered, whether or not it produced samples.
    let rangeStart: Date

    /// The last day the query covered, exclusive of today's partial day.
    let rangeEnd: Date

    init(
        samplesByMetric: [MetricKind: [DailyMetricSample]],
        rangeStart: Date,
        rangeEnd: Date
    ) {
        self.samplesByMetric = samplesByMetric.mapValues { samples in
            samples.sorted { $0.dayStart < $1.dayStart }
        }
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    static func empty(rangeStart: Date, rangeEnd: Date) -> BaselineSeries {
        BaselineSeries(samplesByMetric: [:], rangeStart: rangeStart, rangeEnd: rangeEnd)
    }

    /// Samples for one metric, ascending by day. Empty when the metric is unavailable.
    func samples(for metric: MetricKind) -> [DailyMetricSample] {
        samplesByMetric[metric] ?? []
    }

    /// The count of valid days for one metric — the `n` in the cold-start rules (§4.2.4).
    func validDayCount(for metric: MetricKind) -> Int {
        samples(for: metric).count
    }

    /// Samples strictly before `day`, which is the window a value is scored against so that
    /// today never contaminates the baseline it is scored by (§4.2.1).
    func samples(for metric: MetricKind, before day: Date) -> [DailyMetricSample] {
        samples(for: metric).filter { $0.dayStart < day }
    }
}
