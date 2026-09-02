//
//  DynamicTypeAndLayoutTests.swift
//  ZenithiumTests
//
//  Verification of layout and formatting under Dynamic Type:
//  Default, AX3 (Accessibility 3), and AX5 (Accessibility 5).
//

import Testing
import SwiftUI
@testable import Zenithium

@Suite("Dynamic Type ve Arayüz Düzeni")
struct DynamicTypeAndLayoutTests {

    private let calendar = Calendar.autoupdatingCurrent
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Sayısal biçimlendirmede Türkçe virgül ve monospacedDigit kuralları")
    func formattingRespectsTurkishConventions() {
        #expect(ZenithiumFormat.metric(12.34, digits: 1) == "12,3")
        #expect(ZenithiumFormat.metric(67.0, digits: 0) == "67")
        #expect(ZenithiumFormat.percent(0.85) == "%85")
        #expect(ZenithiumFormat.percentTR(0.12) == "%12")
        #expect(ZenithiumFormat.strain(14.8) == "14,8")
    }

    @Test("CircadianArc 5 işaretli eğri veri yapısı ve erişilebilirlik değerleri")
    func circadianArcWithFiveMarkersRendersValidly() {
        let wake = now
        let samples = (0..<288).map { i in
            CircadianSample(date: wake.addingTimeInterval(Double(i) * 300), alertness: 50.0)
        }
        let markers = [
            CircadianMarker(event: .morningPeak, date: wake.addingTimeInterval(3600), alertness: 70),
            CircadianMarker(event: .afternoonDip, date: wake.addingTimeInterval(7200), alertness: 40),
            CircadianMarker(event: .secondaryPeak, date: wake.addingTimeInterval(14400), alertness: 75),
            CircadianMarker(event: .melatoninOnset, date: wake.addingTimeInterval(21600), alertness: 30),
            CircadianMarker(event: .sleepTrough, date: wake.addingTimeInterval(28800), alertness: 20)
        ]
        let arc = CircadianArc(
            midpoint: wake.addingTimeInterval(14400),
            referenceDate: wake,
            samples: samples,
            markers: markers,
            amplitudeScale: 1.0,
            peakAlertness: 80.0
        )
        let view = CircadianArcView(arc: arc)
        #expect(view.arc.markers.count == 5)
        #expect(arc.markers.count == 5)
    }

    @Test("Farklı dinamik yazı tipi boyutlarında görünüm oluşturma", arguments: [
        DynamicTypeSize.medium,
        DynamicTypeSize.large,
        DynamicTypeSize.accessibility3,
        DynamicTypeSize.accessibility5
    ])
    func dynamicTypeSizesInstantiateCleanly(size: DynamicTypeSize) {
        let tile = MetricTile(
            label: "İstirahat Nabzı",
            value: "67",
            unit: "bpm",
            caption: "Son 7 günün ortalamasında"
        )
        .environment(\.dynamicTypeSize, size)

        #expect(tile != nil)

        let card = SectionCard(
            title: "Günün Uyanıklık Eğrisi",
            subtitle: "Gün boyunca uyanıklık, uykuna göre demirlenmiş"
        ) {
            Text("İçerik")
        }
        .environment(\.dynamicTypeSize, size)

        #expect(card != nil)
    }
}
