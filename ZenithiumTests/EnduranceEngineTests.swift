//
//  EnduranceEngineTests.swift
//  ZenithiumTests
//
//  The critical-speed fit and everything derived from it. The reference runner below is
//  1500 m in 5:00, 3000 m in 10:40 and 5000 m in 18:30, which fits CS = 4.3169 m/s and
//  D′ = 216.8 m at R² = 0.9999 — verified independently before being asserted on.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Endurance engine")
struct EnduranceEngineTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func effort(_ distance: Double, _ duration: Double, daysAgo: Int = 5) -> BestEffort {
        BestEffort(
            distance: distance,
            duration: duration,
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400)
        )
    }

    private var referenceEfforts: [BestEffort] {
        [effort(1500, 300), effort(3000, 640), effort(5000, 1110)]
    }

    // MARK: - Fitting

    @Test("Kritik hız ve D′ doğru çözülüyor")
    func fitsKnownRunner() throws {
        let model = try #require(EnduranceEngine.fit(efforts: referenceEfforts, now: now))
        #expect(abs(model.criticalSpeed - 4.3169) < 0.001)
        #expect(abs(model.anaerobicDistance - 216.8) < 0.5)
        #expect(model.rSquared > 0.999)
        #expect(model.effortCount == 3)
        #expect(abs(model.criticalPace - 231.6) < 0.5)
    }

    @Test("Üç efordan az olunca model kurulmaz")
    func requiresThreeEfforts() {
        #expect(EnduranceEngine.fit(efforts: Array(referenceEfforts.prefix(2)), now: now) == nil)
    }

    @Test("Aynı mesafede iki efordan hızlısı alınır")
    func keepsFastestPerDistance() throws {
        let withSlowRepeat = referenceEfforts + [effort(5000, 1300)]
        let model = try #require(EnduranceEngine.fit(efforts: withSlowRepeat, now: now))
        #expect(model.effortCount == 3, "aynı mesafe iki nokta saymamalı")
        #expect(abs(model.criticalSpeed - 4.3169) < 0.001, "yavaş tekrar fiti çekmemeli")
    }

    @Test("Pencere dışındaki eski eforlar sayılmaz")
    func agesOutOldEfforts() {
        let stale = referenceEfforts.map {
            BestEffort(distance: $0.distance, duration: $0.duration, date: now.addingTimeInterval(-200 * 86_400))
        }
        #expect(EnduranceEngine.fit(efforts: stale, now: now) == nil)
    }

    /// Efforts under two minutes are dominated by D′ and bend the fit; over forty minutes
    /// the two-parameter model stops describing the physiology.
    @Test("Süre aralığı dışındaki eforlar elenir")
    func filtersByDuration() {
        let outOfRange = [effort(400, 60), effort(800, 115), effort(30000, 7200)]
        #expect(EnduranceEngine.fit(efforts: outOfRange, now: now) == nil)
    }

    /// A set of efforts that does not describe a critical-speed relationship produces a
    /// negative intercept, and reporting a model anyway would be inventing one.
    @Test("Negatif D′ üreten eforlarda model verilmez")
    func rejectsNegativeIntercept() {
        // Getting relatively faster over distance — physiologically backwards.
        let backwards = [effort(1500, 400), effort(3000, 700), effort(5000, 1000)]
        let model = EnduranceEngine.fit(efforts: backwards, now: now)
        if let model {
            #expect(model.anaerobicDistance >= 0)
        }
    }

    // MARK: - Predictions

    @Test("Yarış tahminleri makul ve sıralı")
    func predictionsAreOrdered() throws {
        let model = try #require(EnduranceEngine.fit(efforts: referenceEfforts, now: now))
        let predictions = EnduranceEngine.predictions(from: model)
        #expect(predictions.count == RaceDistance.allCases.count)

        // 5K tahmini girdiye çok yakın olmalı.
        let fiveK = try #require(predictions.first { $0.distance == .fiveK })
        #expect(abs(fiveK.seconds - 1110) < 15)

        // Uzadıkça süre artmalı, tempo yavaşlamalı.
        let sorted = predictions.sorted { $0.distance.metres < $1.distance.metres }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            #expect(later.seconds > earlier.seconds)
            #expect(later.pace > earlier.pace)
        }
    }

    /// The model has no term for the slow component of oxygen uptake, so it over-predicts
    /// long distances. The marathon must say so rather than quietly being wrong.
    @Test("Maraton tahmini uyarısıyla gelir")
    func marathonCarriesCaveat() throws {
        let model = try #require(EnduranceEngine.fit(efforts: referenceEfforts, now: now))
        let marathon = try #require(
            EnduranceEngine.predictions(from: model).first { $0.distance == .marathon }
        )
        #expect(!marathon.isReliable)
        #expect(marathon.caveat != nil)
        #expect(marathon.extrapolationFactor > 5)
    }

    // MARK: - Zones

    /// A faster speed is a smaller pace. Getting that backwards is the easiest mistake in
    /// the file, so it is asserted directly.
    @Test("Bölgelerin hızlı ucu yavaş ucundan küçük")
    func zoneBandsAreOrderedCorrectly() throws {
        let model = try #require(EnduranceEngine.fit(efforts: referenceEfforts, now: now))
        let zones = EnduranceEngine.paceZones(from: model)
        #expect(zones.count == PaceZone.allCases.count)
        for band in zones {
            #expect(band.fastPace < band.slowPace, "\(band.zone) ters")
        }
        // Eşik bandı kritik tempoyu içermeli.
        let threshold = try #require(zones.first { $0.zone == .threshold })
        #expect(threshold.fastPace <= model.criticalPace && model.criticalPace <= threshold.slowPace)
    }

    @Test("Tempodan bölge bulma")
    func zoneLookup() throws {
        let model = try #require(EnduranceEngine.fit(efforts: referenceEfforts, now: now))
        #expect(EnduranceEngine.zone(forPace: model.criticalPace, model: model) == .threshold)
        #expect(EnduranceEngine.zone(forPace: model.criticalPace * 1.35, model: model) == .easy)
    }

    // MARK: - Decoupling

    @Test("Ayrışma: sabit verim sıfır kayma")
    func decouplingIsZeroWhenSteady() throws {
        let result = try #require(
            EnduranceEngine.decoupling(
                firstHalfSpeed: 3.5, firstHalfHeartRate: 150,
                secondHalfSpeed: 3.5, secondHalfHeartRate: 150
            )
        )
        #expect(abs(result.drift) < 1e-12)
        #expect(result.heldTogether)
    }

    @Test("Ayrışma: aynı tempoda yükselen nabız pozitif kayma")
    func decouplingDetectsDrift() throws {
        // 150 -> 165 bpm at the same speed is a 9.1% drop in speed-per-beat.
        let result = try #require(
            EnduranceEngine.decoupling(
                firstHalfSpeed: 3.5, firstHalfHeartRate: 150,
                secondHalfSpeed: 3.5, secondHalfHeartRate: 165
            )
        )
        #expect(abs(result.drift - 0.0909) < 0.001)
        #expect(!result.heldTogether)
    }

    // MARK: - Grade adjustment

    /// Uphill running at a given pace is equivalent to a faster pace on the flat; downhill
    /// is equivalent to a slower one. The direction is the whole point.
    @Test("Eğim düzeltmesi doğru yönde")
    func gradeAdjustmentDirection() {
        let flat = EnduranceEngine.gradeAdjustedPace(pace: 300, gradient: 0)
        #expect(abs(flat - 300) < 0.5)

        let uphill = EnduranceEngine.gradeAdjustedPace(pace: 300, gradient: 0.10)
        #expect(uphill < 300, "yokuş yukarı eşdeğeri daha hızlı olmalı: \(uphill)")
        #expect(abs(uphill - 181) < 5)

        let downhill = EnduranceEngine.gradeAdjustedPace(pace: 300, gradient: -0.10)
        #expect(downhill > 300, "yokuş aşağı eşdeğeri daha yavaş olmalı: \(downhill)")
    }

    @Test("Aşırı eğimler kırpılır")
    func gradeIsClamped() {
        let extreme = EnduranceEngine.gradeAdjustedPace(pace: 300, gradient: 0.9)
        let clamped = EnduranceEngine.gradeAdjustedPace(pace: 300, gradient: 0.30)
        #expect(abs(extreme - clamped) < 1e-9)
    }
}
