//
//  ReferenceNormsTests.swift
//  ZenithiumTests
//
//  The reference overlay, and the gate that keeps it off until its table is verified.
//
//  Every test that needs table data is written to hold in both states: it asserts the
//  refusal while the table is empty, and the real property once it is filled. That is
//  deliberate — a suite that only passes in one of the two states either fails today or
//  stops guarding tomorrow, and this table is going to be filled by somebody who is not
//  reading this file at the time.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Reference norms")
struct ReferenceNormsTests {

    // MARK: - The verification gate

    /// The one invariant that cannot be allowed to drift: the flag and the table agree.
    ///
    /// Flipping `isPublicationVerified` without filling the table would ship a feature that
    /// silently does nothing; filling the table without flipping the flag would leave
    /// verified numbers switched off. Both are quiet, and both fail here.
    @Test("Doğrulama bayrağı ile tablo aynı şeyi söylüyor")
    func theFlagAndTheTableAgree() {
        let hasData = !ReferenceNorms.maleTreadmill.isEmpty
            && !ReferenceNorms.femaleTreadmill.isEmpty
        #expect(
            hasData == ReferenceNorms.isPublicationVerified,
            hasData
                ? "tablo dolu ama isPublicationVerified false"
                : "isPublicationVerified true ama tablo boş"
        )
        #expect(
            (ReferenceNorms.source != nil) == ReferenceNorms.isPublicationVerified,
            "doğrulanmış bir tablo kaynağını söylemek zorunda"
        )
    }

    @Test("İki cinsiyet tablosu aynı yaş bantlarını kapsıyor")
    func bothSexesCoverTheSameBands() {
        #expect(
            Set(ReferenceNorms.maleTreadmill.keys) == Set(ReferenceNorms.femaleTreadmill.keys),
            "bir cinsiyette olan bant öbüründe yok"
        )
    }

    // MARK: - Refusals
    //
    // These hold whatever the table contains, which is why they are the tests that matter
    // most: they are the app's promise not to compare somebody against a group it has no
    // data for.

    @Test("Yaş bilinmiyorsa karşılaştırma yok")
    func withoutAnAgeThereIsNoBand() {
        #expect(ReferenceNorms.vo2MaxPosition(value: 48, age: nil, biologicalSex: .male) == nil)
    }

    @Test("Cinsiyet kayıtlı değilse karşılaştırma yok")
    func withoutASexThereIsNoBand() {
        #expect(ReferenceNorms.vo2MaxPosition(value: 48, age: 35, biologicalSex: .notSet) == nil)
        #expect(ReferenceNorms.vo2MaxPosition(value: 48, age: 35, biologicalSex: .other) == nil)
    }

    /// Under eighteen and over the table's oldest band. Neither gets an extrapolation.
    @Test("Tablo dışındaki yaşlar için bant uydurulmuyor", arguments: [0, 5, 12, 17, 18, 19, 90, 95, 120])
    func agesOutsideTheTableAreRefused(age: Int) {
        #expect(ReferenceNorms.vo2MaxBand(age: age, biologicalSex: .male) == nil)
        #expect(ReferenceNorms.vo2MaxBand(age: age, biologicalSex: .female) == nil)
        #expect(ReferenceNorms.vo2MaxPosition(value: 45, age: age, biologicalSex: .male) == nil)
    }

    @Test("Sıfır veya negatif ölçüm karşılaştırılmıyor")
    func aNonPositiveValueIsRefused() {
        #expect(ReferenceNorms.vo2MaxPosition(value: 0, age: 35, biologicalSex: .male) == nil)
        #expect(ReferenceNorms.vo2MaxPosition(value: -3, age: 35, biologicalSex: .male) == nil)
    }

    @Test("Doğrulanmamış tablo hiçbir yaşta karşılaştırma üretmiyor")
    func anUnverifiedTableComparesNothing() {
        guard !ReferenceNorms.isPublicationVerified else { return }
        for age in stride(from: 20, through: 89, by: 1) {
            #expect(
                ReferenceNorms.vo2MaxPosition(value: 45, age: age, biologicalSex: .male) == nil,
                "\(age) yaşında doğrulanmamış tablodan karşılaştırma sızdı"
            )
        }
    }

    // MARK: - The table, once it exists

    @Test("Kapsanan her bantta iki cinsiyet için de satır var")
    func everyCoveredBandHasBothSexes() throws {
        for band in ReferenceNorms.coveredBands {
            for sex in [BiologicalSexValue.male, .female] {
                let row = try #require(
                    ReferenceNorms.vo2MaxPercentiles(age: band + 5, biologicalSex: sex),
                    "\(band)/\(sex)"
                )
                #expect(row.isMonotonic, "\(band)/\(sex): persentiller artmıyor")
                #expect(row.p10 > 0, "\(band)/\(sex)")
            }
        }
    }

    @Test("Ortancalar yaşla azalıyor")
    func mediansFallWithAge() throws {
        for sex in [BiologicalSexValue.male, .female] {
            var previous: Double?
            for band in ReferenceNorms.coveredBands {
                let row = try #require(ReferenceNorms.vo2MaxPercentiles(age: band, biologicalSex: sex))
                if let previous {
                    #expect(row.p50 < previous, "\(band) bandı bir öncekinden yüksek")
                }
                previous = row.p50
            }
        }
    }

    /// The anchors the primary abstracts state outright. A transcription slip fails here.
    @Test("Yayımlanmış ortancalar tabloyla uyuşuyor")
    func publishedMediansMatchTheTable() throws {
        guard ReferenceNorms.isPublicationVerified else { return }
        let source = try #require(ReferenceNorms.source)
        let anchors = try #require(
            ReferenceNorms.publishedMedians[source],
            "kaynak '\(source)' için çıpa kaydı yok — publishedMedians'a ekle"
        )
        for (band, expected) in anchors {
            let male = try #require(ReferenceNorms.vo2MaxPercentiles(age: band, biologicalSex: .male))
            let female = try #require(ReferenceNorms.vo2MaxPercentiles(age: band, biologicalSex: .female))
            #expect(abs(male.p50 - expected.male) < 0.05, "\(band) erkek ortancası")
            #expect(abs(female.p50 - expected.female) < 0.05, "\(band) kadın ortancası")
        }
    }

    @Test("Bant eşlemesi doğru", arguments: [(20, 20), (29, 20), (30, 30), (45, 40), (79, 70)])
    func bandsMapCorrectly(age: Int, expected: Int) {
        guard !ReferenceNorms.coveredBands.isEmpty else {
            #expect(ReferenceNorms.band(for: age) == nil)
            return
        }
        #expect(ReferenceNorms.band(for: age) == expected)
    }

    // MARK: - Position arithmetic
    //
    // Exercised against a literal row rather than the table, so the interpolation is tested
    // today and stays tested whatever the table ends up containing.

    private let row = VO2MaxPercentiles(p10: 30.0, p25: 35.1, p50: 41.0, p75: 47.4, p90: 53.2)

    private func position(_ value: Double) -> NormPosition {
        NormPosition(
            value: value,
            percentiles: row,
            ageBand: 40,
            ageBandWidth: 10,
            biologicalSex: .male
        )
    }

    @Test("Yayımlanmış her nokta kendi persentiline düşüyor")
    func eachPublishedPointLandsOnItsOwnPercentile() {
        for (value, percentile) in row.points {
            #expect(
                abs(position(value).approximatePercentile - percentile) < 0.001,
                "\(value) → \(percentile)"
            )
        }
    }

    @Test("Konum monoton artıyor")
    func thePositionIsMonotonic() {
        var previous: Double = -1
        for value in stride(from: 1.0, through: 90.0, by: 0.5) {
            let percentile = position(value).approximatePercentile
            #expect(percentile >= previous, "\(value) geriye gitti")
            previous = percentile
        }
    }

    @Test("Uçlar sınırlanıyor, dışarıya uzatılmıyor")
    func theExtremesAreClampedRatherThanExtrapolated() {
        #expect(position(1).approximatePercentile >= 0.02)
        #expect(position(1).approximatePercentile <= 0.10)
        #expect(position(300).approximatePercentile <= 0.98)
        #expect(position(300).approximatePercentile >= 0.90)
    }

    @Test("Ara değerler iki yayımlanmış nokta arasında kalıyor")
    func interpolatedValuesStayBetweenTheirNeighbours() {
        // Halfway between p25 and p50 sits halfway between 25% and 50%.
        let midpoint = (row.p25 + row.p50) / 2
        let percentile = position(midpoint).approximatePercentile
        #expect(percentile > 0.25)
        #expect(percentile < 0.50)
        #expect(abs(percentile - 0.375) < 0.01)
    }

    @Test("Artan satır monotonluk kontrolünden geçiyor, karışık satır geçmiyor")
    func monotonicityDetectsASwappedColumn() {
        #expect(row.isMonotonic)
        let swapped = VO2MaxPercentiles(p10: 30.0, p25: 41.0, p50: 35.1, p75: 47.4, p90: 53.2)
        #expect(!swapped.isMonotonic)
    }

    // MARK: - §12

    @Test("Özet bir konum bildiriyor, bir hüküm değil")
    func theSummaryStatesAPositionOnly() {
        for value in [22.0, 35.0, 48.0, 62.0] {
            let text = position(value).summary.lowercased()
            #expect(text.contains("tanı değil"))
            #expect(text.contains("40–49"))
            for word in ["riskli", "düşük risk", "sağlıksız", "hastalık", "iyi durumda", "kötü"] {
                #expect(!text.contains(word), "\(value): \(word)")
            }
        }
    }
}
