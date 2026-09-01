//
//  TestSupport.swift
//  ZenithiumTests
//
//  Shared fixtures. Spec §11: Swift Testing only, no XCTest, and every engine suite runs
//  without HealthKit, without SwiftData and without a device.
//

import Testing
import Foundation
@testable import Zenithium

/// §11 — golden vectors must reproduce to ±0.05.
enum GoldenTolerance {
    static let `default`: Double = 0.05

    /// §5.3 states the five strain calibration anchors to ±0.1.
    static let strainAnchor: Double = 0.1

    /// For values the specification quotes to six figures.
    static let tight: Double = 0.000005
}

/// Asserts two doubles are within a tolerance, reporting the actual delta on failure.
func expectClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = GoldenTolerance.default,
    _ label: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let delta = abs(actual - expected)
    #expect(
        delta <= tolerance,
        "\(label.isEmpty ? "value" : label): expected \(expected) ± \(tolerance), got \(actual) (Δ \(delta))",
        sourceLocation: sourceLocation
    )
}

/// Fixed calendars, so no test depends on where it runs (§2.7).
enum TestCalendars {

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// A zone with a spring-forward transition on 2025-03-09 at 02:00 local.
    static var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }
}

/// Parses an ISO-8601 instant. Returns the epoch for malformed input rather than trapping,
/// so a typo in a fixture fails an assertion instead of crashing the suite.
func iso(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string) ?? Date(timeIntervalSince1970: 0)
}

/// A scoring baseline with settled confidence, for tests that are not about cold start.
func settledBaseline(
    _ metric: MetricKind,
    mean: Double,
    standardDeviation: Double,
    sampleCount: Int = 60
) -> ScoringBaseline {
    ScoringBaseline(
        metric: metric,
        mean: mean,
        standardDeviation: standardDeviation,
        sampleCount: sampleCount,
        confidence: 1,
        isScorable: true
    )
}

/// An observation of a metric against a settled baseline.
func observation(
    _ metric: MetricKind,
    value: Double,
    mean: Double,
    standardDeviation: Double,
    sampleCount: Int = 60
) -> MetricObservation {
    MetricObservation(
        value: value,
        baseline: settledBaseline(
            metric,
            mean: mean,
            standardDeviation: standardDeviation,
            sampleCount: sampleCount
        )
    )
}

/// A steady heart-rate series: one sample per `spacing` seconds across `minutes`.
///
/// The first sample sits exactly at `start`, which the strain engine treats as the anchor
/// rather than as a contributing segment — so `minutes` minutes of samples produce exactly
/// `minutes` minutes of accumulated time (§5.3).
func steadyHeartRateSeries(
    start: Date,
    minutes: Int,
    beatsPerMinute: Double,
    spacing: TimeInterval = 60
) -> [HeartRateSample] {
    let count = Int(Double(minutes) * 60 / spacing)
    return (0...count).map { index in
        HeartRateSample(
            timestamp: start.addingTimeInterval(Double(index) * spacing),
            beatsPerMinute: beatsPerMinute,
            sourceBundleIdentifier: "test"
        )
    }
}

/// A day window starting at `start` and running 24 hours.
func testDayWindow(start: Date, calendar: Calendar = TestCalendars.utc) -> DayWindow {
    DayWindow(
        start: start,
        end: start.addingTimeInterval(TimeConversion.secondsPerDay),
        timeZoneIdentifier: calendar.timeZone.identifier,
        dayStart: calendar.startOfDay(for: start),
        boundary: .wakeAnchored,
        usedFallbackAnchor: false
    )
}

/// A sleep segment.
func sleepSegment(
    from start: Date,
    to end: Date,
    stage: SleepStage,
    timeZoneIdentifier: String = "UTC"
) -> SleepSegment {
    SleepSegment(
        interval: DateInterval(start: start, end: end),
        stage: stage,
        sourceBundleIdentifier: "test",
        timeZoneIdentifier: timeZoneIdentifier
    )
}
