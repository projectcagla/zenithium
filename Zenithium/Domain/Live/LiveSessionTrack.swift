//
//  LiveSessionTrack.swift
//  Zenithium
//
//  A session's accumulated impulse, kept incrementally. Adım 4.
//
//  ## The cost this removes
//
//  `LiveSessionEngine.evaluate` walks the whole sample array three times — the impulse
//  integral, the average reserve, and the projection's trailing filter — and it is called on
//  every tick *and* every heart-rate sample. That is quadratic in session length, and the
//  constant is not small:
//
//      30 min →     19 M element visits,  7 200 array allocations
//       1 h   →     78 M                 14 400
//       2 h   →    311 M                 28 800
//       3 h   →    700 M                 43 200
//       4 h   →  1 244 M                 57 600
//
//  A half-hour session is fine and a marathon is not. On a watch that cost is battery and
//  heat during the exact activity the watch exists for.
//
//  ## Why this is not a new implementation of the integral
//
//  It is the same one. The trapezoid sum is a sum of independent pairwise terms, so a total
//  built by adding each new pair as it arrives contains exactly the same terms in exactly
//  the same left-to-right order as one built by walking the array afterwards. Same terms,
//  same order, same floating-point result — `LiveSessionTrackTests` asserts it against
//  `LiveSessionEngine.trimp(over:input:)` over a three-hour session rather than taking it
//  on trust.
//
//  The engine's array-walking version stays exactly as it was. It is the definition, the
//  tests are written against it, and a fast path that cannot be checked against a definition
//  is not a fast path, it is a second opinion.
//
//  ## Why only a window of samples is kept
//
//  Once a pair's contribution is in `trimp`, the older of the two samples is not needed
//  again — nothing recomputes history. What still needs samples is the projection, which
//  reads a trailing window. So the track keeps that window plus slack, and a four-hour
//  session holds a few hundred samples instead of fourteen thousand.
//

import Foundation

/// Accumulates a live session's impulse as samples arrive.
struct LiveSessionTrack: Sendable, Equatable {

    // MARK: - Retention

    /// How much trailing history is kept, seconds.
    ///
    /// Twice the projection window, so the projection always has a full window to work from
    /// even when samples arrive unevenly.
    static let retainedSeconds: Double = LiveSessionEngine.projectionWindowSeconds * 2

    /// The fewest samples kept, whatever their age.
    ///
    /// A watch that has lost contact for ten minutes has samples older than the retention
    /// window and nothing newer. Dropping them would leave the projection with nothing to
    /// measure a rate from, so a floor is kept regardless of age.
    static let minimumRetainedSamples = 32

    // MARK: - Fixed for the session

    let restingHeartRate: Double
    let maxHeartRate: Double
    let biologicalSex: BiologicalSexValue

    // MARK: - Accumulated

    /// Banister impulse over every sample seen, not just the retained ones.
    private(set) var trimp: Double = 0

    /// Sum of every sample's reserve fraction, for the unweighted mean the engine reports.
    private(set) var reserveSum: Double = 0

    /// How many samples have been folded in, ever.
    private(set) var sampleCount = 0

    /// The trailing samples still held, oldest first.
    private(set) var retained: [LiveHeartRateSample] = []

    private var previous: LiveHeartRateSample?

    init(
        restingHeartRate: Double,
        maxHeartRate: Double,
        biologicalSex: BiologicalSexValue
    ) {
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.biologicalSex = biologicalSex
    }

    // MARK: - Reading

    /// The unweighted mean reserve fraction, matching `LiveSessionEngine`'s average.
    var averageReserveFraction: Double {
        sampleCount > 0 ? reserveSum / Double(sampleCount) : 0
    }

    /// The most recent sample, when there is one.
    var latest: LiveHeartRateSample? { retained.last }

    /// Whether anything has been recorded.
    var isEmpty: Bool { sampleCount == 0 }

    // MARK: - Appending

    /// Folds one sample in.
    ///
    /// Out-of-order samples are ignored rather than integrated: HealthKit can deliver a late
    /// reading, and a negative interval would subtract impulse from a session that only ever
    /// gains it.
    mutating func append(_ sample: LiveHeartRateSample) {
        guard sample.beatsPerMinute > 0 else { return }
        if let previous, sample.elapsedSeconds < previous.elapsedSeconds { return }

        let fraction = StrainScale.reserveFraction(
            heartRate: sample.beatsPerMinute,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
        reserveSum += fraction
        sampleCount += 1

        if let previous {
            // Exactly the term `LiveSessionEngine.trimp(over:input:)` would add for this pair,
            // including its two guards: a non-positive interval contributes nothing, and a gap
            // longer than the maximum is a gap rather than a held reading.
            let seconds = sample.elapsedSeconds - previous.elapsedSeconds
            if seconds > 0, seconds <= LiveSessionEngine.maximumGapSeconds {
                let constants = biologicalSex.trimpConstants
                let a = LiveSessionEngine.impulseRate(
                    previous.beatsPerMinute,
                    restingHeartRate: restingHeartRate,
                    maxHeartRate: maxHeartRate,
                    constants: constants
                )
                let b = LiveSessionEngine.impulseRate(
                    sample.beatsPerMinute,
                    restingHeartRate: restingHeartRate,
                    maxHeartRate: maxHeartRate,
                    constants: constants
                )
                trimp += (a + b) / 2 * (seconds / 60)
            }
        }

        previous = sample
        retained.append(sample)
        prune(now: sample.elapsedSeconds)
    }

    /// Drops samples that are past the retention window, keeping the floor.
    private mutating func prune(now: Double) {
        guard retained.count > Self.minimumRetainedSamples else { return }
        let cutoff = now - Self.retainedSeconds
        // Retained oldest-first, so the survivors are a suffix.
        guard let firstKept = retained.firstIndex(where: { $0.elapsedSeconds >= cutoff }) else {
            return
        }
        let removable = min(firstKept, retained.count - Self.minimumRetainedSamples)
        guard removable > 0 else { return }
        retained.removeFirst(removable)
    }
}
