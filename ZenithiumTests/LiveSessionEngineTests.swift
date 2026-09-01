//
//  LiveSessionEngineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C1 — where the session stands while it is still running.
//
//  The test that matters most is `impulseAddsRatherThanStrain`. Strain saturates, so adding
//  this morning's strain to this session's strain overstates the day — by about fifteen per
//  cent in the ordinary case below. That is a number someone would read mid-run and believe.
//  Everything else here is guarding the edges: gaps in the trace, an empty session, a
//  projection that should refuse to be made.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Live session")
struct LiveSessionEngineTests {

    private let resting: Double = 50
    private let maximum: Double = 190

    /// A steady session at a fixed fraction of reserve, sampled every five seconds.
    private func input(
        minutes: Double,
        reserveFraction: Double,
        strainBefore: Double = 0,
        ceiling: Double? = nil,
        sex: BiologicalSexValue = .male
    ) -> LiveSessionInput {
        let beats = resting + (maximum - resting) * reserveFraction
        let seconds = minutes * 60
        let samples = stride(from: 0.0, through: seconds, by: 5).map {
            LiveHeartRateSample(elapsedSeconds: $0, beatsPerMinute: beats)
        }
        return LiveSessionInput(
            elapsedSeconds: seconds,
            samples: samples,
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: sex,
            strainBeforeSession: strainBefore,
            ceiling: ceiling
        )
    }

    // MARK: - The one that matters

    @Test("Toplanan şey zorlanma değil, dürtü")
    func impulseAddsRatherThanStrain() throws {
        // Forty-five minutes at 75% of reserve, on top of a morning that already read 4.0.
        let output = LiveSessionEngine.evaluate(
            input(minutes: 45, reserveFraction: 0.75, strainBefore: 4.0)
        )

        // The correct answer maps the summed impulse once.
        let priorTRIMP = try #require(StrainScale.trimp(forStrain: 4.0))
        let expected = StrainScale.strain(forTRIMP: priorTRIMP + output.sessionTRIMP)
        #expect(abs(output.dayStrain - expected) < 0.001)

        // Adding the two strains would be higher, and wrong. This is the assertion that
        // stops someone "simplifying" the engine back into a bug.
        let naive = 4.0 + StrainScale.strain(forTRIMP: output.sessionTRIMP)
        #expect(naive > output.dayStrain + 1)
    }

    @Test("Seansın kendi katkısı gün toplamından çıkarılabiliyor")
    func theSessionsOwnContributionIsReported() {
        let output = LiveSessionEngine.evaluate(
            input(minutes: 30, reserveFraction: 0.7, strainBefore: 6.0)
        )
        #expect(abs(output.strainAddedBySession - (output.dayStrain - 6.0)) < 0.001)
        #expect(output.strainAddedBySession > 0)
    }

    // MARK: - Impulse

    @Test("Sabit efor, kapalı formdaki dürtüyle eşleşiyor")
    func steadyEffortMatchesTheClosedForm() {
        let minutes = 40.0
        let fraction = 0.68
        let output = LiveSessionEngine.evaluate(input(minutes: minutes, reserveFraction: fraction))
        let closedForm = StrainScale.trimp(
            forMinutes: minutes,
            reserveFraction: fraction,
            biologicalSex: .male
        )
        // The trapezoid rule on a constant integrand is exact.
        #expect(abs(output.sessionTRIMP - closedForm) < 0.01)
    }

    @Test("Daha sıkı efor daha çok dürtü biriktiriyor")
    func harderEffortAccumulatesFaster() {
        let easy = LiveSessionEngine.evaluate(input(minutes: 30, reserveFraction: 0.5))
        let hard = LiveSessionEngine.evaluate(input(minutes: 30, reserveFraction: 0.85))
        #expect(hard.sessionTRIMP > easy.sessionTRIMP)
        #expect(hard.dayStrain > easy.dayStrain)
    }

    @Test("Nabız verisi yoksa hiçbir şey uydurulmuyor")
    func noSamplesMeansNoStrain() {
        let empty = LiveSessionInput(
            elapsedSeconds: 600,
            samples: [],
            restingHeartRate: resting,
            maxHeartRate: maximum,
            biologicalSex: .male,
            strainBeforeSession: 3,
            ceiling: 14
        )
        let output = LiveSessionEngine.evaluate(empty)
        #expect(output.sessionTRIMP == 0)
        #expect(abs(output.dayStrain - 3) < 0.001)
        #expect(output.currentReserveFraction == 0)
    }

    @Test("Kayıt boşluğu köprülenmiyor")
    func aGapIsNotBridged() {
        // Two minutes of running, four minutes of nothing, two minutes more. The middle must
        // not be integrated as if the watch had kept reading.
        let beats = resting + (maximum - resting) * 0.8
        let samples =
            stride(from: 0.0, through: 120.0, by: 5).map {
                LiveHeartRateSample(elapsedSeconds: $0, beatsPerMinute: beats)
            }
            + stride(from: 360.0, through: 480.0, by: 5).map {
                LiveHeartRateSample(elapsedSeconds: $0, beatsPerMinute: beats)
            }

        let withGap = LiveSessionEngine.evaluate(
            LiveSessionInput(
                elapsedSeconds: 480,
                samples: samples,
                restingHeartRate: resting,
                maxHeartRate: maximum,
                biologicalSex: .male,
                strainBeforeSession: 0,
                ceiling: nil
            )
        )
        let fourMinutes = LiveSessionEngine.evaluate(input(minutes: 4, reserveFraction: 0.8))
        // Four minutes of readings either way, so the impulse should match — the gap adds
        // nothing rather than adding four minutes of the last known beat.
        #expect(abs(withGap.sessionTRIMP - fourMinutes.sessionTRIMP) < 0.5)
    }

    // MARK: - Ceiling

    @Test("Tavan ilerlemesi gün zorlanmasının tavana oranı")
    func ceilingProgressIsTheRatio() throws {
        let output = LiveSessionEngine.evaluate(
            input(minutes: 30, reserveFraction: 0.7, strainBefore: 2, ceiling: 14)
        )
        let progress = try #require(output.ceilingProgress)
        #expect(abs(progress - output.dayStrain / 14) < 0.001)
    }

    @Test("Tavan yoksa ilerleme de yok")
    func noCeilingMeansNoProgress() {
        let output = LiveSessionEngine.evaluate(input(minutes: 20, reserveFraction: 0.6))
        #expect(output.ceilingProgress == nil)
        #expect(output.band == .unbounded)
        #expect(output.secondsToCeiling == nil)
    }

    @Test(
        "Bantlar ilerlemeye göre",
        arguments: [
            (0.0, LiveSessionBand.building),
            (0.5, LiveSessionBand.building),
            (0.84, LiveSessionBand.building),
            (0.85, LiveSessionBand.nearing),
            (0.99, LiveSessionBand.nearing),
            (1.0, LiveSessionBand.beyond),
            (1.4, LiveSessionBand.beyond)
        ]
    )
    func bandsFollowProgress(progress: Double, expected: LiveSessionBand) {
        #expect(LiveSessionEngine.band(forProgress: progress) == expected)
    }

    @Test("Her bandın söyleyecek bir cümlesi var, hiçbiri emir vermiyor")
    func everyBandExplainsItself() {
        for band in LiveSessionBand.allCases {
            #expect(!band.displayName.isEmpty)
            #expect(!band.summary.isEmpty)
            // §12 and §1: this screen is read mid-effort. It reports; it does not instruct.
            for word in ["dur", "durmalı", "bırak", "yavaşla", "kes"] {
                #expect(!band.summary.lowercased().contains(word), "\(band): \(word)")
            }
        }
    }

    // MARK: - Projection

    @Test("Tavana kalan süre mevcut hızdan çıkıyor")
    func projectionUsesTheCurrentRate() throws {
        let output = LiveSessionEngine.evaluate(
            input(minutes: 20, reserveFraction: 0.75, strainBefore: 0, ceiling: 14)
        )
        let seconds = try #require(output.secondsToCeiling)
        #expect(seconds > 0)
        #expect(seconds <= LiveSessionEngine.maximumProjectionSeconds)

        // Sanity: at this rate the ceiling should be a sensible number of further minutes,
        // not a number of days.
        #expect(seconds < 2 * 3_600)
    }

    @Test("Hafif efor tavana hiç varmıyorsa süre bildirilmiyor")
    func anEasyEffortReportsNoProjection() {
        // A gentle jog does not reach a hard day's ceiling eventually; it never reaches it,
        // and "5 saat" would be arithmetic pretending to be advice.
        let output = LiveSessionEngine.evaluate(
            input(minutes: 20, reserveFraction: 0.35, strainBefore: 0, ceiling: 18)
        )
        #expect(output.secondsToCeiling == nil)
    }

    @Test("Tavan geçilmişse süre bildirilmiyor")
    func passingTheCeilingEndsTheProjection() {
        let output = LiveSessionEngine.evaluate(
            input(minutes: 90, reserveFraction: 0.85, strainBefore: 6, ceiling: 10)
        )
        #expect(output.secondsToCeiling == nil)
        #expect(output.band == .beyond)
    }

    @Test("Doymuş bir gün sıfırlanmıyor")
    func asaturatedDayIsNotErased() {
        // The inversion has no answer at the scale ceiling. Falling back to zero there would
        // show someone who has already had an enormous day a strain of nearly nothing.
        let output = LiveSessionEngine.evaluate(
            input(minutes: 10, reserveFraction: 0.7, strainBefore: 21, ceiling: 14)
        )
        #expect(output.dayStrain >= 20.9)
        #expect(output.secondsToCeiling == nil)
        #expect(output.band == .beyond)
    }

    // MARK: - Reserve

    @Test("Anlık ve ortalama rezerv oranı doğru")
    func reserveFractionsAreCorrect() {
        let output = LiveSessionEngine.evaluate(input(minutes: 10, reserveFraction: 0.6))
        #expect(abs(output.currentReserveFraction - 0.6) < 0.001)
        #expect(abs(output.averageReserveFraction - 0.6) < 0.001)
    }

    @Test("Dinlenme nabzının altındaki değerler sıfıra kırpılıyor")
    func belowRestingClampsToZero() {
        let samples = stride(from: 0.0, through: 300.0, by: 5).map {
            LiveHeartRateSample(elapsedSeconds: $0, beatsPerMinute: 42)
        }
        let output = LiveSessionEngine.evaluate(
            LiveSessionInput(
                elapsedSeconds: 300,
                samples: samples,
                restingHeartRate: resting,
                maxHeartRate: maximum,
                biologicalSex: .male,
                strainBeforeSession: 0,
                ceiling: nil
            )
        )
        #expect(output.currentReserveFraction == 0)
        #expect(output.sessionTRIMP == 0)
    }
}
