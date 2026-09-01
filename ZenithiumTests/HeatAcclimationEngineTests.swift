//
//  HeatAcclimationEngineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C7 — heat adaptation from the sessions actually done in it.
//
//  The model encodes a time course, so the time course is what the tests check: most of the
//  effect inside a week, the plateau at about two weeks, and decay over two to three weeks
//  without exposure. A bounded accumulation is easy to write and easy to get subtly wrong —
//  a naive step reaches about sixty per cent in fourteen days, which contradicts the very
//  literature it is meant to encode.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Heat acclimation")
struct HeatAcclimationEngineTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// `count` consecutive daily sessions ending today.
    private func sessions(
        count: Int,
        temperature: Double,
        minutes: Double = 60,
        humidity: Double? = nil,
        endingDaysAgo: Int = 0
    ) -> [HeatExposure] {
        (0..<count).map { offset in
            HeatExposure(
                date: now.addingTimeInterval(-Double(endingDaysAgo + count - 1 - offset) * 86_400),
                temperatureCelsius: temperature,
                humidity: humidity,
                minutes: minutes
            )
        }
    }

    private func state(_ exposures: [HeatExposure]) -> HeatAcclimationState {
        HeatAcclimationEngine.state(exposures: exposures, now: now, calendar: calendar)
    }

    // MARK: - Time course

    @Test("İki hafta günlük sıcak seans platoya yaklaştırıyor")
    func twoWeeksReachesThePlateau() {
        let result = state(sessions(count: 14, temperature: 33))
        #expect(result.adaptation > 0.85, "14 gün sonra \(result.adaptation)")
        #expect(result.isEstablished)
    }

    @Test("Bir hafta etkinin çoğunu getiriyor")
    func oneWeekBringsMostOfIt() {
        let week = state(sessions(count: 7, temperature: 33))
        let fortnight = state(sessions(count: 14, temperature: 33))
        #expect(week.adaptation > 0.6, "7 gün sonra \(week.adaptation)")
        #expect(week.adaptation < fortnight.adaptation)
    }

    @Test("Üç hafta arayla uyum büyük ölçüde kayboluyor")
    func threeWeeksAwayLosesIt() {
        let adapted = state(sessions(count: 14, temperature: 33))
        let lapsed = state(sessions(count: 14, temperature: 33, endingDaysAgo: 21))
        #expect(lapsed.adaptation < adapted.adaptation * 0.3, "\(lapsed.adaptation) vs \(adapted.adaptation)")
        #expect(lapsed.isDecaying)
    }

    @Test("Birkaç günlük ara uyumu düşürmüyor")
    func ashortBreakKeepsIt() {
        let adapted = state(sessions(count: 14, temperature: 33))
        let paused = state(sessions(count: 14, temperature: 33, endingDaysAgo: 3))
        #expect(abs(paused.adaptation - adapted.adaptation) < 0.001)
        #expect(!paused.isDecaying)
    }

    // MARK: - Dose

    @Test("Eşiğin altındaki seanslar sayılmıyor", arguments: [10.0, 18.0, 23.5])
    func coolSessionsDoNotCount(temperature: Double) {
        let result = state(sessions(count: 14, temperature: temperature))
        #expect(result.adaptation == 0)
        #expect(result.exposures.isEmpty)
        #expect(HeatAcclimationEngine.summary(for: result) == nil)
    }

    @Test("Daha sıcak seans daha çok katkı veriyor")
    func hotterSessionsContributeMore() {
        let warm = state(sessions(count: 10, temperature: 27))
        let hot = state(sessions(count: 10, temperature: 34))
        #expect(hot.adaptation > warm.adaptation)
    }

    @Test("Kısa seans oransal katkı veriyor")
    func shortSessionsContributeProportionally() {
        let full = state(sessions(count: 10, temperature: 33, minutes: 60))
        let half = state(sessions(count: 10, temperature: 33, minutes: 30))
        #expect(half.adaptation < full.adaptation)
        #expect(half.adaptation > 0)
    }

    @Test("Çok uzun seans doymuş katkı veriyor")
    func verylongSessionsSaturate() {
        #expect(
            HeatAcclimationEngine.increment(
                for: HeatExposure(date: now, temperatureCelsius: 33, humidity: nil, minutes: 240)
            ) == HeatAcclimationEngine.increment(
                for: HeatExposure(date: now, temperatureCelsius: 33, humidity: nil, minutes: 60)
            )
        )
    }

    // MARK: - Humidity

    @Test("Nem etkin sıcaklığı yükseltiyor")
    func humidityRaisesTheEffectiveTemperature() {
        let dry = HeatExposure(date: now, temperatureCelsius: 30, humidity: 0.3, minutes: 60)
        let humid = HeatExposure(date: now, temperatureCelsius: 30, humidity: 0.9, minutes: 60)
        #expect(
            HeatAcclimationEngine.effectiveTemperature(for: humid)
                > HeatAcclimationEngine.effectiveTemperature(for: dry)
        )
        #expect(
            HeatAcclimationEngine.effectiveTemperature(for: humid)
                <= 30 + HeatAcclimationEngine.humidityPenaltyCelsius
        )
    }

    @Test("Nem kaydı yoksa kuru sıcaklık kullanılıyor")
    func withoutHumidityTheDryTemperatureIsUsed() {
        let exposure = HeatExposure(date: now, temperatureCelsius: 31, humidity: nil, minutes: 60)
        #expect(HeatAcclimationEngine.effectiveTemperature(for: exposure) == 31)
    }

    // MARK: - Sources

    @Test("Hava verisi olmayan antrenmanlar atlanıyor")
    func workoutsWithoutWeatherAreSkipped() {
        let workouts = [
            WorkoutSummary(
                id: UUID(),
                activity: .running,
                interval: DateInterval(start: now, duration: 3_600),
                activeEnergyKilocalories: nil,
                distanceMeters: 10_000,
                averageHeartRate: 150,
                sourceBundleIdentifier: nil,
                ambientTemperatureCelsius: nil,
                ambientHumidity: nil
            ),
            WorkoutSummary(
                id: UUID(),
                activity: .running,
                interval: DateInterval(start: now, duration: 3_600),
                activeEnergyKilocalories: nil,
                distanceMeters: 10_000,
                averageHeartRate: 150,
                sourceBundleIdentifier: nil,
                ambientTemperatureCelsius: 31,
                ambientHumidity: 0.6
            )
        ]
        let exposures = HeatAcclimationEngine.exposures(from: workouts)
        #expect(exposures.count == 1)
        #expect(exposures.first?.temperatureCelsius == 31)
        #expect(abs((exposures.first?.minutes ?? 0) - 60) < 0.001)
    }

    // MARK: - §1

    @Test("Özet havayla ilgili bir emir vermiyor")
    func thesummaryGivesNoWeatherOrders() {
        for days in [3, 8, 14] {
            for offset in [0, 10] {
                let result = state(sessions(count: days, temperature: 33, endingDaysAgo: offset))
                guard let text = HeatAcclimationEngine.summary(for: result)?.lowercased() else { continue }
                for word in ["kaçın", "erteleme", "erteleyin", "çıkma", "antrenman yapma", "iptal"] {
                    #expect(!text.contains(word), "\(word)")
                }
            }
        }
    }
}
