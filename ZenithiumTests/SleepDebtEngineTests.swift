//
//  SleepDebtEngineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C4 — sleep owed, and the clock's weekly drift.
//
//  Two properties carry the design. A long night must not zero out a bad week, because a
//  ledger that lets it does the comfortable thing rather than the true one. And a night the
//  watch barely saw must not count as an eight-hour deficit, because missing data is not the
//  same as no sleep — that is the ledger's loudest possible lie.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Sleep debt")
struct SleepDebtEngineTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
        return calendar
    }()

    /// A Wednesday, so weekday arithmetic is unambiguous.
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func nights(_ hours: [Double], midpointMinutes: Double? = 210) -> [BiometricDaySnapshot] {
        hours.enumerated().map { offset, slept in
            snapshot(
                dayStart: calendar.startOfDay(
                    for: now.addingTimeInterval(-Double(hours.count - 1 - offset) * 86_400)
                ),
                sleptHours: slept,
                midpointMinutes: midpointMinutes
            )
        }
    }

    // MARK: - The ledger

    @Test("Uzun bir gece kötü bir haftayı sıfırlamıyor")
    func alongNightDoesNotEraseTheWeek() {
        let ledger = SleepDebtEngine.ledger(
            days: nights([5, 5, 10]),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        // Naively the three nights net to four hours owed. Surplus repays half, so the
        // ledger says five — the comfortable answer and the true one differ, deliberately.
        #expect(abs(ledger.hours - 5) < 0.001)
    }

    @Test("Düzenli eksik uyku doğrusal birikiyor")
    func asteadyShortfallAccumulates() {
        let ledger = SleepDebtEngine.ledger(
            days: nights(Array(repeating: 6.5, count: 7)),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        #expect(abs(ledger.hours - 10.5) < 0.001)
        #expect(ledger.nights == 7)
        #expect(ledger.isReliable)
    }

    @Test("İhtiyacın üstünde uyunan bir hafta borç göstermiyor")
    func asleptWeekOwesNothing() {
        let ledger = SleepDebtEngine.ledger(
            days: nights(Array(repeating: 8.5, count: 7)),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        #expect(ledger.hours == 0)
    }

    @Test("Saatin göremediği gece borç sayılmıyor")
    func amissedNightIsNotADeficit() {
        // Twenty minutes of recorded sleep is a watch that came off, not a twenty-minute
        // night. Counting it as a 7.7-hour deficit would swamp the ledger.
        let withGap = SleepDebtEngine.ledger(
            days: nights([7, 7, 0.3, 7]),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        let withoutGap = SleepDebtEngine.ledger(
            days: nights([7, 7, 7]),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        #expect(abs(withGap.hours - withoutGap.hours) < 0.001)
        #expect(withGap.nights == 3)
    }

    @Test("Az gece varsa defter geçici sayılıyor")
    func afewNightsIsProvisional() {
        let ledger = SleepDebtEngine.ledger(
            days: nights([6, 6]),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        #expect(!ledger.isReliable)
        #expect(SleepDebtEngine.summary(for: ledger).contains("yeterli gece yok"))
    }

    @Test("Pencere dışındaki geceler sayılmıyor")
    func nightsOutsideTheWindowAreIgnored() {
        let old = snapshot(
            dayStart: calendar.startOfDay(for: now.addingTimeInterval(-40 * 86_400)),
            sleptHours: 2.5,
            midpointMinutes: 210
        )
        let ledger = SleepDebtEngine.ledger(
            days: nights([7.5, 7.5, 7.5, 7.5, 7.5]) + [old],
            needHours: 8,
            now: now,
            calendar: calendar
        )
        #expect(ledger.nights == 5)
        #expect(abs(ledger.hours - 2.5) < 0.001)
    }

    @Test("En kötü gece bildiriliyor")
    func theworstNightIsReported() throws {
        let ledger = SleepDebtEngine.ledger(
            days: nights([7, 4.5, 7, 7, 7]),
            needHours: 8,
            now: now,
            calendar: calendar
        )
        let worst = try #require(ledger.worstNight)
        #expect(abs(worst.sleptHours - 4.5) < 0.001)
    }

    @Test("Özet emir vermiyor")
    func thesummaryDoesNotInstruct() {
        for hours in [[6.0, 6, 6, 6, 6, 6, 6], [8.5, 8.5, 8.5, 8.5, 8.5], [4.0, 4, 4, 4, 4, 4]] {
            let text = SleepDebtEngine.summary(
                for: SleepDebtEngine.ledger(days: nights(hours), needHours: 8, now: now, calendar: calendar)
            ).lowercased()
            // §1 — hours, never an instruction to go to bed.
            for word in ["yatmalı", "erken yat", "uyumalı", "azalt", "bırak"] {
                #expect(!text.contains(word), "\(word)")
            }
        }
    }

    // MARK: - Social jetlag

    @Test("Hafta sonu geç kalkmak pozitif kayma veriyor")
    func alaterWeekendProducesAPositiveShift() throws {
        var days: [BiometricDaySnapshot] = []
        for offset in 0..<14 {
            let dayStart = calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400))
            let isFree = SleepDebtEngine.isFreeDay(dayStart, calendar: calendar)
            days.append(
                snapshot(
                    dayStart: dayStart,
                    sleptHours: 7.5,
                    // 03:00 on work days, 04:30 at the weekend.
                    midpointMinutes: isFree ? 270 : 180
                )
            )
        }
        let jetlag = try #require(
            SleepDebtEngine.socialJetlag(days: days, now: now, calendar: calendar)
        )
        #expect(jetlag.isReliable)
        #expect(abs(jetlag.hours - 1.5) < 0.01)
        #expect(SleepDebtEngine.summary(for: jetlag).contains("geç"))
    }

    @Test("Gece yarısını aşan orta noktalar kısa yoldan karşılaştırılıyor")
    func midpointsWrapAroundMidnight() {
        // Work days end at 23:50, free days at 00:40. Fifty minutes apart, not 23 hours.
        let jetlag = SocialJetlag(
            workdayMidpointMinutes: 1_430,
            freeDayMidpointMinutes: 40,
            workdayNights: 8,
            freeDayNights: 4
        )
        #expect(abs(jetlag.hours - 50.0 / 60) < 0.001)
    }

    @Test("Tek taraf yetersizse karşılaştırma güvenilir değil")
    func onesidedDataIsNotReliable() throws {
        var days: [BiometricDaySnapshot] = []
        for offset in 0..<5 {
            let dayStart = calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400))
            days.append(snapshot(dayStart: dayStart, sleptHours: 7.5, midpointMinutes: 200))
        }
        let jetlag = SleepDebtEngine.socialJetlag(days: days, now: now, calendar: calendar)
        if let jetlag {
            #expect(!jetlag.isReliable)
            #expect(SleepDebtEngine.summary(for: jetlag).contains("yeterli gece yok"))
        }
    }

    @Test("Orta noktası olmayan geceler karşılaştırmaya girmiyor")
    func nightsWithoutAMidpointAreSkipped() {
        var days: [BiometricDaySnapshot] = []
        for offset in 0..<14 {
            let dayStart = calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400))
            days.append(snapshot(dayStart: dayStart, sleptHours: 7.5, midpointMinutes: nil))
        }
        #expect(SleepDebtEngine.socialJetlag(days: days, now: now, calendar: calendar) == nil)
    }

    // MARK: - Fixtures

    private func snapshot(
        dayStart: Date,
        sleptHours: Double,
        midpointMinutes: Double?
    ) -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: dayStart,
            timeZoneIdentifier: "Europe/Istanbul",
            heartRateVariability: 60,
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
            sleepDurationSeconds: sleptHours * 3_600,
            sleepScore: 80,
            sleepEfficiency: 0.9,
            deepSeconds: 4_000,
            remSeconds: 5_000,
            coreSeconds: 16_000,
            awakeSeconds: 1_000,
            timeInBedSeconds: (sleptHours + 0.5) * 3_600,
            sleepMidpointMinutes: midpointMinutes,
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
