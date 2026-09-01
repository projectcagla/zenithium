//
//  LiveSessionTrackTests.swift
//  ZenithiumTests
//
//  The incremental impulse total, checked against the definition it replaces.
//
//  This is the assertion the whole optimisation rests on. `LiveSessionTrack` exists because
//  walking the sample array on every tick is quadratic in session length; it is only allowed
//  to exist because the total it accumulates is the same number the engine's own integral
//  produces. Not close to it — the same terms added in the same order.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Live session track")
struct LiveSessionTrackTests {

    private let resting: Double = 55
    private let maximum: Double = 190

    /// A session with uneven sampling and two dropouts long enough to break the integral.
    ///
    /// Deterministic: a seeded generator rather than `random`, so a failure is reproducible.
    private func session(seconds: Double) -> [LiveHeartRateSample] {
        var samples: [LiveHeartRateSample] = []
        var t: Double = 0
        var seed: UInt64 = 7
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        while t < seconds {
            t += [1.0, 1.0, 1.0, 2.0, 0.5][Int(next() * 5) % 5]
            // Two gaps longer than `maximumGapSeconds`, so the guard is exercised.
            if (4_000...4_300).contains(t) || (8_000...8_400).contains(t) { continue }
            let bpm = 120 + 40 * sin(t / 600) + (next() - 0.5) * 8
            samples.append(LiveHeartRateSample(elapsedSeconds: t, beatsPerMinute: bpm))
        }
        return samples
    }

    private func input(
        samples: [LiveHeartRateSample],
        elapsed: Double,
        ceiling: Double? = 15
    ) -> LiveSessionInput {
        LiveSessionInput(
            elapsedSeconds: elapsed,
            samples: samples,
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: .notSet,
            strainBeforeSession: 4,
            ceiling: ceiling
        )
    }

    private func filled(with samples: [LiveHeartRateSample]) -> LiveSessionTrack {
        var track = LiveSessionTrack(
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: .notSet
        )
        for sample in samples { track.append(sample) }
        return track
    }

    @Test("Üç saatlik seansta artımlı integral, motorun integraliyle aynı")
    func incrementalTotalMatchesTheEngineOverALongSession() {
        let samples = session(seconds: 3 * 3_600)
        let batch = LiveSessionEngine.trimp(over: samples, input: input(samples: samples, elapsed: 3 * 3_600))
        let track = filled(with: samples)

        #expect(samples.count > 5_000, "test seansı yeterince uzun değil")
        // The same terms in the same order, so this is an equality and not a tolerance.
        #expect(track.trimp == batch)
    }

    @Test("Ortalama rezerv de aynı")
    func averageReserveMatches() {
        let samples = session(seconds: 1_800)
        let track = filled(with: samples)

        let fractions = samples.map {
            StrainScale.reserveFraction(
                heartRate: $0.beatsPerMinute,
                restingHeartRate: resting,
                maxHeartRate: maximum
            )
        }
        let expected = MathSupport.mean(fractions) ?? 0
        #expect(abs(track.averageReserveFraction - expected) < 1e-12)
    }

    @Test("İki değerlendirme yolu aynı çıktıyı veriyor")
    func bothEvaluatePathsAgree() {
        let samples = session(seconds: 2 * 3_600)
        let elapsed = samples.last?.elapsedSeconds ?? 0
        let track = filled(with: samples)

        let walked = LiveSessionEngine.evaluate(input(samples: samples, elapsed: elapsed))
        let accumulated = LiveSessionEngine.evaluate(
            input(samples: track.retained, elapsed: elapsed),
            track: track
        )

        #expect(walked.sessionTRIMP == accumulated.sessionTRIMP)
        #expect(walked.dayStrain == accumulated.dayStrain)
        #expect(walked.strainAddedBySession == accumulated.strainAddedBySession)
        #expect(walked.currentReserveFraction == accumulated.currentReserveFraction)
        #expect(abs(walked.averageReserveFraction - accumulated.averageReserveFraction) < 1e-12)
        #expect(walked.ceilingProgress == accumulated.ceilingProgress)
        #expect(walked.band == accumulated.band)
    }

    /// The dropouts in the fixture are longer than `maximumGapSeconds`, so a track that
    /// bridged them would report more impulse than the engine does.
    @Test("Uzun kopukluklar iki yolda da aynı biçimde atlanıyor")
    func longGapsAreSkippedIdentically() {
        let samples = [
            LiveHeartRateSample(elapsedSeconds: 0, beatsPerMinute: 140),
            LiveHeartRateSample(elapsedSeconds: 60, beatsPerMinute: 145),
            // A five-minute dropout: not integrated across by either path.
            LiveHeartRateSample(elapsedSeconds: 360, beatsPerMinute: 150),
            LiveHeartRateSample(elapsedSeconds: 420, beatsPerMinute: 152)
        ]
        let track = filled(with: samples)
        let batch = LiveSessionEngine.trimp(over: samples, input: input(samples: samples, elapsed: 420))

        #expect(track.trimp == batch)
        // Two 60-second segments contributed; the 300-second gap did not.
        #expect(track.trimp > 0)
    }

    @Test("Sırasız gelen örnek integrali geri almıyor")
    func outOfOrderSamplesAreIgnored() {
        var track = LiveSessionTrack(
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: .notSet
        )
        track.append(LiveHeartRateSample(elapsedSeconds: 0, beatsPerMinute: 140))
        track.append(LiveHeartRateSample(elapsedSeconds: 30, beatsPerMinute: 150))
        let afterTwo = track.trimp

        // A late reading from before the last one. Integrating it would subtract impulse
        // from a session that can only gain it.
        track.append(LiveHeartRateSample(elapsedSeconds: 10, beatsPerMinute: 90))

        #expect(track.trimp == afterTwo)
        #expect(track.sampleCount == 2)
    }

    @Test("Sıfır ve negatif kalp hızı sayılmıyor")
    func implausibleSamplesAreIgnored() {
        var track = LiveSessionTrack(
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: .notSet
        )
        track.append(LiveHeartRateSample(elapsedSeconds: 0, beatsPerMinute: 0))
        track.append(LiveHeartRateSample(elapsedSeconds: 1, beatsPerMinute: -5))

        #expect(track.isEmpty)
        #expect(track.trimp == 0)
        #expect(track.averageReserveFraction == 0)
    }

    /// The memory half of the fix: a four-hour session must not hold four hours of samples.
    @Test("Uzun seansta bellekte yalnızca kuyruk penceresi kalıyor")
    func onlyTheTrailingWindowIsRetained() {
        let samples = session(seconds: 4 * 3_600)
        let track = filled(with: samples)

        #expect(track.sampleCount == samples.count)
        #expect(track.retained.count < samples.count / 10, "pencere budanmamış")
        #expect(track.retained.count >= LiveSessionTrack.minimumRetainedSamples)

        // Everything kept is inside the retention window, and the newest sample is kept.
        #expect(track.retained.last?.elapsedSeconds == samples.last?.elapsedSeconds)
        for sample in track.retained {
            let age = (samples.last?.elapsedSeconds ?? 0) - sample.elapsedSeconds
            #expect(age <= LiveSessionTrack.retainedSeconds)
        }
    }

    @Test("Az örnekli seansta hiçbir şey budanmıyor")
    func aShortSessionKeepsEverything() {
        let samples = (0..<20).map {
            LiveHeartRateSample(elapsedSeconds: Double($0), beatsPerMinute: 140)
        }
        let track = filled(with: samples)
        #expect(track.retained.count == samples.count)
    }
}
