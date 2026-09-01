//
//  StrengthEngineTests.swift
//  ZenithiumTests
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Strength engine")
struct StrengthEngineTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func entry(_ name: String, sets: Int, reps: Int, weight: Double?) -> StrengthEntry {
        StrengthEntry(id: UUID(), exerciseName: name, sets: sets, reps: reps, rpe: 8, weightKilograms: weight)
    }

    private func session(
        _ pattern: MovementPattern,
        _ entries: [StrengthEntry],
        daysAgo: Int
    ) -> StrengthSessionSnapshot {
        StrengthSessionSnapshot(
            id: UUID(),
            performedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            timeZoneIdentifier: "UTC",
            pattern: pattern,
            entries: entries,
            sessionLoad: 40,
            note: "",
            engineVersion: 1
        )
    }

    // MARK: - One-rep maximum

    /// 100 kg × 5 gives Epley 116.67 and Brzycki 112.50; their mean is 114.583.
    @Test("Epley ve Brzycki ortalaması")
    func estimatesOneRepMax() throws {
        let estimate = try #require(StrengthEngine.estimateOneRepMax(weight: 100, reps: 5))
        #expect(abs(estimate - 114.583) < 0.01)
    }

    /// A single at 100 kg is a 100 kg maximum. Without the guard the mean of the two
    /// formulas returns 101.67, which would report progress that did not happen.
    @Test("Tek tekrar ağırlığın kendisidir")
    func singleRepIsTheWeight() {
        #expect(StrengthEngine.estimateOneRepMax(weight: 100, reps: 1) == 100)
    }

    @Test("Geçersiz girdilerde tahmin yok")
    func rejectsInvalidInput() {
        #expect(StrengthEngine.estimateOneRepMax(weight: 0, reps: 5) == nil)
        #expect(StrengthEngine.estimateOneRepMax(weight: 100, reps: 0) == nil)
        // Brzycki'nin paydası 37 tekrarda sıfırlanır.
        #expect(StrengthEngine.estimateOneRepMax(weight: 100, reps: 40) == nil)
    }

    @Test("Yüksek tekrarda tahmin güvenilmez işaretlenir")
    func flagsHighRepEstimates() throws {
        let sessions = [session(.push, [entry("Bench", sets: 3, reps: 15, weight: 60)], daysAgo: 2)]
        let estimate = try #require(StrengthEngine.oneRepMaxes(from: sessions, now: now).first)
        #expect(!estimate.isReliable)
    }

    /// The previous best must come from an earlier *day*, not simply the second-highest set —
    /// otherwise a heavy triple reports progress against the warm-up set before it.
    @Test("Önceki en iyi, daha erken bir günden gelir")
    func previousBestIsFromAnEarlierDay() throws {
        let sessions = [
            session(.push, [entry("Bench", sets: 1, reps: 5, weight: 90)], daysAgo: 30),
            session(.push, [
                entry("Bench", sets: 1, reps: 5, weight: 95),
                entry("Bench", sets: 1, reps: 5, weight: 100)
            ], daysAgo: 2)
        ]
        let estimate = try #require(StrengthEngine.oneRepMaxes(from: sessions, now: now).first)
        #expect(abs(estimate.weight - 100) < 1e-9)
        let previous = try #require(estimate.previousEstimate)
        // 90 kg × 5 = 103.125, not the 95 kg set from the same session.
        #expect(abs(previous - 103.125) < 0.01)
        let change = try #require(estimate.change)
        #expect(change > 0.10)
    }

    @Test("Yazım farkları tek egzersizde toplanır")
    func foldsSpellingVariants() {
        let sessions = [
            session(.push, [entry("Bench Press", sets: 1, reps: 5, weight: 90)], daysAgo: 20),
            session(.push, [entry("bench press", sets: 1, reps: 5, weight: 100)], daysAgo: 2)
        ]
        let estimates = StrengthEngine.oneRepMaxes(from: sessions, now: now)
        #expect(estimates.count == 1)
        #expect(estimates.first?.previousEstimate != nil)
    }

    @Test("Ağırlıksız kayıtlar 1TM üretmez")
    func skipsEntriesWithoutWeight() {
        let sessions = [session(.push, [entry("Şınav", sets: 4, reps: 20, weight: nil)], daysAgo: 1)]
        #expect(StrengthEngine.oneRepMaxes(from: sessions, now: now).isEmpty)
    }

    // MARK: - Volume

    /// A set is not one set for every muscle it touches — each is weighted by involvement,
    /// so a squat is a full set for the quadriceps and a fraction for the calves.
    @Test("Hacim katılım payıyla ağırlıklandırılır")
    func volumeIsWeightedByInvolvement() throws {
        let sessions = [session(.squat, [entry("Back squat", sets: 5, reps: 5, weight: 100)], daysAgo: 1)]
        let volume = StrengthEngine.weeklyVolume(from: sessions, now: now)

        let quads = try #require(volume.first { $0.muscle == .quads })
        let involvement = MuscleInvolvementMatrix.involvement(for: .squat)
        let expected = 5 * (involvement[.quads] ?? 0)
        #expect(abs(quads.sets - expected) < 1e-9)

        // Anything below the counting threshold must not appear at all.
        for row in volume {
            #expect((involvement[row.muscle] ?? 0) >= StrengthEngine.setCountingThreshold)
        }
    }

    @Test("Pencere dışındaki seanslar hacme girmez")
    func volumeRespectsWindow() {
        let sessions = [session(.squat, [entry("Back squat", sets: 5, reps: 5, weight: 100)], daysAgo: 20)]
        #expect(StrengthEngine.weeklyVolume(from: sessions, now: now).isEmpty)
    }

    @Test("Hacim bantları")
    func volumeBands() {
        #expect(WeeklyVolume(muscle: .chest, sets: 3).band == .minimal)
        #expect(WeeklyVolume(muscle: .chest, sets: 8).band == .maintenance)
        #expect(WeeklyVolume(muscle: .chest, sets: 14).band == .productive)
        #expect(WeeklyVolume(muscle: .chest, sets: 24).band == .high)
    }

    // MARK: - Balance

    @Test("İtme/çekme oranı ve özeti")
    func pushPullBalance() throws {
        let sessions = [
            session(.push, [entry("Bench", sets: 12, reps: 8, weight: 80)], daysAgo: 2),
            session(.pull, [entry("Row", sets: 4, reps: 8, weight: 70)], daysAgo: 3)
        ]
        let balance = StrengthEngine.balance(from: sessions, now: now)
        let ratio = try #require(balance.pushPullRatio)
        #expect(abs(ratio - 3.0) < 1e-9)
        let summary = try #require(balance.summary)
        #expect(summary.contains("İtme hacmin"))
    }

    @Test("Çekme yoksa oran üretilmez")
    func noPullMeansNoRatio() {
        let sessions = [session(.push, [entry("Bench", sets: 6, reps: 8, weight: 80)], daysAgo: 2)]
        let balance = StrengthEngine.balance(from: sessions, now: now)
        #expect(balance.pushPullRatio == nil)
        #expect(balance.summary == nil)
    }

    // MARK: - Deload

    /// Any one of these is an ordinary hard week; it is their coincidence that means
    /// something, so a single reason must not trigger.
    @Test("Tek gerekçe deload sinyali vermez")
    func singleReasonDoesNotTrigger() {
        let signal = StrengthEngine.deloadSignal(
            volume: [WeeklyVolume(muscle: .chest, sets: 26)],
            recoveryScores: [80, 82, 79, 85, 81],
            muscleReadiness: [90, 88, 92],
            loadRatio: 1.0
        )
        #expect(!signal.isTriggered)
        #expect(signal.summary == nil)
    }

    @Test("İki gerekçe birlikte sinyal verir")
    func twoReasonsTrigger() throws {
        let signal = StrengthEngine.deloadSignal(
            volume: [
                WeeklyVolume(muscle: .chest, sets: 26),
                WeeklyVolume(muscle: .quads, sets: 24),
                WeeklyVolume(muscle: .lats, sets: 22)
            ],
            recoveryScores: [50, 55, 48, 60, 52],
            muscleReadiness: [40, 45, 38],
            loadRatio: 1.4
        )
        #expect(signal.isTriggered)
        #expect(signal.reasons.count == 4)
        let summary = try #require(signal.summary)
        #expect(SafetyFilter.isSafe(summary))
    }
}
