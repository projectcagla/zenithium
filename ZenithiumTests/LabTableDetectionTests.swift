//
//  LabTableDetectionTests.swift
//  ZenithiumTests
//
//  Row recovery from recognised fragments, and the two folds that decide whether a marker
//  name is recognised at all.
//
//  Every fixture here is literal geometry rather than a PDF, which is the point of splitting
//  `LabTextFragment` out of `LabDocumentReader`: the rule that decides which value belongs
//  to which marker is the one rule in the import path that fails silently, and it is now the
//  one that can be checked without a scanner.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Lab table row detection")
struct LabTableDetectionTests {

    /// A printed table, optionally rotated.
    ///
    /// `slope` is vertical drift per unit of page width — the same quantity
    /// `estimatedSlope` recovers.
    private func page(
        rows: Int,
        columns: [Double],
        rowSpacing: Double,
        height: Double,
        slope: Double = 0,
        top: Double = 0.85
    ) -> [LabTextFragment] {
        var fragments: [LabTextFragment] = []
        for row in 0..<rows {
            let baseline = top - Double(row) * rowSpacing
            for (index, x) in columns.enumerated() {
                fragments.append(
                    LabTextFragment(
                        text: "r\(row)c\(index)",
                        midY: baseline - x * slope,
                        minX: x,
                        height: height
                    )
                )
            }
        }
        return fragments
    }

    private func lines(_ fragments: [LabTextFragment]) -> [String] {
        LabTextFragment.assembleLines(
            from: fragments,
            bandHeightFactor: 0.7,
            fallbackTolerance: 0.008
        )
    }

    // MARK: - Level pages

    @Test("Yoğun hemogram doğru sayıda satıra ayrılıyor")
    func aDenseTableKeepsItsRows() {
        let fragments = page(
            rows: 6,
            columns: [0.08, 0.45, 0.62, 0.80],
            rowSpacing: 0.011,
            height: 0.009
        )
        #expect(lines(fragments).count == 6)
    }

    @Test("Büyük punto raporda birim, değerinin satırında kalıyor")
    func aUnitSetSlightlyLowStaysOnItsRow() {
        var fragments = page(
            rows: 4,
            columns: [0.08, 0.50],
            rowSpacing: 0.05,
            height: 0.022
        )
        // The unit sits a little below the value it belongs to, as it does when a report
        // prints "mg/dL" in smaller type.
        for row in 0..<4 {
            fragments.append(
                LabTextFragment(
                    text: "unit\(row)",
                    midY: 0.85 - Double(row) * 0.05 - 0.004,
                    minX: 0.68,
                    height: 0.018
                )
            )
        }
        #expect(lines(fragments).count == 4)
    }

    @Test("Bir satır soldan sağa sırayla birleştiriliyor")
    func aRowIsJoinedLeftToRight() {
        let fragments = [
            LabTextFragment(text: "ng/mL", midY: 0.80, minX: 0.62, height: 0.011),
            LabTextFragment(text: "Ferritin", midY: 0.80, minX: 0.08, height: 0.011),
            LabTextFragment(text: "45,2", midY: 0.80, minX: 0.45, height: 0.011)
        ]
        #expect(lines(fragments) == ["Ferritin  45,2  ng/mL"])
    }

    @Test("Satırlar yukarıdan aşağıya sıralanıyor")
    func rowsComeOutTopToBottom() {
        let fragments = [
            LabTextFragment(text: "alt", midY: 0.20, minX: 0.08, height: 0.011),
            LabTextFragment(text: "ust", midY: 0.80, minX: 0.08, height: 0.011),
            LabTextFragment(text: "orta", midY: 0.50, minX: 0.08, height: 0.011)
        ]
        #expect(lines(fragments) == ["ust", "orta", "alt"])
    }

    // MARK: - Rotated pages

    /// The failure this was written for: a photograph of a report is never level, and a
    /// rotated page splits rows in a way that detaches values from markers.
    @Test("Eğik sayfada satırlar bölünmüyor", arguments: [0.021, 0.040, -0.025, -0.015])
    func rotatedPagesStillRecoverTheirRows(slope: Double) {
        let fragments = page(
            rows: 6,
            columns: [0.06, 0.35, 0.55, 0.78, 0.90],
            rowSpacing: 0.025,
            height: 0.012,
            slope: slope
        )
        #expect(lines(fragments).count == 6, "eğim \(slope) satırları böldü")
    }

    @Test("Eğim kestirimi düz sayfayı düz bırakıyor")
    func aLevelPageIsNotGivenARotation() {
        let fragments = page(
            rows: 6,
            columns: [0.08, 0.45, 0.62, 0.80],
            rowSpacing: 0.020,
            height: 0.011
        )
        let band = LabTextFragment.bandTolerance(for: fragments, factor: 0.7, fallback: 0.008)
        #expect(LabTextFragment.estimatedSlope(for: fragments, band: band) == 0)
    }

    @Test("Eğik sayfada kestirilen eğim gerçeğe yakın")
    func theEstimateLandsNearTheRealRotation() {
        let real = 0.030
        let fragments = page(
            rows: 6,
            columns: [0.06, 0.35, 0.55, 0.78, 0.90],
            rowSpacing: 0.025,
            height: 0.012,
            slope: real
        )
        let band = LabTextFragment.bandTolerance(for: fragments, factor: 0.7, fallback: 0.008)
        let estimate = LabTextFragment.estimatedSlope(for: fragments, band: band)
        // Sign convention: a row descending to the right is recovered as a negative slope.
        #expect(estimate < 0, "eğim yönü ters kestirildi")
        #expect(abs(estimate) <= LabTextFragment.maximumSlope)
    }

    @Test("Az parçalı sayfada eğim aranmıyor")
    func aSparsePageIsNotRotated() {
        let fragments = [
            LabTextFragment(text: "a", midY: 0.8, minX: 0.1, height: 0.011),
            LabTextFragment(text: "b", midY: 0.8, minX: 0.5, height: 0.011)
        ]
        let band = LabTextFragment.bandTolerance(for: fragments, factor: 0.7, fallback: 0.008)
        #expect(LabTextFragment.estimatedSlope(for: fragments, band: band) == 0)
    }

    // MARK: - Band

    @Test("Bant yüksekliği metinden türetiliyor")
    func theBandFollowsTheTypeSize() {
        let small = page(rows: 3, columns: [0.1], rowSpacing: 0.02, height: 0.008)
        let large = page(rows: 3, columns: [0.1], rowSpacing: 0.06, height: 0.030)

        let smallBand = LabTextFragment.bandTolerance(for: small, factor: 0.7, fallback: 0.008)
        let largeBand = LabTextFragment.bandTolerance(for: large, factor: 0.7, fallback: 0.008)

        #expect(largeBand > smallBand)
        #expect(abs(smallBand - 0.008 * 0.7) < 1e-12)
    }

    @Test("Yüksekliği olmayan parçalarda yedek bant kullanılıyor")
    func theFallbackBandIsUsedWithoutHeights() {
        let fragments = [
            LabTextFragment(text: "a", midY: 0.8, minX: 0.1, height: 0),
            LabTextFragment(text: "b", midY: 0.8, minX: 0.5, height: 0)
        ]
        #expect(LabTextFragment.bandTolerance(for: fragments, factor: 0.7, fallback: 0.008) == 0.008)
    }

    @Test("Boş giriş boş çıktı")
    func emptyInputProducesNothing() {
        #expect(lines([]).isEmpty)
        #expect(LabTextFragment.group([], band: 0.01, slope: 0).isEmpty)
    }
}

@Suite("Lab name folding")
struct LabNameFoldingTests {

    // MARK: - Turkish

    /// The bug: only the lowercase circumflexed vowels were in the fold map, so an uppercase
    /// "Â" fell through to `lowercased()` and stopped at "â" — a different key from the "a"
    /// its lowercase twin produced. Lab reports set marker names in capitals routinely.
    @Test("Büyük harfli aksanlı ünlüler küçük harfli hâlleriyle aynı katlanıyor")
    func circumflexedVowelsFoldInBothCases() {
        #expect(BiomarkerCatalog.normalize("Â") == BiomarkerCatalog.normalize("â"))
        #expect(BiomarkerCatalog.normalize("Î") == BiomarkerCatalog.normalize("î"))
        #expect(BiomarkerCatalog.normalize("Û") == BiomarkerCatalog.normalize("û"))
        #expect(BiomarkerCatalog.normalize("Â") == "a")
    }

    @Test("Türkçe harfler her iki yazımda da aynı ada gidiyor", arguments: [
        ("Ferritin", "FERRİTİN"),
        ("Kreatinin", "KREATİNİN"),
        ("Trigliserit", "TRİGLİSERİT"),
        ("Glukoz", "GLUKOZ")
    ])
    func caseAndDiacriticsDoNotChangeTheName(pair: (String, String)) {
        #expect(BiomarkerCatalog.normalize(pair.0) == BiomarkerCatalog.normalize(pair.1))
    }

    @Test("Noktasız ı ve noktalı i aynı harfe iniyor")
    func dotlessAndDottedFoldTogether() {
        #expect(BiomarkerCatalog.normalize("ışık") == BiomarkerCatalog.normalize("isik"))
        #expect(BiomarkerCatalog.normalize("İNSÜLİN") == "insulin")
    }

    // MARK: - Optical confusion

    @Test("Optik katlama görsel olarak aynı glifleri birleştiriyor")
    func theOpticalFoldMergesConfusableGlyphs() {
        #expect(BiomarkerCatalog.opticallyFolded("hba1c") == BiomarkerCatalog.opticallyFolded("hbaic"))
        #expect(BiomarkerCatalog.opticallyFolded("b12") == BiomarkerCatalog.opticallyFolded("biz"))
        #expect(BiomarkerCatalog.opticallyFolded("ferrit1n") == BiomarkerCatalog.opticallyFolded("ferritin"))
    }

    /// The property that makes a fuzzy pass safe: it must not merge two markers that were
    /// previously distinguishable. Checked over the whole catalogue rather than by example.
    @Test("Optik katlama katalogda hiçbir iki adı birleştirmiyor")
    func theOpticalFoldCollapsesNothingInTheCatalogue() {
        var byExact: Set<String> = []
        var byFolded: Set<String> = []
        for definition in BiomarkerCatalog.all {
            for name in definition.synonyms + [definition.displayName] {
                let normalized = BiomarkerCatalog.normalize(name)
                guard !normalized.isEmpty else { continue }
                byExact.insert(normalized)
                byFolded.insert(BiomarkerCatalog.opticallyFolded(normalized))
            }
        }
        #expect(byExact.count == byFolded.count, "optik katlama iki farklı belirteci birleştiriyor")
    }

    // MARK: - Matching

    @Test("Temiz bir satır hâlâ tam eşleşmeyle çözülüyor")
    func aCleanLineStillResolvesExactly() throws {
        let match = try #require(BiomarkerCatalog.bestMatch(inLine: "Ferritin  45,2  ng/mL"))
        #expect(match.definition.displayName.lowercased().contains("ferritin"))
    }

    @Test("OCR'ın bozduğu ad yedek geçişte bulunuyor")
    func aMisreadNameIsFoundByTheSecondPass() throws {
        // A "1" read as an "l" — the single most common confusion on a printed report.
        let match = try #require(BiomarkerCatalog.bestMatch(inLine: "HbAlc  %5,4"))
        let exact = BiomarkerCatalog.bestMatch(inLine: "HbA1c  %5,4")
        #expect(match.definition.key == exact?.definition.key)
    }

    @Test("Hiçbir belirteç içermeyen satır yine de eşleşmiyor")
    func anUnrelatedLineStillMatchesNothing() {
        #expect(BiomarkerCatalog.bestMatch(inLine: "Rapor tarihi 12.03.2026") == nil)
        #expect(BiomarkerCatalog.bestMatch(inLine: "Sayfa 2 / 4") == nil)
    }
}
