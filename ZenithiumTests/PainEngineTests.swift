//
//  PainEngineTests.swift
//  ZenithiumTests
//
//  The pain log's one honest comparison, and the §12 boundary around it.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Pain engine")
struct PainEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    private var origin: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9)) ?? Date()
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: origin) ?? origin
    }

    private func entry(_ muscle: MuscleGroup, dayOffset: Int, severity: Int = 3) -> PainEntry {
        PainEntry(
            muscle: muscle,
            laterality: .right,
            severity: severity,
            quality: .ache,
            loggedAt: day(dayOffset)
        )
    }

    /// Thirty days of light load, with heavy days seeded before each entry day.
    private func loads(heavyBefore entryDays: [Int]) -> [DailyLoad] {
        let heavy = Set(entryDays.flatMap { [$0 - 1, $0 - 2] })
        return (0..<30).map { offset in
            DailyLoad(dayStart: calendar.startOfDay(for: day(offset)), load: heavy.contains(offset) ? 14 : 3)
        }
    }

    // MARK: - The comparison

    @Test("Ağır günlerden sonra gelen kayıtlar yükle ilişkilendirilir")
    func detectsLoadPattern() throws {
        let entryDays = [10, 17, 24]
        let insights = PainEngine.insights(
            entries: entryDays.map { entry(.calves, dayOffset: $0) },
            dailyLoads: loads(heavyBefore: entryDays),
            calendar: calendar
        )
        let calves = try #require(insights.first { $0.muscle == .calves })
        #expect(calves.followsLoad)
        #expect(calves.loadBefore > calves.loadOtherwise)
        #expect(calves.summary.contains("daha yüksekti"))
    }

    @Test("Yük farkı yoksa örüntü iddia edilmez")
    func doesNotClaimPatternWithoutOne() throws {
        let flat = (0..<30).map {
            DailyLoad(dayStart: calendar.startOfDay(for: day($0)), load: 8)
        }
        let insights = PainEngine.insights(
            entries: [10, 17, 24].map { entry(.calves, dayOffset: $0) },
            dailyLoads: flat,
            calendar: calendar
        )
        let calves = try #require(insights.first)
        #expect(!calves.followsLoad)
        #expect(calves.summary.contains("belirgin bir örüntü göstermiyor"))
    }

    /// A 2.0 difference on a base of 2 is one hard session, not a pattern — so the relative
    /// test has to fire alongside the absolute one.
    @Test("Küçük tabanda büyük göreli fark tek başına yetmez")
    func requiresBothAbsoluteAndRelative() {
        let tiny = (0..<30).map { offset -> DailyLoad in
            let load = [10, 9, 17, 16, 24, 23].contains(offset) ? 1.5 : 0.4
            return DailyLoad(dayStart: calendar.startOfDay(for: day(offset)), load: load)
        }
        let insights = PainEngine.insights(
            entries: [10, 17, 24].map { entry(.calves, dayOffset: $0) },
            dailyLoads: tiny,
            calendar: calendar
        )
        #expect(insights.first?.followsLoad == false, "mutlak eşik tutmadan örüntü iddia edilmemeli")
    }

    @Test("Üç kayıttan az olunca içgörü üretilmez")
    func requiresThreeEntries() {
        let insights = PainEngine.insights(
            entries: [entry(.calves, dayOffset: 10), entry(.calves, dayOffset: 17)],
            dailyLoads: loads(heavyBefore: [10, 17]),
            calendar: calendar
        )
        #expect(insights.isEmpty)
    }

    /// A heavy Tuesday that produced a calf entry must not also serve as a control day for
    /// the hamstrings — that would put the same day on both sides of the comparison.
    @Test("Kontrol grubu hiçbir kayıt taşımayan günlerden kurulur")
    func controlExcludesAllEntryDays() throws {
        let entries = [10, 17, 24].map { entry(.calves, dayOffset: $0) }
            + [11, 18, 25].map { entry(.hamstrings, dayOffset: $0) }
        let insights = PainEngine.insights(
            entries: entries,
            dailyLoads: loads(heavyBefore: [10, 17, 24]),
            calendar: calendar
        )
        // Both regions share one control mean, and no entry day appears in it.
        let means = Set(insights.map { ZenithiumFormat.metric($0.loadOtherwise, digits: 4) })
        #expect(means.count == 1, "kontrol ortalaması bölgeye göre değişmemeli")
    }

    // MARK: - §12

    /// Past the threshold the app's usefulness genuinely ends, and the sentence has to say
    /// so instead of offering training context beside it.
    @Test("Yüksek şiddet yük bağlamını değil hekim yönlendirmesini verir")
    func severeEntriesRouteToClinician() throws {
        let entryDays = [10, 17, 24]
        let insights = PainEngine.insights(
            entries: [
                entry(.calves, dayOffset: 10, severity: 3),
                entry(.calves, dayOffset: 17, severity: 8),
                entry(.calves, dayOffset: 24, severity: 4)
            ],
            dailyLoads: loads(heavyBefore: entryDays),
            calendar: calendar
        )
        let calves = try #require(insights.first)
        #expect(calves.hasSevereEntry)
        #expect(calves.summary.contains("hekime göster"))
        #expect(!calves.summary.contains("daha yüksekti"), "yük cümlesi yerine geçmeli, yanına gelmemeli")
    }

    @Test("Şiddetli kayıtlar listenin başına gelir")
    func severeSortsFirst() throws {
        let insights = PainEngine.insights(
            entries: [10, 17, 24].map { entry(.calves, dayOffset: $0, severity: 2) }
                + [11, 18, 25].map { entry(.lowerBack, dayOffset: $0, severity: 8) },
            dailyLoads: loads(heavyBefore: [10, 17, 24]),
            calendar: calendar
        )
        #expect(insights.first?.muscle == .lowerBack)
    }

    @Test("Her içgörü cümlesi güvenlik süzgecinden geçer")
    func summariesAreSafe() {
        let insights = PainEngine.insights(
            entries: [10, 17, 24].map { entry(.calves, dayOffset: $0, severity: 8) },
            dailyLoads: loads(heavyBefore: [10, 17, 24]),
            calendar: calendar
        )
        for insight in insights {
            #expect(SafetyFilter.isSafe(insight.summary), "\(insight.summary)")
        }
    }

    @Test("Şiddet 0–10 aralığına kırpılır")
    func severityIsClamped() {
        #expect(PainEntry(muscle: .calves, laterality: .left, severity: 42, quality: .ache, loggedAt: origin).severity == 10)
        #expect(PainEntry(muscle: .calves, laterality: .left, severity: -3, quality: .ache, loggedAt: origin).severity == 0)
    }

    // MARK: - Laterality

    @Test("Tek taraflı yoğunluk sayı olarak bildirilir")
    func reportsLaterality() throws {
        let entries = [
            PainEntry(muscle: .calves, laterality: .right, severity: 3, quality: .ache, loggedAt: day(10)),
            PainEntry(muscle: .calves, laterality: .right, severity: 3, quality: .ache, loggedAt: day(12)),
            PainEntry(muscle: .calves, laterality: .right, severity: 3, quality: .ache, loggedAt: day(14)),
            PainEntry(muscle: .calves, laterality: .left, severity: 2, quality: .ache, loggedAt: day(16))
        ]
        let summary = try #require(PainEngine.lateralityImbalance(entries: entries, muscle: .calves))
        #expect(summary.contains("sağ"))
        #expect(SafetyFilter.isSafe(summary))
    }

    @Test("Eşit dağılımda asimetri bildirilmez")
    func noImbalanceWhenEven() {
        let entries = [
            PainEntry(muscle: .calves, laterality: .right, severity: 3, quality: .ache, loggedAt: day(10)),
            PainEntry(muscle: .calves, laterality: .right, severity: 3, quality: .ache, loggedAt: day(12)),
            PainEntry(muscle: .calves, laterality: .left, severity: 3, quality: .ache, loggedAt: day(14)),
            PainEntry(muscle: .calves, laterality: .left, severity: 3, quality: .ache, loggedAt: day(16))
        ]
        #expect(PainEngine.lateralityImbalance(entries: entries, muscle: .calves) == nil)
    }
}

@Suite("Clinician report")
struct ClinicianReportTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func days(count: Int) -> [BiometricDaySnapshot] {
        (0..<count).map { offset in
            BiometricDaySnapshot(
                dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400)),
                timeZoneIdentifier: "UTC",
                heartRateVariability: 60 + Double(offset % 5),
                restingHeartRate: 50 + Double(offset % 3),
                wristTemperatureDelta: nil,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                recoveryScore: 70,
                recoveryConfidence: 1,
                recoveryZTotal: 0,
                dayStrain: 8,
                targetCeiling: 14,
                trimp: 60,
                zoneSeconds: [],
                maxHeartRateUsed: 190,
                sleepDurationSeconds: 7 * 3600,
                sleepScore: 80,
                sleepEfficiency: 0.9,
                deepSeconds: 4_000,
                remSeconds: 5_000,
                coreSeconds: 16_000,
                awakeSeconds: 1_000,
                timeInBedSeconds: 8 * 3600,
                sleepMidpointMinutes: 200,
                sleepStart: nil,
                wakeTime: nil,
                napSeconds: 0,
                dataQuality: .good,
                dataQualityReasons: [],
                computedAt: now,
                engineVersion: 1
            )
        }
    }

    @Test("Yeterli gün varsa temel bölümler dolar")
    func buildsCoreSections() {
        let report = ClinicianReportBuilder.build(
            days: days(count: 40),
            vitals: [],
            markers: [],
            sex: .male,
            now: now,
            calendar: calendar
        )
        #expect(!report.isEmpty)
        #expect(report.sections.contains { $0.title == "Gece ölçümleri" })
        #expect(report.sections.contains { $0.title == "Uyku" })
    }

    /// A mean of three days would look like a measurement and is not one.
    @Test("Az örnekli satırlar basılmaz")
    func dropsThinRows() {
        #expect(ClinicianReportBuilder.row(label: "x", values: [1, 2, 3], digits: 0) == nil)
        #expect(ClinicianReportBuilder.row(label: "x", values: Array(repeating: 1.0, count: 10), digits: 0) != nil)
    }

    /// §12: the document states where a value sits, never whether that is good.
    @Test("Rapor yorum içermez")
    func reportInterpretsNothing() {
        let report = ClinicianReportBuilder.build(
            days: days(count: 40),
            vitals: [],
            markers: [],
            sex: .male,
            now: now,
            calendar: calendar
        )
        #expect(SafetyFilter.isSafe(report.disclaimer))
        for section in report.sections {
            if let caption = section.caption { #expect(SafetyFilter.isSafe(caption)) }
            for line in section.lines { #expect(SafetyFilter.isSafe(line), "\(line)") }
            for row in section.rows { #expect(SafetyFilter.isSafe(row.label)) }
        }
        #expect(report.disclaimer.contains("yorumlanmamış"))
    }

    @Test("Boş veriden rapor üretilmez")
    func emptyDataProducesEmptyReport() {
        let report = ClinicianReportBuilder.build(
            days: [],
            vitals: [],
            markers: [],
            sex: .notSet,
            now: now,
            calendar: calendar
        )
        #expect(report.isEmpty)
    }
}
