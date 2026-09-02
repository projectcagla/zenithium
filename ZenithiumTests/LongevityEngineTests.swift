//
//  LongevityEngineTests.swift
//  ZenithiumTests
//
//  The composite, and the promise that it opens.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Longevity engine")
struct LongevityEngineTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func vital(_ sign: VitalSign, values: [Double]) -> VitalReading {
        let samples = values.enumerated().map { offset, value in
            VitalSample(
                sign: sign,
                dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(values.count - 1 - offset) * 86_400)),
                value: value
            )
        }
        return VitalsEngine.reading(for: sign, samples: samples)
    }

    private func days(count: Int, hrv: Double = 60, resting: Double = 50, sleepHours: Double = 8, strain: Double = 8) -> [BiometricDaySnapshot] {
        (0..<count).map { offset in
            BiometricDaySnapshot(
                dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400)),
                timeZoneIdentifier: "Europe/Istanbul",
                heartRateVariability: hrv,
                restingHeartRate: resting,
                wristTemperatureDelta: nil,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                recoveryScore: 70,
                recoveryConfidence: 1,
                recoveryZTotal: 0,
                dayStrain: strain,
                targetCeiling: 14,
                trimp: 60,
                zoneSeconds: [],
                maxHeartRateUsed: 190,
                sleepDurationSeconds: sleepHours * 3600,
                sleepScore: 80,
                sleepEfficiency: 0.9,
                deepSeconds: 4_000,
                remSeconds: 5_000,
                coreSeconds: 16_000,
                awakeSeconds: 1_000,
                timeInBedSeconds: (sleepHours + 0.5) * 3600,
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

    // MARK: - Structure

    @Test("Ağırlıklar tam 1 eder")
    func weightsSumToOne() {
        let total = LongevityPillar.allCases.reduce(0) { $0 + $1.weight }
        #expect(abs(total - 1.0) < 1e-9)
    }

    /// A composite nobody can take apart is a horoscope with arithmetic.
    @Test("Skor bileşenlerini taşır")
    func alwaysCarriesComponents() throws {
        let score = try #require(
            LongevityEngine.score(
                vitals: [vital(.vo2Max, values: Array(repeating: 48.0, count: 30))],
                days: days(count: 60),
                now: now
            )
        )
        #expect(!score.components.isEmpty)
        for component in score.components {
            #expect(abs(component.contribution - component.score * component.pillar.weight) < 1e-9)
        }
    }

    /// Missing signals must not cost points. Without renormalising, a user whose watch does
    /// not report walking steadiness would score fifteen lower for owning different hardware.
    @Test("Eksik sütun puan düşürmez, kapsam olarak bildirilir")
    func missingPillarsRenormalise() throws {
        let full = try #require(
            LongevityEngine.score(
                vitals: [
                    vital(.vo2Max, values: Array(repeating: 48.0, count: 30)),
                    vital(.walkingSpeed, values: Array(repeating: 1.3, count: 30))
                ],
                days: days(count: 60),
                now: now
            )
        )
        let partial = try #require(
            LongevityEngine.score(
                vitals: [vital(.vo2Max, values: Array(repeating: 48.0, count: 30))],
                days: days(count: 60),
                now: now
            )
        )
        #expect(partial.coverage < full.coverage)
        #expect(partial.isPartial)
        // Both sit in the same region despite one pillar being absent.
        #expect(abs(partial.score - full.score) < 25)
    }

    @Test("Kapsam eşiğinin altında skor üretilmez")
    func requiresMinimumCoverage() {
        #expect(
            LongevityEngine.score(
                vitals: [vital(.vo2Max, values: Array(repeating: 48.0, count: 30))],
                days: [],
                now: now
            ) == nil
        )
    }

    // MARK: - Percentile

    @Test("Yüzdelik konumu")
    func percentileScoring() {
        let values = (1...100).map(Double.init)
        #expect(abs(LongevityEngine.percentileScore(of: 50.5, in: values, higherIsFitter: true) - 50) < 0.01)
        #expect(LongevityEngine.percentileScore(of: 100, in: values, higherIsFitter: true) > 99)
        #expect(LongevityEngine.percentileScore(of: 1, in: values, higherIsFitter: true) < 1)
    }

    /// A lower resting heart rate is fitter, so the scale has to invert for it.
    @Test("Düşük daha iyiyse ölçek ters çevrilir")
    func inversePolarity() {
        let values = (1...100).map(Double.init)
        let high = LongevityEngine.percentileScore(of: 90, in: values, higherIsFitter: false)
        let low = LongevityEngine.percentileScore(of: 10, in: values, higherIsFitter: false)
        #expect(low > high)
    }

    /// A value tied with its whole history scores the middle, not an end.
    @Test("Tamamen eşit seride orta puan")
    func flatSeriesScoresMiddle() {
        let flat = Array(repeating: 5.0, count: 20)
        #expect(abs(LongevityEngine.percentileScore(of: 5, in: flat, higherIsFitter: true) - 50) < 1e-9)
    }

    // MARK: - Sleep

    @Test("Uyku süresi puanı yedi–dokuz saatte tam")
    func sleepDurationCurve() throws {
        let good = try #require(LongevityEngine.score(vitals: [], days: days(count: 60, sleepHours: 8), now: now))
        let short = try #require(LongevityEngine.score(vitals: [], days: days(count: 60, sleepHours: 5), now: now))

        let goodSleep = try #require(good.components.first { $0.pillar == .sleep })
        let shortSleep = try #require(short.components.first { $0.pillar == .sleep })
        #expect(goodSleep.score > shortSleep.score)
    }

    @Test("Hareket sürekliliği oransal")
    func activityIsProportional() throws {
        let active = try #require(LongevityEngine.score(vitals: [], days: days(count: 60, strain: 8), now: now))
        let inactive = try #require(LongevityEngine.score(vitals: [], days: days(count: 60, strain: 0), now: now))

        let activeScore = try #require(active.components.first { $0.pillar == .activity })
        let inactiveScore = try #require(inactive.components.first { $0.pillar == .activity })
        #expect(activeScore.score == 100)
        #expect(inactiveScore.score == 0)
    }

    // MARK: - §12

    @Test("Özet bir sağlık hükmü vermez")
    func summaryIsDescriptive() throws {
        let score = try #require(LongevityEngine.score(vitals: [], days: days(count: 60), now: now))
        #expect(SafetyFilter.isSafe(score.summary))
        for pillar in LongevityPillar.allCases {
            #expect(SafetyFilter.isSafe(pillar.rationale), "\(pillar.rawValue)")
        }
    }
}

@Suite("Environment engine")
struct EnvironmentEngineTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func daylight(_ minutes: Double, days: Int) -> [VitalSample] {
        (0..<days).map { offset in
            VitalSample(
                sign: .timeInDaylight,
                dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400)),
                value: minutes
            )
        }
    }

    @Test("Gün ışığı güvenilirlik eğrisi")
    func daylightReliability() {
        #expect(EnvironmentEngine.daylightContext(from: daylight(200, days: 20)).circadianReliability == 1.0)
        #expect(EnvironmentEngine.daylightContext(from: daylight(30, days: 20)).circadianReliability == 0.6)

        let middle = EnvironmentEngine.daylightContext(from: daylight(90, days: 20))
        #expect(abs(middle.circadianReliability - 0.8) < 1e-9)
    }

    /// Even a user who never goes outside still has sleep timing, which is the curve's
    /// primary anchor — so reliability floors rather than collapsing.
    @Test("Güvenilirlik tabanı 0.6")
    func reliabilityHasAFloor() {
        #expect(EnvironmentEngine.daylightContext(from: daylight(0, days: 20)).circadianReliability == 0.6)
    }

    @Test("Az veride iddia yok")
    func requiresEnoughDays() {
        let context = EnvironmentEngine.daylightContext(from: daylight(30, days: 3))
        #expect(!context.hasData)
        #expect(context.summary == nil)
    }

    // MARK: - Time zones

    @Test("Saat dilimi değişimi yakalanır ve yönü doğru")
    func detectsTimeZoneShift() throws {
        var days: [BiometricDaySnapshot] = []
        for offset in (0..<10).reversed() {
            let zone = offset < 4 ? "Asia/Tokyo" : "Europe/Istanbul"
            days.append(sample(daysAgo: offset, zone: zone))
        }
        let shift = try #require(EnvironmentEngine.recentTimeZoneShift(in: days))
        #expect(shift.to == "Asia/Tokyo")
        #expect(shift.hours > 0, "İstanbul'dan Tokyo'ya doğuya gidiş pozitif olmalı")
        #expect(shift.adaptationDays > 0)
        #expect(SafetyFilter.isSafe(shift.summary))
    }

    @Test("Aynı dilimde değişim bildirilmez")
    func noShiftWhenStationary() {
        let days = (0..<10).reversed().map { sample(daysAgo: $0, zone: "Europe/Istanbul") }
        #expect(EnvironmentEngine.recentTimeZoneShift(in: days) == nil)
    }

    /// Advancing the clock is harder than delaying it, because the free-running human day
    /// runs slightly over twenty-four hours.
    @Test("Doğuya gidiş batıya gidişten uzun sürer")
    func eastwardTakesLonger() {
        let east = TimeZoneShift(from: "A", to: "B", date: now, hours: 8)
        let west = TimeZoneShift(from: "B", to: "A", date: now, hours: -8)
        #expect(east.adaptationDays > west.adaptationDays)
    }

    @Test("Adaptasyon süresi içinde aktif, sonrasında pasif")
    func adaptingWindowRespectsAdaptationDays() {
        let shift = TimeZoneShift(from: "Europe/London", to: "Europe/Istanbul", date: now, hours: 3)
        let dayWithin = now.addingTimeInterval(Double(shift.adaptationDays - 1) * 86_400)
        let dayExpired = now.addingTimeInterval(Double(shift.adaptationDays + 2) * 86_400)
        #expect(EnvironmentEngine.isAdapting(to: shift, on: dayWithin, calendar: calendar))
        #expect(!EnvironmentEngine.isAdapting(to: shift, on: dayExpired, calendar: calendar))
    }

    private func sample(daysAgo: Int, zone: String) -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400)),
            timeZoneIdentifier: zone,
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
            sleepDurationSeconds: 8 * 3600,
            sleepScore: 80,
            sleepEfficiency: 0.9,
            deepSeconds: 4_000,
            remSeconds: 5_000,
            coreSeconds: 16_000,
            awakeSeconds: 1_000,
            timeInBedSeconds: 8.5 * 3600,
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
