//
//  BloodworkTimelineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C3 — the rate of change and the panel grouping.
//
//  §12 governs both. Neither of these may judge a direction; the rate is a number with a
//  sign and the grouping is an ordering. The tests check the arithmetic and the refusals —
//  in particular that a trend is *not* produced from too few draws or too short a span,
//  because a confident-looking slope through two draws six weeks apart is the exact failure
//  mode this feature has to avoid.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Marker rate of change")
struct MarkerRateTests {

    private let reference = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("Düz bir yükseliş yıllık hıza doğru çevriliyor")
    func steadyRiseBecomesAnAnnualRate() throws {
        // Four draws a year apart, rising ten units a year.
        let series = makeSeries(
            values: [100, 110, 120, 130],
            daysAgo: [1_095, 730, 365, 0]
        )
        let rate = try #require(series.annualRate)
        #expect(abs(rate - 10) < 0.05)
    }

    @Test("Düşüş negatif hız veriyor")
    func fallProducesANegativeRate() throws {
        let series = makeSeries(values: [80, 65, 50], daysAgo: [730, 365, 0])
        let rate = try #require(series.annualRate)
        #expect(rate < 0)
        #expect(abs(rate + 15) < 0.05)
    }

    @Test("Sabit bir değer sıfır hız veriyor")
    func flatSeriesHasNoSlope() throws {
        let series = makeSeries(values: [44, 44, 44], daysAgo: [730, 365, 0])
        let rate = try #require(series.annualRate)
        #expect(abs(rate) < 0.000_001)
    }

    @Test("İki ölçüm trend sayılmıyor")
    func twoDrawsAreNotATrend() {
        let series = makeSeries(values: [100, 140], daysAgo: [400, 0])
        #expect(series.annualRate == nil)
    }

    @Test("Altı aydan kısa aralık trend sayılmıyor")
    func aShortSpanIsNotATrend() {
        // Three draws, but all inside six weeks: the slope would be dominated by which
        // morning the blood was taken.
        let series = makeSeries(values: [100, 130, 160], daysAgo: [42, 21, 0])
        #expect(series.annualRate == nil)
    }

    @Test("Tam sınırda olan aralık kabul ediliyor")
    func exactlyTheMinimumSpanCounts() {
        let span = BloodworkViewModel.MarkerSeries.minimumSpanDaysForRate
        let series = makeSeries(values: [100, 110, 120], daysAgo: [span, span / 2, 0])
        #expect(series.annualRate != nil)
    }

    @Test("Ölçümlerin sırası sonucu değiştirmiyor")
    func orderDoesNotMatter() throws {
        let ascending = makeSeries(values: [100, 110, 120], daysAgo: [730, 365, 0])
        let shuffled = BloodworkViewModel.MarkerSeries(
            marker: ascending.marker,
            entries: ascending.entries.shuffled()
        )
        let first = try #require(ascending.annualRate)
        let second = try #require(shuffled.annualRate)
        #expect(abs(first - second) < 0.000_001)
    }

    private func makeSeries(values: [Double], daysAgo: [Double]) -> BloodworkViewModel.MarkerSeries {
        let entries = zip(values, daysAgo).map { value, days in
            BloodMarkerSnapshot(
                id: UUID(),
                marker: .ferritin,
                value: value,
                unitSymbol: "ng/mL",
                referenceRange: MarkerRange(minimum: 15, maximum: 150),
                optimalRange: MarkerRange(minimum: 40, maximum: 100),
                drawnAt: reference.addingTimeInterval(-days * 86_400),
                note: ""
            )
        }
        // The view model keeps series newest first.
        return BloodworkViewModel.MarkerSeries(
            marker: .ferritin,
            entries: entries.sorted { $0.drawnAt > $1.drawnAt }
        )
    }
}

@Suite("Panel grouping")
struct PanelGroupingTests {

    private let reference = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("Paneller katalog sırasında geliyor")
    func panelsFollowCatalogueOrder() {
        let groups = BloodworkViewModel.groupByPanel([
            series(for: .ferritin),
            series(for: .apoB),
            series(for: .highSensitivityCRP)
        ])
        let orders = groups.map(\.panel.order)
        #expect(orders == orders.sorted())
    }

    @Test("Boş panel görünmüyor")
    func emptyPanelsAreAbsent() {
        let groups = BloodworkViewModel.groupByPanel([series(for: .ferritin)])
        #expect(groups.count == 1)
        #expect(groups.first?.series.count == 1)
    }

    @Test("Katalogda olmayan belirteç bir panele zorlanmıyor")
    func unknownMarkersAreNotFiledUnderAGuess() {
        let custom = BloodMarkerKind.custom("kendi ölçümüm")
        let groups = BloodworkViewModel.groupByPanel([series(for: custom)])
        #expect(groups.isEmpty)
    }

    @Test("Panel içindeki belirteçler ada göre sıralı")
    func markersWithinAPanelAreSortedByName() {
        let markers = BiomarkerCatalog.definitions(in: .lipid).prefix(3).map {
            BloodMarkerKind.standard($0.key)
        }
        guard markers.count >= 2 else { return }
        let groups = BloodworkViewModel.groupByPanel(markers.map { series(for: $0) })
        guard let names = groups.first?.series.map(\.marker.displayName) else { return }
        #expect(names == names.sorted())
    }

    private func series(for marker: BloodMarkerKind) -> BloodworkViewModel.MarkerSeries {
        BloodworkViewModel.MarkerSeries(
            marker: marker,
            entries: [
                BloodMarkerSnapshot(
                    id: UUID(),
                    marker: marker,
                    value: 50,
                    unitSymbol: "",
                    referenceRange: .unbounded,
                    optimalRange: .unbounded,
                    drawnAt: reference,
                    note: ""
                )
            ]
        )
    }
}
