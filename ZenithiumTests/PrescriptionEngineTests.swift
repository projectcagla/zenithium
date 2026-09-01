//
//  PrescriptionEngineTests.swift
//  ZenithiumTests
//
//  The prescription and the plan. The load-bearing assertions are about *decisions*, not
//  arithmetic: that a spike overrides a good morning, that tired legs remove leg sessions,
//  and that every prescription carries its reasons.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Prescription engine")
struct PrescriptionEngineTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func recovery(score: Double, ceiling: Double? = 14) -> RecoveryOutput {
        RecoveryOutput(
            availability: .scored,
            score: score,
            band: RecoveryBand.band(forScore: score),
            targetStrainCeiling: ceiling,
            zTotal: 0,
            confidence: 1,
            drivers: [],
            missingDrivers: [],
            topPositiveDriver: nil,
            topNegativeDriver: nil,
            topPositiveSummary: nil,
            topNegativeSummary: nil
        )
    }

    private func load(ratio: Double) -> TrainingLoadOutput {
        TrainingLoadOutput(
            acuteLoad: 10 * ratio,
            chronicLoad: 10,
            ratio: ratio,
            instantRatio: ratio,
            recentRatios: Array(repeating: ratio, count: 7),
            band: LoadBand.band(forRatio: ratio),
            weekLoad: 70,
            previousWeekLoad: 70,
            rampRate: 0,
            monotony: 1.2,
            fosterStrain: 84,
            fitnessFatigue: FitnessFatigue(fitness: 40, fatigue: 38, form: 2),
            activeDaysInChronicWindow: 16
        )
    }

    private func readiness(_ muscle: MuscleGroup, _ value: Double) -> MuscleReadiness {
        MuscleReadiness(
            muscle: muscle,
            fatigue: 100 - value,
            readiness: value,
            halfLifeHours: 36,
            decayConstant: 0.02,
            dominantSource: nil,
            dominantSourceTimestamp: nil,
            contributingSessionCount: 1
        )
    }

    private func prescribe(
        score: Double,
        lens: TrainingLens = .endurance,
        ratio: Double? = 1.0,
        muscles: [MuscleReadiness] = [],
        strainSoFar: Double = 0
    ) -> Prescription? {
        PrescriptionEngine.prescribe(
            recovery: recovery(score: score),
            lens: lens,
            load: ratio.map { load(ratio: $0) },
            muscles: muscles,
            strainSoFar: strainSoFar,
            biologicalSex: .male,
            criticalSpeed: nil,
            circadian: nil
        )
    }

    // MARK: - Intent

    @Test("Kırmızı sabah dinlenme, yeşil sabah sert seans verir")
    func intentFollowsRecovery() throws {
        let red = try #require(prescribe(score: 30))
        #expect(red.primary.kind == .rest || red.primary.kind == .easyMovement)

        let green = try #require(prescribe(score: 85))
        #expect(green.primary.kind == .intervals || green.primary.kind == .tempo)
    }

    /// A good morning is evidence the body handled yesterday, not evidence the spike was
    /// fine. The ratio may only ever soften the intent.
    @Test("Yük sıçraması iyi sabahı geçersiz kılar")
    func spikeOverridesGoodMorning() throws {
        let normal = try #require(prescribe(score: 85, ratio: 1.0))
        let spiked = try #require(prescribe(score: 85, ratio: 1.6))

        #expect(normal.primary.kind == .intervals)
        #expect(spiked.primary.kind != .intervals, "sıçramada interval verilmemeli")
        #expect(spiked.rationale.contains { $0.contains("eklemiyorum") })
    }

    @Test("Düşük yük oranı niyeti yükseltir")
    func lowRatioRaisesIntent() throws {
        let normal = try #require(prescribe(score: 55, ratio: 1.0))
        let light = try #require(prescribe(score: 55, ratio: 0.6))
        #expect(light.primary.kind != normal.primary.kind)
        #expect(light.rationale.contains { $0.contains("alan var") })
    }

    // MARK: - Muscle constraints

    @Test("Yorgun bacaklar bacak seansını eler")
    func tiredLegsRemoveLegSessions() throws {
        let tired = [readiness(.quads, 35), readiness(.hamstrings, 40)]
        let strength = try #require(prescribe(score: 85, lens: .strength, muscles: tired))
        #expect(strength.primary.kind != .strengthLower)
        #expect(strength.constrainedMuscles.contains(.quads))

        let endurance = try #require(prescribe(score: 85, lens: .endurance, muscles: tired))
        #expect(endurance.primary.kind != .intervals)
    }

    @Test("Dinlenmiş bacaklarda kuvvet merceği alt vücut verir")
    func freshLegsAllowLowerBody() throws {
        let fresh = [readiness(.quads, 92), readiness(.hamstrings, 90)]
        let strength = try #require(prescribe(score: 85, lens: .strength, muscles: fresh))
        #expect(strength.primary.kind == .strengthLower)
        #expect(strength.constrainedMuscles.isEmpty)
    }

    // MARK: - Lens

    /// The same inputs must produce a session each persona recognises. This is the whole
    /// argument for a lens.
    @Test("Aynı girdi her mercekte farklı seans üretir")
    func lensShapesTheSession() throws {
        let endurance = try #require(prescribe(score: 80, lens: .endurance))
        let hybrid = try #require(prescribe(score: 80, lens: .hybrid))
        let strength = try #require(prescribe(score: 80, lens: .strength))
        let health = try #require(prescribe(score: 80, lens: .health))

        #expect(endurance.primary.kind != strength.primary.kind)
        #expect(hybrid.primary.kind != endurance.primary.kind)
        #expect(health.primary.kind == .walk, "sağlık merceğine interval verilmemeli")
    }

    /// "How hard should you push today" is not a question this persona is asking.
    @Test("Sağlık merceği hiçbir zaman sert seans önermez")
    func healthLensNeverPushes() throws {
        for score in [30.0, 55.0, 95.0] {
            let prescription = try #require(prescribe(score: score, lens: .health))
            for session in prescription.everySession {
                #expect(
                    [.rest, .easyMovement, .walk, .easyAerobic].contains(session.kind),
                    "sağlık merceğinde \(session.kind)"
                )
            }
        }
    }

    // MARK: - Forecast

    /// The forecast runs the strain integral backwards, so it must land on the same scale as
    /// the number the user sees at the end of the day.
    @Test("Öngörülen zorlanma tavanın altında kalır")
    func forecastStaysUnderCeiling() throws {
        let prescription = try #require(prescribe(score: 85))
        let ceiling = try #require(prescription.ceiling)
        #expect(prescription.primary.forecastStrain < ceiling)
        #expect(prescription.primary.forecastStrain > 0)
    }

    @Test("Gün içinde biriken zorlanma seansı kısaltır")
    func accumulatedStrainShortensSession() throws {
        let fresh = try #require(prescribe(score: 85, strainSoFar: 0))
        let late = try #require(prescribe(score: 85, strainSoFar: 10))
        #expect(late.primary.minutes < fresh.primary.minutes)
    }

    @Test("Süre beş dakikaya yuvarlanır")
    func minutesAreRounded() throws {
        let prescription = try #require(prescribe(score: 70))
        #expect(prescription.primary.minutes % 5 == 0)
        #expect(prescription.primary.minutes >= 10)
    }

    // MARK: - Rationale

    /// A suggestion nobody can interrogate is a horoscope.
    @Test("Her reçete gerekçesini taşır")
    func alwaysCarriesRationale() throws {
        for score in [25.0, 55.0, 88.0] {
            let prescription = try #require(prescribe(score: score))
            #expect(!prescription.rationale.isEmpty)
            for reason in prescription.rationale {
                #expect(SafetyFilter.isSafe(reason), "\(reason)")
            }
        }
    }

    @Test("Alternatifler sunulur ve birincilden farklıdır")
    func offersAlternatives() throws {
        let prescription = try #require(prescribe(score: 80))
        #expect(!prescription.alternatives.isEmpty)
        #expect(!prescription.alternatives.contains { $0.kind == prescription.primary.kind })
    }

    @Test("Puanlanmamış toparlanmada reçete yok")
    func noPrescriptionWithoutScore() {
        let unavailable = RecoveryOutput(
            availability: .unavailable(.noOvernightData),
            score: nil,
            band: nil,
            targetStrainCeiling: nil,
            zTotal: nil,
            confidence: 0,
            drivers: [],
            missingDrivers: [],
            topPositiveDriver: nil,
            topNegativeDriver: nil,
            topPositiveSummary: nil,
            topNegativeSummary: nil
        )
        #expect(
            PrescriptionEngine.prescribe(
                recovery: unavailable,
                lens: .endurance,
                load: nil,
                muscles: [],
                strainSoFar: 0,
                biologicalSex: .male,
                criticalSpeed: nil,
                circadian: nil
            ) == nil
        )
    }
}

@Suite("Strain inverse")
struct StrainInverseTests {

    /// The forecast is only trustworthy if the inverse is exact.
    @Test("TRIMP ve zorlanma dönüşümü tam geri döner")
    func strainInverseRoundTrips() throws {
        for strain in [1.0, 5.0, 10.0, 14.0, 18.0] {
            let trimp = try #require(StrainEngine.trimp(forStrain: strain))
            #expect(abs(StrainEngine.strain(forTRIMP: trimp) - strain) < 1e-9, "zorlanma \(strain)")
        }
    }

    /// The model says the scale ceiling is approached but never reached, so inventing a
    /// finite answer there would be inventing physiology.
    @Test("Ölçek tavanında ters çözüm yok")
    func inverseIsUndefinedAtCeiling() {
        #expect(StrainEngine.trimp(forStrain: EngineConstants.Strain.scaleMax) == nil)
        #expect(StrainEngine.trimp(forStrain: 25) == nil)
    }

    @Test("Süre ve TRIMP dönüşümü tutarlı")
    func minutesRoundTrip() throws {
        let trimp = StrainEngine.trimp(forMinutes: 55, reserveFraction: 0.5, biologicalSex: .male)
        let minutes = try #require(
            StrainEngine.minutes(forTRIMP: trimp, reserveFraction: 0.5, biologicalSex: .male)
        )
        #expect(abs(minutes - 55) < 1e-9)
    }

    /// 55 minutes at half of reserve is an easy hour: TRIMP 45.97, strain 5.42.
    @Test("Bilinen bir seansın öngörüsü")
    func knownSessionForecast() {
        let trimp = StrainEngine.trimp(forMinutes: 55, reserveFraction: 0.5, biologicalSex: .male)
        #expect(abs(trimp - 45.97) < 0.01)
        #expect(abs(StrainEngine.strain(forTRIMP: trimp) - 5.42) < 0.01)
    }

    @Test("Sıfır şiddette süre çözümü yok")
    func noMinutesAtZeroIntensity() {
        #expect(StrainEngine.minutes(forTRIMP: 50, reserveFraction: 0, biologicalSex: .male) == nil)
    }
}

@Suite("Plan engine")
struct PlanEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    @Test("Faz sınırları", arguments: [
        (84, PlanPhase.base), (60, .base), (40, .build), (25, .sharpen),
        (16, .sharpen), (14, .taper), (1, .taper), (0, .event), (-3, .recovery), (-14, .base)
    ])
    func phaseBoundaries(_ daysRemaining: Int, _ expected: PlanPhase) {
        #expect(
            PlanEngine.phase(daysRemaining: daysRemaining, totalDays: 84, taperDays: 14) == expected,
            "kalan \(daysRemaining)"
        )
    }

    @Test("Tapering süresi türe göre değişir")
    func taperLengthVariesByKind() {
        #expect(GoalEventKind.race.taperDays == 14)
        #expect(GoalEventKind.strengthTest.taperDays == 5)
        #expect(
            PlanEngine.phase(daysRemaining: 10, totalDays: 84, taperDays: 5) != .taper,
            "kuvvet testi 10 gün kala henüz tapering değil"
        )
    }

    /// The whole reason a taper works: fatigue sheds on a seven-day constant and fitness on
    /// a forty-two-day one, so cutting volume lifts form while fitness barely moves.
    @Test("Tapering formu yükseltir, kondisyonu az düşürür")
    func taperLiftsForm() {
        let before = FitnessFatigue(fitness: 60, fatigue: 62, form: -2)
        let after = PlanEngine.taperProjection(
            currentFitness: before.fitness,
            currentFatigue: before.fatigue,
            usualDailyLoad: 12,
            days: 14
        )
        #expect(after.form > before.form)
        #expect(after.fatigue < before.fatigue)
        // Fitness falls too — the point is the ratio of the two falls, not that fitness holds.
        #expect(after.fitness < before.fitness)
    }

    @Test("Önerilen azaltma literatür aralığında")
    func taperReductionIsFromLiterature() {
        #expect(PlanEngine.taperVolumeReduction >= 0.40)
        #expect(PlanEngine.taperVolumeReduction <= 0.60)
    }

    @Test("Konum özeti güvenli ve bilgilendirici")
    func positionSummary() throws {
        let event = GoalEvent(
            kind: .race,
            name: "İstanbul Maratonu",
            date: calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        )
        let position = PlanEngine.position(on: Date(), event: event, calendar: calendar)
        #expect(position.daysRemaining == 30)
        let summary = PlanEngine.summary(for: position)
        #expect(summary.contains("İstanbul Maratonu"))
        #expect(SafetyFilter.isSafe(summary))
    }
}

// MARK: - Cycle context (Yol haritası v4, C6)

/// The cycle may explain a reading. It may never change the session.
///
/// This suite exists mostly to stop a future contributor from "improving" the engine by
/// softening the luteal phase. That is the obvious change and it is the wrong one: the
/// largest review of the question found the effect on performance trivial and hugely
/// variable between people, and §1 rules out an app that quietly prescribes an easier month
/// every month. What the phase legitimately explains is the *signal*, not the capacity.
@Suite("Cycle context never moves the prescription")
struct PrescriptionCycleTests {

    private func context(
        phase: CyclePhase,
        confidence: Double,
        phaseMean: Double?,
        today: Double?
    ) -> CycleContext {
        CycleContext(
            estimate: CyclePhaseEstimate(
                phase: phase,
                dayOfCycle: 20,
                cycleLength: 28,
                confidence: confidence
            ),
            phaseBaselineHRV: phaseMean,
            todayHRV: today
        )
    }

    @Test("Emin olunmayan bir faz hiçbir şey söylemiyor")
    func alowConfidencePhaseSaysNothing() {
        let line = PrescriptionEngine.cycleContextLine(
            cycle: context(phase: .luteal, confidence: 0.3, phaseMean: 60, today: 59),
            band: .yellow
        )
        #expect(line == nil)
    }

    @Test("Yeşil bir sabahta açıklanacak bir şey yok")
    func agreenMorningNeedsNoExplanation() {
        let line = PrescriptionEngine.cycleContextLine(
            cycle: context(phase: .luteal, confidence: 0.9, phaseMean: 60, today: 61),
            band: .green
        )
        #expect(line == nil)
    }

    @Test("Faz ortalamasının civarındaki bir gün olağan diye anlatılıyor")
    func atypicalDayIsExplained() throws {
        let line = try #require(
            PrescriptionEngine.cycleContextLine(
                cycle: context(phase: .luteal, confidence: 0.9, phaseMean: 60, today: 58),
                band: .yellow
            )
        )
        #expect(line.contains("olağan"))
        // The point of the line: it says the morning is ordinary, not that anything is wrong.
        for word in ["kötü", "düşük toparlanma", "dinlen", "azalt"] {
            #expect(!line.lowercased().contains(word), "\(word)")
        }
    }

    @Test("Faz ortalamasından uzak bir gün faza yıkılmıyor")
    func anatypicalDayIsNotExplainedAway() throws {
        let line = try #require(
            PrescriptionEngine.cycleContextLine(
                cycle: context(phase: .luteal, confidence: 0.9, phaseMean: 60, today: 40),
                band: .red
            )
        )
        #expect(line.contains("açıklamıyor"))
    }

    @Test("Faz geçmişi yoksa iddia edilmiyor")
    func withoutHistoryNoClaimIsMade() throws {
        let line = try #require(
            PrescriptionEngine.cycleContextLine(
                cycle: context(phase: .luteal, confidence: 0.9, phaseMean: nil, today: 55),
                band: .yellow
            )
        )
        #expect(line.contains("yeterli geçmiş yok"))
    }

    @Test(
        "Faz, seansı hiçbir bantta değiştirmiyor",
        arguments: [40.0, 55.0, 62.0, 78.0, 91.0]
    )
    func thephaseNeverMovesTheSession(score: Double) throws {
        let recovery = RecoveryOutput(
            availability: .scored,
            score: score,
            band: RecoveryBand.band(forScore: score),
            targetStrainCeiling: 14,
            zTotal: 0,
            confidence: 1,
            drivers: [],
            missingDrivers: [],
            topPositiveDriver: nil,
            topNegativeDriver: nil,
            topPositiveSummary: nil,
            topNegativeSummary: nil
        )
        func run(_ cycle: CycleContext?) -> Prescription? {
            PrescriptionEngine.prescribe(
                recovery: recovery,
                lens: .endurance,
                load: nil,
                muscles: [],
                strainSoFar: 0,
                biologicalSex: .female,
                criticalSpeed: nil,
                circadian: nil,
                cycle: cycle
            )
        }

        let without = try #require(run(nil))
        for phase in CyclePhase.allCases {
            let with = try #require(
                run(context(phase: phase, confidence: 0.95, phaseMean: 60, today: 59))
            )
            #expect(with.primary == without.primary, "\(phase) birincil seansı değiştirdi")
            #expect(with.alternatives == without.alternatives, "\(phase) alternatifleri değiştirdi")
            #expect(with.ceiling == without.ceiling, "\(phase) tavanı değiştirdi")
            // Only the rationale may differ, and only by gaining a line.
            #expect(with.rationale.count >= without.rationale.count)
            #expect(with.rationale.prefix(without.rationale.count).elementsEqual(without.rationale))
        }
    }

    @Test(
        "Hiçbir faz için satır bir emir içermiyor",
        arguments: CyclePhase.allCases
    )
    func nolineInstructs(phase: CyclePhase) {
        for band in [RecoveryBand.red, .yellow] {
            for mean in [Double?.some(60), nil] {
                let line = PrescriptionEngine.cycleContextLine(
                    cycle: context(phase: phase, confidence: 0.9, phaseMean: mean, today: 58),
                    band: band
                )
                guard let line else { continue }
                // §1 — no restriction prompt, in any phase, on any band.
                for word in ["dinlen", "azalt", "yavaşla", "atla", "vazgeç", "bırak"] {
                    #expect(!line.lowercased().contains(word), "\(phase)/\(band): \(word)")
                }
            }
        }
    }
}
