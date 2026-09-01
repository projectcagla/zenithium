//
//  LabReportParserTests.swift
//  ZenithiumTests
//
//  The laboratory parser. Every case here is a line shape a real Turkish report prints,
//  and the assertions are about the two things that can silently go wrong: reading a digit
//  out of a marker's own name, and mistaking a reference band for a result.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Lab report parser")
struct LabReportParserTests {

    private func parsed(_ line: String) throws -> ParsedLabValue {
        switch LabReportParser.parseLine(line) {
        case .parsed(let value):
            return value
        case .namedButUnreadable:
            Issue.record("Belirteç bulundu ama sayı okunamadı: \(line)")
            throw ParseTestFailure.unreadable
        case .notALabLine:
            Issue.record("Satır tahlil satırı sayılmadı: \(line)")
            throw ParseTestFailure.notALabLine
        }
    }

    enum ParseTestFailure: Error {
        case unreadable
        case notALabLine
    }

    // MARK: - The digits-in-the-name trap

    @Test("B12'nin adındaki 12 sonuç sanılmaz")
    func doesNotReadDigitsFromMarkerName() throws {
        let value = try parsed("B12 Vitamini                350       pg/mL      200 - 900")
        #expect(value.marker.storageKey == "vitaminB12")
        #expect(value.value == 350)
        #expect(value.unitSymbol == "pg/mL")
        #expect(value.printedRange == MarkerRange(minimum: 200, maximum: 900))
    }

    @Test("HbA1c'nin adındaki 1 sonuç sanılmaz")
    func handlesHbA1c() throws {
        let value = try parsed("HbA1c                       5,4       %          4.0 - 5.6")
        #expect(value.marker.storageKey == "hba1c")
        #expect(value.value == 5.4)
    }

    @Test("Serbest T4'ün adındaki 4 sonuç sanılmaz")
    func handlesFreeT4() throws {
        let value = try parsed("Serbest T4                  1,15      ng/dL      0,80 - 1,80")
        #expect(value.marker.storageKey == "freeT4")
        #expect(value.value == 1.15)
    }

    // MARK: - Ranges

    @Test("Parantez içindeki aralık sonuç sayılmaz")
    func ignoresParentheticalRange() throws {
        let value = try parsed("Ferritin                    45,2      ng/mL      (30 - 400)")
        #expect(value.marker.storageKey == "ferritin")
        #expect(value.value == 45.2)
        #expect(value.printedRange == MarkerRange(minimum: 30, maximum: 400))
    }

    @Test("Tek taraflı sınır aralık olarak alınmaz")
    func doesNotTakeSingleBoundAsRange() throws {
        let value = try parsed("HDL Kolesterol              58        mg/dL      > 40")
        #expect(value.value == 58)
        // "> 40" iki taraflı değil; laboratuvarın bandı olarak kaydedilmez.
        #expect(value.printedRange == nil)
    }

    @Test("Değerden sonra basılan aralık sonucu bozmaz")
    func rangeAfterValue() throws {
        let value = try parsed("Total Kolesterol 190 mg/dL 0 - 200")
        #expect(value.marker.storageKey == "totalCholesterol")
        #expect(value.value == 190)
        #expect(value.printedRange == MarkerRange(minimum: 0, maximum: 200))
    }

    // MARK: - Thresholds and separators

    @Test("Eşik değer olarak basılmış sonuç")
    func readsThreshold() throws {
        let value = try parsed("hs-CRP                      <0,3      mg/L")
        #expect(value.marker.storageKey == "highSensitivityCRP")
        #expect(value.value == 0.3)
        #expect(value.isThreshold)
    }

    @Test("Ondalık virgül ve nokta birlikte")
    func decimalSeparators() {
        #expect(LabReportParser.decimalValue(of: "45,2", sawDot: false, sawComma: true) == 45.2)
        #expect(LabReportParser.decimalValue(of: "1.234,5", sawDot: true, sawComma: true) == 1234.5)
        #expect(LabReportParser.decimalValue(of: "1,234.5", sawDot: true, sawComma: true) == 1234.5)
        #expect(LabReportParser.decimalValue(of: "5.4", sawDot: true, sawComma: false) == 5.4)
    }

    /// The case that made `resolveGrouping` necessary: 1.234 U/L is three hundred times
    /// below the bottom of the CK band and 1234 U/L is an ordinary post-session reading.
    @Test("Belirsiz binlik ayırıcı referans bandıyla çözülür")
    func resolvesAmbiguousGrouping() throws {
        let value = try parsed("CK (Kreatin Kinaz)          1.234     U/L        39 - 308")
        #expect(value.marker.storageKey == "creatineKinase")
        #expect(value.value == 1234)
        // Belirsizlik bedava değil: satır düşük güvenle işaretlenir ve varsayılan olarak
        // seçili gelmez.
        #expect(value.confidence == .low)
        #expect(!value.confidence.isPreselected)
    }

    @Test("Belirsiz olmayan bir değerde binlik yorumu denenmez")
    func keepsUnambiguousValue() throws {
        let value = try parsed("Açlık Glukozu               92        mg/dL      70 - 99")
        #expect(value.value == 92)
        #expect(value.confidence == .high)
    }

    // MARK: - Non-lab lines

    @Test("Tahlil olmayan satırlar geçilir")
    func skipsNonLabLines() {
        let lines = [
            "Bu rapor hekim değerlendirmesi gerektirir.",
            "Sayfa 2 / 4",
            ""
        ]
        for line in lines {
            if case .parsed = LabReportParser.parseLine(line) {
                Issue.record("Tahlil satırı sanıldı: \(line)")
            }
        }
    }

    // MARK: - Dates

    @Test("Etiketli tarih tercih edilir")
    func prefersLabelledDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let found = LabReportParser.detectDrawDate(
            in: ["Rapor No: 118820", "Numune Tarihi: 14.03.2026", "Basım: 20.03.2026"],
            referenceDate: reference
        )
        let components = calendar.dateComponents([.year, .month, .day], from: try #require(found))
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 14)
    }

    @Test("Gelecekteki tarih alınmaz")
    func rejectsFutureDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(LabReportParser.detectDrawDate(in: ["Tarih: 14.03.2026"], referenceDate: reference) == nil)
    }

    // MARK: - Whole documents

    @Test("Aynı belirteç iki kez geçerse güvenli olan kazanır")
    func deduplicatesByConfidence() {
        let document = LabDocumentText(
            pages: [
                LabDocumentPage(
                    pageNumber: 1,
                    lines: [
                        "Ferritin  45,2  ng/mL  (30 - 400)",
                        "Ferritin  45,2"
                    ],
                    source: .textLayer
                )
            ],
            fileName: "tahlil.pdf"
        )
        let draft = LabReportParser.parse(document)
        #expect(draft.values.filter { $0.marker.storageKey == "ferritin" }.count == 1)
        // Birimi olan satır daha güvenli, o kalmalı.
        #expect(draft.values.first?.unitSymbol == "ng/mL")
    }
}
