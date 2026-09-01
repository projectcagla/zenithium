//
//  CycleEngineTests.swift
//  ZenithiumTests
//
//  Phase estimation and phase-aware baselines. The §12 boundary is tested as hard as the
//  arithmetic: this engine must never produce fertility or diagnosis language.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Cycle engine")
struct CycleEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    private var origin: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8)) ?? Date()
    }

    private func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: origin) ?? origin)
    }

    /// `cycles` consecutive 28-day cycles with five bleeding days each.
    private func flowDays(cycles: Int, length: Int = 28) -> [MenstrualFlowDay] {
        var result: [MenstrualFlowDay] = []
        for cycle in 0..<cycles {
            for bleedingDay in 0..<5 {
                let offset = cycle * length + bleedingDay
                result.append(MenstrualFlowDay(dayStart: day(offset), isCycleStart: bleedingDay == 0))
            }
        }
        return result
    }

    // MARK: - Cycle starts

    @Test("Ardışık kanama günleri tek döngü başlangıcı sayılır")
    func consecutiveDaysAreOnePeriod() {
        let starts = CycleEngine.cycleStarts(from: flowDays(cycles: 3), calendar: calendar)
        #expect(starts.count == 3)
        #expect(starts.first == day(0))
        #expect(starts.last == day(56))
    }

    /// A one-day gap in logging is far more often a missed entry than a second period.
    @Test("Bir günlük boşluk yeni döngü başlatmaz")
    func shortGapDoesNotStartNewCycle() {
        let days = [
            MenstrualFlowDay(dayStart: day(0), isCycleStart: true),
            MenstrualFlowDay(dayStart: day(1), isCycleStart: false),
            MenstrualFlowDay(dayStart: day(3), isCycleStart: false)
        ]
        #expect(CycleEngine.cycleStarts(from: days, calendar: calendar).count == 1)
    }

    @Test("Ölçülen döngü uzunluğu")
    func measuresCycleLength() throws {
        let starts = CycleEngine.cycleStarts(from: flowDays(cycles: 4, length: 30), calendar: calendar)
        let length = try #require(CycleEngine.measuredCycleLength(starts: starts, calendar: calendar))
        #expect(length == 30)
    }

    @Test("Tek döngüden uzunluk ölçülmez")
    func requiresSeveralCyclesForLength() {
        let starts = CycleEngine.cycleStarts(from: flowDays(cycles: 2), calendar: calendar)
        #expect(CycleEngine.measuredCycleLength(starts: starts, calendar: calendar) == nil)
    }

    // MARK: - Phase

    /// Menstrual 1–5, follicular 6–12, ovulatory 13–15, luteal 16 onward for a 28-day cycle.
    @Test("Faz sınırları", arguments: [
        (1, CyclePhase.menstrual), (5, .menstrual),
        (6, .follicular), (12, .follicular),
        (13, .ovulatory), (15, .ovulatory),
        (16, .luteal), (28, .luteal)
    ])
    func phaseBoundaries(_ dayOfCycle: Int, _ expected: CyclePhase) throws {
        let days = flowDays(cycles: 4)
        let target = day(3 * 28 + dayOfCycle - 1)
        let estimate = try #require(CycleEngine.phase(on: target, flowDays: days, calendar: calendar))
        #expect(estimate.dayOfCycle == dayOfCycle)
        #expect(estimate.phase == expected, "gün \(dayOfCycle)")
    }

    @Test("Kayıt yoksa faz tahmini yok")
    func noEstimateWithoutFlowData() {
        #expect(CycleEngine.phase(on: day(10), flowDays: [], calendar: calendar) == nil)
    }

    /// Past one and a half cycle lengths the count has stopped meaning anything — almost
    /// always a logging gap rather than a cycle that long.
    @Test("Çok geç günlerde faz üretilmez")
    func stopsCountingAfterOneAndAHalfCycles() {
        let days = flowDays(cycles: 1)
        #expect(CycleEngine.phase(on: day(50), flowDays: days, calendar: calendar) == nil)
    }

    @Test("Güven: ölçülü uzunluk ve çok döngü yüksek, tek döngü düşük")
    func confidenceReflectsEvidence() throws {
        let many = try #require(
            CycleEngine.phase(on: day(3 * 28 + 20), flowDays: flowDays(cycles: 4), calendar: calendar)
        )
        #expect(many.isConfident)

        let few = try #require(
            CycleEngine.phase(on: day(20), flowDays: flowDays(cycles: 1), calendar: calendar)
        )
        #expect(!few.isConfident, "tek döngüden kesin konuşulmamalı: \(few.confidence)")
        #expect(few.qualifier.hasPrefix("Muhtemelen"))
    }

    // MARK: - Phase-aware baselines

    /// The whole reason the feature exists: a luteal resting heart rate compared against a
    /// whole-cycle mean reads high every month.
    @Test("Faz ayrımı luteal kaymayı ortaya çıkarır")
    func partitionSeparatesPhases() throws {
        let days = flowDays(cycles: 6)
        var values: [(day: Date, value: Double)] = []
        for offset in 0..<(6 * 28) {
            let dayOfCycle = offset % 28 + 1
            // Follicular 50, luteal 54 — a four-beat shift, inside the published range.
            values.append((day(offset), dayOfCycle >= 16 ? 54 : 50))
        }

        let partitioned = CycleEngine.partition(values: values, flowDays: days, calendar: calendar)
        let follicular = try #require(CycleEngine.phaseBaseline(for: .follicularPhase, partitioned: partitioned))
        let luteal = try #require(CycleEngine.phaseBaseline(for: .lutealPhase, partitioned: partitioned))

        #expect(abs(follicular.mean - 50) < 0.001)
        #expect(abs(luteal.mean - 54) < 0.001)

        let shift = try #require(CycleEngine.phaseShift(partitioned: partitioned))
        #expect(abs(shift - 4) < 0.001)
    }

    @Test("Az örnekli grupta faz taban çizgisi kullanılmaz")
    func requiresEnoughSamplesPerGroup() {
        let days = flowDays(cycles: 2)
        let values = (0..<20).map { (day($0), 50.0) }
        let partitioned = CycleEngine.partition(values: values, flowDays: days, calendar: calendar)
        #expect(CycleEngine.phaseBaseline(for: .lutealPhase, partitioned: partitioned) == nil)
    }

    /// Putting a day whose phase is unknown into either group is exactly the contamination
    /// the partition exists to prevent.
    @Test("Fazı bilinmeyen günler hiçbir gruba konmaz")
    func dropsUnknownDays() {
        let values = (0..<40).map { (day($0), 50.0) }
        let partitioned = CycleEngine.partition(values: values, flowDays: [], calendar: calendar)
        #expect(partitioned.isEmpty)
    }

    @Test("Ovulasyon foliküler grupla havuzlanır")
    func ovulatoryPoolsWithFollicular() {
        #expect(CyclePhase.ovulatory.baselineGroup == .follicularPhase)
        #expect(CyclePhase.menstrual.baselineGroup == .follicularPhase)
        #expect(CyclePhase.luteal.baselineGroup == .lutealPhase)
    }

    // MARK: - §12

    /// The line this engine lives on. No fertility, no pregnancy, no diagnosis — in any
    /// phase, in any string it can produce.
    @Test("Hiçbir faz metni yasaklı dil içermez")
    func copyStaysWithinBounds() throws {
        for phase in CyclePhase.allCases {
            #expect(SafetyFilter.isSafe(phase.physiologyNote), "\(phase.rawValue)")
            let lowered = phase.physiologyNote.lowercased()
            #expect(!lowered.contains("gebe"))
            #expect(!lowered.contains("doğurgan"))
            #expect(!lowered.contains("hamile"))
        }

        let estimate = try #require(
            CycleEngine.phase(on: day(3 * 28 + 20), flowDays: flowDays(cycles: 4), calendar: calendar)
        )
        let context = CycleEngine.context(for: estimate, metric: .heartRateVariability, phaseMean: 58)
        #expect(SafetyFilter.isSafe(context))
        #expect(context.contains("Luteal"))
    }
}
