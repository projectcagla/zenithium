//
//  LiveSessionEngine.swift
//  Zenithium
//
//  Where the session stands, while it is still running. Yol haritası v4, C1.
//
//  ## Why this exists
//
//  Two things the app already computes never met each other. `StrainEngine` scores a day
//  after it has happened, by integrating heart rate against reserve. `PrescriptionEngine`
//  names a ceiling for the day before it starts, from recovery and load. Between those two
//  is the only moment that matters while training: how much of today's room is left.
//
//  This engine is that middle. It integrates the same Banister impulse over the session so
//  far, adds it to what the day already held, and reports the result on the same 0–21 scale
//  the person sees every evening. Nothing new is modelled — the arithmetic is `StrainScale`
//  run forward on partial data.
//
//  ## Impulse, not strain, is what adds
//
//  Strain is `21·(1 − e^(−k·TRIMP))`, which saturates. Adding this morning's strain to this
//  session's strain would therefore double-count the flat part of the curve and overstate the
//  day badly. The day's strain before the session is inverted back to impulse, the session's
//  impulse is added there, and the sum is mapped forward once. That is the whole trick, and
//  getting it backwards is the single easiest way to make this screen lie.
//
//  ## Time to the ceiling
//
//  Taken from the *recent* rate rather than the session average, because the question is
//  asked mid-effort and the average includes the warm-up. When the recent rate would not
//  reach the ceiling in a reasonable session, no time is reported: an easy jog does not
//  arrive at a hard day's ceiling eventually, it never arrives.
//

import Foundation

enum LiveSessionEngine {

    /// The trailing window the projection's rate is taken from, seconds.
    ///
    /// Long enough that a few missed beats do not swing it, short enough that the number
    /// responds when someone starts climbing.
    static let projectionWindowSeconds: Double = 180

    /// Above this fraction of the ceiling the session reads as "nearing".
    static let nearingFraction: Double = 0.85

    /// Projections longer than this are not reported.
    ///
    /// Not a judgement about session length — a limit on what a rate measured over three
    /// minutes can honestly say about the next several hours.
    static let maximumProjectionSeconds: Double = 3 * 3_600

    /// Where the session stands.
    static func evaluate(_ input: LiveSessionInput) -> LiveSessionOutput {
        assemble(
            input: input,
            sessionTRIMP: trimp(over: input.samples, input: input),
            latest: input.samples.last,
            averageReserve: averageReserve(of: input.samples, input: input),
            projectionSamples: input.samples
        )
    }

    /// The same reading, from a track that accumulated the impulse as the samples arrived.
    ///
    /// Identical arithmetic — see `LiveSessionTrack` for why the incremental total is the
    /// same number rather than an approximation of it. This exists because the array-walking
    /// version is quadratic over a session's length and a marathon is a long session.
    static func evaluate(_ input: LiveSessionInput, track: LiveSessionTrack) -> LiveSessionOutput {
        assemble(
            input: input,
            sessionTRIMP: track.trimp,
            latest: track.latest,
            averageReserve: track.averageReserveFraction,
            projectionSamples: track.retained
        )
    }

    /// Everything both paths share, given the two figures they compute differently.
    private static func assemble(
        input: LiveSessionInput,
        sessionTRIMP: Double,
        latest: LiveHeartRateSample?,
        averageReserve average: Double,
        projectionSamples: [LiveHeartRateSample]
    ) -> LiveSessionOutput {
        // Impulse adds; strain does not. See the file comment.
        //
        // The inversion has no answer at or above the scale ceiling, where the logarithm
        // diverges. That is not a failure to fall back from: a day already reading 21 is
        // saturated, and anything added to it still reads 21. Returning zero there — which
        // is what a bare `?? 0` would do — would erase the whole day.
        let priorTRIMP = StrainScale.trimp(forStrain: input.strainBeforeSession)
        let dayStrain = priorTRIMP.map { StrainScale.strain(forTRIMP: $0 + sessionTRIMP) }
            ?? EngineConstants.Strain.scaleMax

        let current = latest.map {
            StrainScale.reserveFraction(
                heartRate: $0.beatsPerMinute,
                restingHeartRate: input.restingHeartRate,
                maxHeartRate: input.maxHeartRate
            )
        } ?? 0

        let progress = input.ceiling.flatMap { $0 > 0 ? dayStrain / $0 : nil }

        return LiveSessionOutput(
            sessionTRIMP: sessionTRIMP,
            dayStrain: dayStrain,
            strainAddedBySession: max(0, dayStrain - input.strainBeforeSession),
            currentReserveFraction: current,
            averageReserveFraction: average,
            ceilingProgress: progress,
            secondsToCeiling: priorTRIMP.flatMap {
                secondsToCeiling(input: input, samples: projectionSamples, dayTRIMP: $0 + sessionTRIMP)
            },
            band: band(forProgress: progress)
        )
    }

    // MARK: - Impulse

    /// Banister impulse over the samples, trapezoid rule on reserve fraction.
    ///
    /// The same integral `StrainEngine` runs on a finished day, with two differences that
    /// matter for a live reading: the interval before the first sample is not counted, since
    /// nothing is known about it, and a gap longer than `maximumGapSeconds` is treated as a
    /// gap rather than bridged — a watch that lost contact for four minutes did not hold the
    /// last reading for four minutes.
    static func trimp(over samples: [LiveHeartRateSample], input: LiveSessionInput) -> Double {
        guard samples.count >= 2 else { return 0 }
        let constants = input.biologicalSex.trimpConstants

        var total: Double = 0
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let seconds = next.elapsedSeconds - previous.elapsedSeconds
            guard seconds > 0, seconds <= maximumGapSeconds else { continue }

            let a = impulseRate(
                previous.beatsPerMinute,
                restingHeartRate: input.restingHeartRate,
                maxHeartRate: input.maxHeartRate,
                constants: constants
            )
            let b = impulseRate(
                next.beatsPerMinute,
                restingHeartRate: input.restingHeartRate,
                maxHeartRate: input.maxHeartRate,
                constants: constants
            )
            total += (a + b) / 2 * (seconds / 60)
        }
        return total
    }

    /// A gap longer than this is not integrated across.
    static let maximumGapSeconds: Double = 120

    /// Impulse per minute at one heart rate.
    ///
    /// Takes the two rates rather than the whole input so `LiveSessionTrack` can add the same
    /// term incrementally without a second copy of this expression existing anywhere.
    static func impulseRate(
        _ beatsPerMinute: Double,
        restingHeartRate: Double,
        maxHeartRate: Double,
        constants: TRIMPConstants
    ) -> Double {
        let x = StrainScale.reserveFraction(
            heartRate: beatsPerMinute,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
        return x * constants.b * exp(constants.c * x)
    }

    // MARK: - Projection

    private static func secondsToCeiling(
        input: LiveSessionInput,
        samples: [LiveHeartRateSample],
        dayTRIMP: Double
    ) -> Double? {
        guard let ceiling = input.ceiling,
              let ceilingTRIMP = StrainScale.trimp(forStrain: ceiling) else { return nil }

        let remaining = ceilingTRIMP - dayTRIMP
        guard remaining > 0 else { return nil }

        // The rate over the trailing window, falling back to the whole session early on when
        // the window has not filled yet.
        let cutoff = input.elapsedSeconds - projectionWindowSeconds
        // Samples are ordered, so the window is a suffix — found by index rather than by
        // allocating a filtered copy on every tick.
        let windowStart = samples.firstIndex { $0.elapsedSeconds >= cutoff } ?? samples.endIndex
        let window = samples[windowStart...]
        let recent = window.count >= 2 ? Array(window) : samples
        guard let first = recent.first, let last = recent.last else { return nil }

        let span = last.elapsedSeconds - first.elapsedSeconds
        guard span > 0 else { return nil }

        let impulse = trimp(over: recent, input: input)
        let perSecond = impulse / span
        guard perSecond > 0 else { return nil }

        let seconds = remaining / perSecond
        guard seconds <= maximumProjectionSeconds else { return nil }
        return seconds
    }

    // MARK: - Bands

    static func band(forProgress progress: Double?) -> LiveSessionBand {
        guard let progress else { return .unbounded }
        if progress >= 1 { return .beyond }
        if progress >= nearingFraction { return .nearing }
        return .building
    }

    // MARK: - Averages

    private static func averageReserve(
        of samples: [LiveHeartRateSample],
        input: LiveSessionInput
    ) -> Double {
        let fractions = samples.map {
            StrainScale.reserveFraction(
                heartRate: $0.beatsPerMinute,
                restingHeartRate: input.restingHeartRate,
                maxHeartRate: input.maxHeartRate
            )
        }
        return MathSupport.mean(fractions) ?? 0
    }
}
