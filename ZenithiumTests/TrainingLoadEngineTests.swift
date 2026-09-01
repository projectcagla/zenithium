//
//  TrainingLoadEngineTests.swift
//  ZenithiumTests
//
//  The load engine. Every figure below was verified independently before it was asserted on.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Training load engine")
struct TrainingLoadEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    /// A steady four-sessions-a-week block, repeated. Its true ratio is 1.00 by construction.
    private func steadyBlock(weeks: Int, reference: Date) -> TrainingLoadInput {
        let week: [Double] = [12, 0, 8, 0, 14, 6, 0]
        let pattern = Array(repeating: week, count: weeks).flatMap { $0 }
        return input(pattern, reference: reference)
    }

    private func input(_ loads: [Double], reference: Date) -> TrainingLoadInput {
        var days: [DailyLoad] = []
        for (offset, load) in loads.enumerated() {
            let day = calendar.date(byAdding: .day, value: -(loads.count - 1 - offset), to: reference) ?? reference
            days.append(DailyLoad(dayStart: calendar.startOfDay(for: day), load: load))
        }
        return TrainingLoadInput(days: days, referenceDay: reference, calendar: calendar)
    }

    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)) ?? Date()
    }

    // MARK: - The seed bug this engine was rewritten to fix

    /// Seeding the exponential terms at day one leaves the chronic term carrying 14.5% of
    /// that single value four weeks later, and an unchanging block whose true ratio is 1.00
    /// reads 0.84. Seeding at the first week's mean reads 0.99 from four weeks onward.
    @Test("Değişmeyen blok dört haftadan itibaren 1.00 civarı okur")
    func steadyBlockReadsUnity() throws {
        for weeks in [4, 8, 12] {
            let output = TrainingLoadEngine.analyse(steadyBlock(weeks: weeks, reference: reference))
            let ratio = try #require(output.ratio, "\(weeks) haftada oran üretilmeliydi")
            #expect(abs(ratio - 1.0) < 0.02, "\(weeks) hafta: \(ratio)")
        }
    }

    /// The unsmoothed ratio swings by nearly half across one unchanged week, which is the
    /// reason the headline is the seven-day mean and not this.
    @Test("Anlık oran hafta içinde salınır, düzleştirilmiş olan salınmaz")
    func instantRatioSwingsButHeadlineDoesNot() throws {
        let output = TrainingLoadEngine.analyse(steadyBlock(weeks: 12, reference: reference))
        let instant = try #require(output.instantRatio)
        let headline = try #require(output.ratio)

        #expect(abs(headline - 1.0) < 0.02)
        // Reference day lands on a rest day, so the instantaneous term sits well below.
        #expect(instant < headline - 0.05)

        let spread = (output.recentRatios.max() ?? 0) - (output.recentRatios.min() ?? 0)
        #expect(spread > 0.2, "salınım beklenenden küçük: \(spread)")
    }

    // MARK: - Bands

    @Test("Yükselen ve azalan haftalar doğru bantlara düşer")
    func bandsFollowTheChange() throws {
        let week: [Double] = [12, 0, 8, 0, 14, 6, 0]
        let base = Array(repeating: week, count: 8).flatMap { $0 }

        let heavier = base + week.map { $0 * 1.4 }
        let heavyRatio = try #require(TrainingLoadEngine.analyse(input(heavier, reference: reference)).ratio)
        #expect(heavyRatio > 1.10, "ağır hafta: \(heavyRatio)")

        let taper = base + week.map { $0 * 0.5 }
        let taperRatio = try #require(TrainingLoadEngine.analyse(input(taper, reference: reference)).ratio)
        #expect(taperRatio < 0.85, "taper: \(taperRatio)")
        #expect(TrainingLoadEngine.analyse(input(taper, reference: reference)).band == .detraining)
    }

    @Test("Bant sınırları")
    func bandBoundaries() {
        #expect(LoadBand.band(forRatio: 0.79) == .detraining)
        #expect(LoadBand.band(forRatio: 0.80) == .maintaining)
        #expect(LoadBand.band(forRatio: 1.00) == .productive)
        #expect(LoadBand.band(forRatio: 1.29) == .productive)
        #expect(LoadBand.band(forRatio: 1.30) == .rising)
        #expect(LoadBand.band(forRatio: 1.50) == .spike)
    }

    // MARK: - History gate

    @Test("Yeterli antrenman günü yoksa oran üretilmez")
    func suppressesRatioWithoutHistory() {
        var loads = Array(repeating: 0.0, count: 40)
        loads[38] = 20
        loads[39] = 18
        let output = TrainingLoadEngine.analyse(input(loads, reference: reference))
        #expect(output.ratio == nil)
        #expect(output.band == nil)
        #expect(TrainingLoadEngine.summary(for: output).contains("gerekiyor"))
    }

    /// A rest day is a data point, not an absence. Dropping them would make a
    /// three-sessions-a-week athlete look like they train daily.
    @Test("Boş günler sıfır olarak doldurulur")
    func fillsGapsWithZero() {
        let sparse = [
            DailyLoad(dayStart: calendar.date(byAdding: .day, value: -10, to: reference) ?? reference, load: 20),
            DailyLoad(dayStart: reference, load: 10)
        ]
        let series = TrainingLoadEngine.densifiedSeries(
            TrainingLoadInput(days: sparse, referenceDay: reference, calendar: calendar)
        )
        #expect(series.count == 11)
        #expect(series.filter { $0.load == 0 }.count == 9)
    }

    // MARK: - Monotony

    @Test("Tekdüzelik: aynı yükte her gün yüksek, değişken haftada düşük")
    func monotonyDiscriminates() throws {
        let varied = [12, 0, 8, 0, 14, 6, 0].map { DailyLoad(dayStart: reference, load: Double($0)) }
        let flat = Array(repeating: 8.0, count: 7).map { DailyLoad(dayStart: reference, load: $0) }

        let variedMonotony = try #require(TrainingLoadEngine.monotony(of: varied))
        #expect(variedMonotony < 1.2)
        // A perfectly flat week has zero deviation, which is where the floor earns its keep.
        #expect(TrainingLoadEngine.monotony(of: flat) == nil)
    }

    @Test("Dinlenme haftası sonsuz tekdüzelik üretmez")
    func restWeekHasNoMonotony() {
        let rest = Array(repeating: 0.0, count: 7).map { DailyLoad(dayStart: reference, load: $0) }
        #expect(TrainingLoadEngine.monotony(of: rest) == nil)
    }

    // MARK: - Fitness and fatigue

    /// Fatigue sheds on a seven-day constant and fitness on a forty-two-day one, so two
    /// weeks off leaves form positive. That difference is the whole reason a taper works.
    @Test("İki hafta dinlenme formu pozitife çevirir")
    func taperLiftsForm() {
        let week: [Double] = [12, 0, 8, 0, 14, 6, 0]
        let loaded = Array(repeating: week, count: 8).flatMap { $0 }
        let tapered = loaded + Array(repeating: 0.0, count: 14)

        let before = TrainingLoadEngine.analyse(input(loaded, reference: reference)).fitnessFatigue
        let after = TrainingLoadEngine.analyse(input(tapered, reference: reference)).fitnessFatigue

        #expect(before.form < after.form)
        #expect(after.form > 0)
        #expect(after.fitness < before.fitness, "kondisyon da düşmeli, sadece daha yavaş")
    }

    // MARK: - Forecasting

    @Test("Anlık tavan çözümü tam olarak geri döner")
    func ceilingRoundTrips() throws {
        let output = TrainingLoadEngine.analyse(steadyBlock(weeks: 12, reference: reference))
        for ceiling in [1.10, 1.30, 1.50] {
            let allowed = try #require(TrainingLoadEngine.loadCeiling(forInstantRatio: ceiling, from: output))
            let achieved = try #require(TrainingLoadEngine.projectedInstantRatio(after: allowed, from: output))
            #expect(abs(achieved - ceiling) < 1e-9, "tavan \(ceiling) -> \(achieved)")
        }
    }

    /// For an athlete whose hard days run 12–14, a 1.30 ceiling has to permit a hard-but-
    /// sane session. A ceiling that answers "515" or "0.4" is arithmetically fine and
    /// useless as a prescription.
    @Test("Tavan kullanılabilir büyüklükte yük verir")
    func ceilingIsUsable() throws {
        let output = TrainingLoadEngine.analyse(steadyBlock(weeks: 12, reference: reference))
        let allowed = try #require(TrainingLoadEngine.loadCeiling(forInstantRatio: 1.30, from: output))
        #expect(allowed > 12 && allowed < 30, "izin verilen yük: \(allowed)")
    }

    @Test("Daha ağır seans daha yüksek öngörülen oran verir")
    func projectionIsMonotonic() throws {
        let output = TrainingLoadEngine.analyse(steadyBlock(weeks: 12, reference: reference))
        let light = try #require(TrainingLoadEngine.projectedRatio(after: 5, from: output))
        let heavy = try #require(TrainingLoadEngine.projectedRatio(after: 25, from: output))
        #expect(heavy > light)
    }
}
