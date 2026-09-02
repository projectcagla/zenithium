//
//  StrainEngineTests.swift
//  ZenithiumTests
//
//  Spec §11 golden vector 2, the §5.3 calibration anchors, the gap rules and monotonicity.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Strain engine")
struct StrainEngineTests {

    private let start = iso("2025-06-01T06:00:00Z")

    private func input(
        samples: [HeartRateSample],
        restingHeartRate: Double = 50,
        maxHeartRate: Double = 190,
        sex: BiologicalSexValue = .female,
        anchor: StrainAnchor? = nil,
        previous: Double? = nil,
        recovery: Double? = nil
    ) -> StrainInput {
        StrainInput(
            samples: samples,
            dayWindow: testDayWindow(start: start),
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            maxHeartRateSource: .observed,
            biologicalSex: sex,
            anchor: anchor,
            previouslyReportedStrain: previous,
            recoveryScore: recovery
        )
    }

    // MARK: - §11 golden vector 2

    @Test("Golden vector 2 — 30 minutes at 150 bpm, female constants")
    func goldenStrain() {
        let samples = steadyHeartRateSeries(start: start, minutes: 30, beatsPerMinute: 150)
        let output = StrainEngine.compute(input(samples: samples))

        // x = (150 − 50) / (190 − 50)
        expectClose(100.0 / 140.0, 0.714286, tolerance: GoldenTolerance.tight, "x")
        expectClose(output.trimp, 60.75, "TRIMP")
        expectClose(output.strain, 6.85, "Strain")
        #expect(output.contributingSampleCount == 30)
    }

    @Test("Sex selects the Banister constants")
    func sexSelectsConstants() {
        #expect(BiologicalSexValue.male.trimpConstants.b == 0.64)
        #expect(BiologicalSexValue.male.trimpConstants.c == 1.92)
        for sex in [BiologicalSexValue.female, .other, .notSet] {
            #expect(sex.trimpConstants.b == 0.86)
            #expect(sex.trimpConstants.c == 1.67)
        }
    }

    // MARK: - §5.3 calibration anchors

    @Test(
        "Calibration anchors reproduce to ±0.1",
        arguments: [(65.0, 7.2), (135.0, 12.3), (200.0, 15.3), (365.0, 19.0), (500.0, 20.2)]
    )
    func calibrationAnchors(trimp: Double, expected: Double) {
        expectClose(
            StrainEngine.strain(forTRIMP: trimp),
            expected,
            tolerance: GoldenTolerance.strainAnchor,
            "strain at TRIMP \(trimp)"
        )
    }

    @Test("Strain is bounded by the 21-point scale and monotonic in TRIMP")
    func strainIsBoundedAndMonotonic() {
        var previous = -1.0
        for trimp in stride(from: 0.0, through: 2000.0, by: 10.0) {
            let strain = StrainEngine.strain(forTRIMP: trimp)
            #expect(strain >= previous)
            #expect(strain <= EngineConstants.Strain.scaleMax)
            previous = strain
        }
    }

    // MARK: - §5.3 gap rules

    @Test("A gap longer than 120 seconds contributes nothing")
    func longGapsContributeNothing() {
        let samples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 150, sourceBundleIdentifier: nil),
            HeartRateSample(timestamp: start.addingTimeInterval(60), beatsPerMinute: 150, sourceBundleIdentifier: nil),
            // A five-minute hole: the sample after it opens a new segment.
            HeartRateSample(timestamp: start.addingTimeInterval(360), beatsPerMinute: 150, sourceBundleIdentifier: nil),
            HeartRateSample(timestamp: start.addingTimeInterval(420), beatsPerMinute: 150, sourceBundleIdentifier: nil)
        ]
        let output = StrainEngine.compute(input(samples: samples))
        // Two 60-second segments contribute; the 300-second hole does not.
        #expect(output.contributingSampleCount == 2)
        expectClose(output.uncoveredSeconds, 300, tolerance: 1e-9, "uncovered seconds")
    }

    @Test("A segment is clamped to 60 seconds")
    func segmentsAreClamped() {
        let clampedSamples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 150, sourceBundleIdentifier: nil),
            // 90 seconds: inside the 120 s cut-off, so it counts — but only 60 s of it.
            HeartRateSample(timestamp: start.addingTimeInterval(90), beatsPerMinute: 150, sourceBundleIdentifier: nil)
        ]
        let oneMinute = [
            HeartRateSample(timestamp: start, beatsPerMinute: 150, sourceBundleIdentifier: nil),
            HeartRateSample(timestamp: start.addingTimeInterval(60), beatsPerMinute: 150, sourceBundleIdentifier: nil)
        ]
        let clamped = StrainEngine.compute(input(samples: clampedSamples))
        let exact = StrainEngine.compute(input(samples: oneMinute))
        expectClose(clamped.trimp, exact.trimp, tolerance: 1e-9, "90 s clamps to the 60 s value")
    }

    @Test("Implausible samples are dropped rather than clamped")
    func implausibleSamplesDropped() {
        let samples = [
            HeartRateSample(timestamp: start, beatsPerMinute: 150, sourceBundleIdentifier: nil),
            HeartRateSample(timestamp: start.addingTimeInterval(60), beatsPerMinute: 900, sourceBundleIdentifier: nil),
            HeartRateSample(timestamp: start.addingTimeInterval(120), beatsPerMinute: 150, sourceBundleIdentifier: nil)
        ]
        let output = StrainEngine.compute(input(samples: samples))
        // The artefact is gone, leaving a 120 s span whose single surviving segment is
        // clamped to 60 s.
        #expect(output.contributingSampleCount == 1)
    }

    // MARK: - §5.3 monotonicity

    @Test("A recompute never lowers a value already shown")
    func strainIsMonotonicWithinADay() {
        let samples = steadyHeartRateSeries(start: start, minutes: 30, beatsPerMinute: 150)
        let full = StrainEngine.compute(input(samples: samples))

        // A later pass that sees fewer samples — HealthKit deleted some — must not drop the
        // number the user already saw.
        let fewer = Array(samples.prefix(10))
        let recomputed = StrainEngine.compute(
            input(samples: fewer, previous: full.strain)
        )
        #expect(recomputed.strain >= full.strain)
        #expect(recomputed.wasClampedToPreviousValue)
    }

    @Test("An anchor resumes rather than restarting")
    func anchorResumes() {
        let first = steadyHeartRateSeries(start: start, minutes: 15, beatsPerMinute: 150)
        let firstPass = StrainEngine.compute(input(samples: first))

        let second = steadyHeartRateSeries(
            start: start.addingTimeInterval(15 * 60),
            minutes: 15,
            beatsPerMinute: 150
        )
        let secondPass = StrainEngine.compute(
            input(samples: second, anchor: firstPass.anchor, previous: firstPass.strain)
        )

        // Resuming from the anchor reaches the same place as computing the whole day at once.
        let whole = StrainEngine.compute(
            input(samples: steadyHeartRateSeries(start: start, minutes: 30, beatsPerMinute: 150))
        )
        expectClose(secondPass.trimp, whole.trimp, tolerance: 0.01, "resumed TRIMP")
    }

    // MARK: - §15 rule 8

    @Test("A degenerate heart-rate reserve cannot divide by zero")
    func degenerateReserveIsGuarded() {
        let samples = steadyHeartRateSeries(start: start, minutes: 10, beatsPerMinute: 150)
        let output = StrainEngine.compute(
            input(samples: samples, restingHeartRate: 190, maxHeartRate: 190)
        )
        #expect(output.strain.isFinite)
        #expect(output.trimp.isFinite)
    }

    @Test("An empty series produces zero, not a crash")
    func emptySeries() {
        let output = StrainEngine.compute(input(samples: []))
        #expect(output.strain == 0)
        #expect(output.trimp == 0)
        #expect(output.contributingSampleCount == 0)
    }

    // MARK: - ASSUMPTION ZONE-1

    @Test("Zone boundaries partition the reserve")
    func zonesPartitionReserve() {
        #expect(HeartRateZone.zone(forReserveFraction: 0.00) == .zone1)
        #expect(HeartRateZone.zone(forReserveFraction: 0.19) == .zone1)
        #expect(HeartRateZone.zone(forReserveFraction: 0.20) == .zone2)
        #expect(HeartRateZone.zone(forReserveFraction: 0.45) == .zone3)
        #expect(HeartRateZone.zone(forReserveFraction: 0.75) == .zone4)
        #expect(HeartRateZone.zone(forReserveFraction: 0.85) == .zone5)
        #expect(HeartRateZone.zone(forReserveFraction: 0.95) == .zone6)
        #expect(HeartRateZone.zone(forReserveFraction: 1.00) == .zone6)
    }

    @Test("Zone seconds are recorded against the right band")
    func zoneSecondsRecorded() {
        // x = 0.714 lands in zone 4 (60–80% of reserve).
        let samples = steadyHeartRateSeries(start: start, minutes: 30, beatsPerMinute: 150)
        let output = StrainEngine.compute(input(samples: samples))
        expectClose(output.seconds(in: .zone4), 1800, tolerance: 1, "zone 4 seconds")
        expectClose(output.zoneSeconds.reduce(0, +), 1800, tolerance: 1, "total zone seconds")
    }

    // MARK: - §5.3 HRmax resolution

    @Test("A user override wins")
    func overrideWins() {
        let resolved = StrainEngine.resolveMaxHeartRate(override: 195, observed: 210, age: 30)
        #expect(resolved.value == 195)
        #expect(resolved.source == .userOverride)
    }

    @Test("Without an override, the higher of observed and Tanaka wins")
    func observedVersusTanaka() {
        // Tanaka at 40 is 208 − 28 = 180.
        let observedWins = StrainEngine.resolveMaxHeartRate(override: nil, observed: 192, age: 40)
        #expect(observedWins.source == .observed)
        expectClose(observedWins.value, 192, tolerance: 1e-9, "observed")

        let tanakaWins = StrainEngine.resolveMaxHeartRate(override: nil, observed: 170, age: 40)
        #expect(tanakaWins.source == .tanaka)
        expectClose(tanakaWins.value, 180, tolerance: 1e-9, "Tanaka at 40")
    }

    @Test("With no age, Tanaka assumes 35 and says so (HRMAX-1)")
    func assumedAge() {
        let resolved = StrainEngine.resolveMaxHeartRate(override: nil, observed: nil, age: nil)
        expectClose(resolved.value, 183.5, tolerance: 1e-9, "Tanaka at the assumed age")
        #expect(resolved.source == .tanakaAssumedAge)
        #expect(resolved.source.invitesCorrection)
    }

    // MARK: - §5.4 session load

    @Test("Logged strength load is volume ÷ 3, capped at 100")
    func strengthSessionLoad() {
        expectClose(StrainEngine.sessionLoad(forVolumeLoad: 150), 50, tolerance: 1e-9, "150 → 50")
        expectClose(StrainEngine.sessionLoad(forVolumeLoad: 600), 100, tolerance: 1e-9, "capped at 100")
        expectClose(StrainEngine.sessionLoad(forVolumeLoad: 0), 0, tolerance: 1e-9, "zero volume")
    }

    // MARK: - StressEngine.recoverySummary

    @Test("Stres toparlanma özeti sakin blok olduğunda ve olmadığında doğru üretilir")
    func stressRecoverySummaryFormats() {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = Date(timeIntervalSince1970: 1_780_000_000)

        let withRecovery = StressDay(
            intervals: [],
            trainingLoad: 10,
            nonTrainingLoad: 20,
            recoveryWindows: [RecoveryWindow(start: dayStart.addingTimeInterval(3600), end: dayStart.addingTimeInterval(6000), heartRate: 55)],
            secondsByBand: [:]
        )
        let summaryWith = StressEngine.recoverySummary(for: withRecovery, calendar: calendar)
        #expect(summaryWith != nil)
        #expect(summaryWith?.contains("Günün en sakin bloğu") == true)
        #expect(summaryWith?.contains("40 dakika sürdü") == true)

        let withoutRecovery = StressDay(
            intervals: [],
            trainingLoad: 10,
            nonTrainingLoad: 20,
            recoveryWindows: [],
            secondsByBand: [:]
        )
        let summaryWithout = StressEngine.recoverySummary(for: withoutRecovery, calendar: calendar)
        #expect(summaryWithout == "Bugün nabzın dinlenik seviyeye uzun süre inmedi.")
    }
}
