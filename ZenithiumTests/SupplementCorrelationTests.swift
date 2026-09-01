//
//  SupplementCorrelationTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C5 — supplements as a correlation subject.
//
//  A course is a window, not a nightly tap, and the tests are mostly about that difference:
//  which days a course covers, that an ongoing course has no end, and that the engine's
//  wording still reports rather than claims. §12 governs the last one — the app may say a
//  measurement differed between two windows and may never say a substance caused it.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Supplement courses")
struct SupplementCourseTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("Kür kendi penceresini kapsıyor")
    func acourseCoversItsWindow() {
        let course = SupplementCourse(
            name: "Kreatin",
            startedAt: start,
            endedAt: start.addingTimeInterval(30 * 86_400)
        )
        #expect(!course.covers(start.addingTimeInterval(-86_400)))
        #expect(course.covers(start))
        #expect(course.covers(start.addingTimeInterval(15 * 86_400)))
        #expect(course.covers(start.addingTimeInterval(30 * 86_400)))
        #expect(!course.covers(start.addingTimeInterval(31 * 86_400)))
    }

    @Test("Süren bir kürün sonu yok")
    func anongoingCourseHasNoEnd() {
        let course = SupplementCourse(name: "D vitamini", startedAt: start)
        #expect(course.isOngoing)
        #expect(course.covers(start.addingTimeInterval(400 * 86_400)))
        #expect(course.days(through: start.addingTimeInterval(9 * 86_400)) == 10)
    }

    @Test("Kür, korelasyon öznesine dönüşüyor")
    func acourseBecomesASubject() {
        let course = SupplementCourse(name: "Magnezyum", startedAt: start)
        #expect(course.correlationSubject == .supplement("Magnezyum"))
        #expect(course.correlationSubject.displayName == "Magnezyum")
        #expect(course.correlationSubject.behavior == nil)
        #expect(course.correlationSubject.symbolName == "pills")
    }

    @Test("Özne anahtarları çakışmıyor")
    func subjectKeysDoNotCollide() {
        var keys = Set<String>()
        for behavior in JournalBehavior.allCases {
            keys.insert(CorrelationSubject.behavior(behavior).key)
        }
        let before = keys.count
        keys.insert(CorrelationSubject.supplement("alcohol").key)
        // A supplement someone happens to name after a behaviour must not overwrite it.
        #expect(keys.count == before + 1)
    }
}

@Suite("Supplement correlation")
struct SupplementCorrelationTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Sixty nights: the first thirty at one HRV, the last thirty higher, with a course
    /// starting halfway.
    private func history(
        before: Double,
        during: Double
    ) -> (records: [BiometricDaySnapshot], course: SupplementCourse) {
        var records: [BiometricDaySnapshot] = []
        for offset in 0..<60 {
            let dayStart = calendar.startOfDay(
                for: now.addingTimeInterval(-Double(59 - offset) * 86_400)
            )
            // A little alternating noise, so both groups have a variance. Two identical
            // constants would make the pooled deviation zero and the effect size undefined,
            // which tests the engine's arithmetic rather than its behaviour.
            let jitter: Double = offset.isMultiple(of: 2) ? 2 : -2
            records.append(
                snapshot(dayStart: dayStart, hrv: (offset < 30 ? before : during) + jitter)
            )
        }
        let courseStart = records[30].dayStart
        return (records, SupplementCourse(name: "Kreatin", startedAt: courseStart))
    }

    @Test("Kürün kapsadığı geceler diğerleriyle karşılaştırılıyor")
    func thecourseWindowIsCompared() throws {
        let (records, course) = history(before: 50, during: 62)
        let results = JournalViewModel.buildInsights(
            outcome: .heartRateVariability,
            logs: journalDays(for: records),
            records: records,
            calendar: calendar,
            supplements: [course]
        )
        let supplement = try #require(results.first { $0.subject == .supplement("Kreatin") })
        #expect(supplement.sampleWithBehavior == 30)
        #expect(supplement.sampleWithoutBehavior == 30)
        #expect(supplement.difference > 10)
        #expect(supplement.isConsistent)
    }

    @Test("Fark yoksa tutarlı bir sonuç bildirilmiyor")
    func noDifferenceIsNotReportedAsOne() throws {
        let (records, course) = history(before: 55, during: 55)
        let results = JournalViewModel.buildInsights(
            outcome: .heartRateVariability,
            logs: journalDays(for: records),
            records: records,
            calendar: calendar,
            supplements: [course]
        )
        let supplement = try #require(results.first { $0.subject == .supplement("Kreatin") })
        #expect(!supplement.isConsistent)
    }

    @Test("Özet sebep iddia etmiyor")
    func thesummaryClaimsNoCause() throws {
        let (records, course) = history(before: 50, during: 62)
        let results = JournalViewModel.buildInsights(
            outcome: .heartRateVariability,
            logs: journalDays(for: records),
            records: records,
            calendar: calendar,
            supplements: [course]
        )
        let supplement = try #require(results.first { $0.subject == .supplement("Kreatin") })
        let text = CorrelationEngine.summary(for: supplement).lowercased()
        #expect(text.contains("kreatin"))
        // §12 — an observation, never a causal claim.
        for word in ["sayesinde", "yüzünden", "neden oldu", "artırır", "düşürür", "iyileştirir"] {
            #expect(!text.contains(word), "\(word)")
        }
    }

    @Test("Takviyesiz çağrı eskisi gibi çalışıyor")
    func withoutSupplementsNothingChanges() {
        let (records, _) = history(before: 50, during: 62)
        let results = JournalViewModel.buildInsights(
            outcome: .heartRateVariability,
            logs: journalDays(for: records),
            records: records,
            calendar: calendar
        )
        #expect(results.allSatisfy { $0.behavior != nil })
    }

    // MARK: - Fixtures

    /// A journal day for every record, so the behaviour side of the comparison has data too.
    private func journalDays(for records: [BiometricDaySnapshot]) -> [JournalDay] {
        records.enumerated().map { offset, record in
            JournalDay(
                dayStart: record.dayStart,
                behaviors: offset.isMultiple(of: 2) ? [.alcohol] : [],
                mood: .good,
                note: ""
            )
        }
    }

    private func snapshot(dayStart: Date, hrv: Double) -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: dayStart,
            timeZoneIdentifier: "Europe/Istanbul",
            heartRateVariability: hrv,
            restingHeartRate: 50,
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
            sleepDurationSeconds: 27_000,
            sleepScore: 80,
            sleepEfficiency: 0.9,
            deepSeconds: 4_000,
            remSeconds: 5_000,
            coreSeconds: 16_000,
            awakeSeconds: 1_000,
            timeInBedSeconds: 29_700,
            sleepMidpointMinutes: 210,
            sleepStart: nil,
            wakeTime: nil,
            napSeconds: 0,
            dataQuality: .good,
            dataQualityReasons: [],
            computedAt: dayStart,
            engineVersion: 1
        )
    }
}
