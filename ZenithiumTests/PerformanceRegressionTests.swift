//
//  PerformanceRegressionTests.swift
//  ZenithiumTests
//
//  Guards for the work the v4 optimisations removed. Yol haritası v4, A9.
//
//  None of these measure time. A wall-clock assertion on a shared CI machine fails for
//  reasons that have nothing to do with the code, so it gets loosened until it cannot fail,
//  and then it guards nothing. Every assertion here is a count instead: how many splines a
//  redraw builds, how many synonyms a line examines, how many reads a refresh issues. Those
//  are exactly what the optimisations changed, they are deterministic, and a regression
//  moves them in an obvious direction.
//

import Testing
import Foundation
import SwiftUI
@testable import Zenithium

@Suite("Body map path building")
@MainActor
struct BodyPathCacheTests {

    private let rect = CGRect(x: 0, y: 0, width: 340, height: 1000)

    @Test("Aynı boyut için ikinci çizim hiç spline kurmaz")
    func rebuildsNothingWhenSizeIsUnchanged() {
        let cache = BodyPathCache()
        let regions = BodyGeometry.regions(for: .anterior)

        _ = cache.paths(for: regions, in: rect)
        let afterFirst = cache.splineBuildCount
        #expect(afterFirst > 0)

        // Three redraws at the same size: the canvas fill, the hit-test overlay and its
        // content shape all resolve through the cache, and none of them may rebuild.
        for _ in 0..<3 {
            _ = cache.paths(for: regions, in: rect)
        }
        #expect(cache.splineBuildCount == afterFirst)
    }

    @Test("Bir düzen geçişi bölge başına yalnız kendi karınlarını kurar")
    func buildsEachBellyExactlyOnce() {
        let cache = BodyPathCache()
        let regions = BodyGeometry.regions(for: .anterior)
        _ = cache.paths(for: regions, in: rect)

        let bellies = regions.reduce(0) { $0 + $1.outlines.count }
        let expected = bellies + BodyGeometry.silhouetteOutlines.count
        #expect(cache.splineBuildCount == expected)
    }

    @Test("Boyut değişince yeniden kurulur")
    func rebuildsWhenSizeChanges() {
        let cache = BodyPathCache()
        let regions = BodyGeometry.regions(for: .anterior)

        _ = cache.paths(for: regions, in: rect)
        let afterFirst = cache.splineBuildCount
        _ = cache.paths(for: regions, in: rect.insetBy(dx: -20, dy: 0))
        #expect(cache.splineBuildCount > afterFirst)
    }

    @Test("Ön ve arka görünüm arasında geçiş yeniden kurar")
    func rebuildsWhenSideChanges() {
        let cache = BodyPathCache()
        _ = cache.paths(for: BodyGeometry.regions(for: .anterior), in: rect)
        let afterFirst = cache.splineBuildCount
        _ = cache.paths(for: BodyGeometry.regions(for: .posterior), in: rect)
        #expect(cache.splineBuildCount > afterFirst)
    }

    @Test("Dış çizgiler bölge kurulurken bir kez üretilir")
    func outlinesArePrecomputed() {
        for region in BodyGeometry.allRegions {
            #expect(region.outlines.count == region.spines.count)
            for outline in region.outlines {
                #expect(outline.count >= 3, "\(region.id) çizilemeyecek kadar az noktaya sahip")
            }
        }
    }

    @Test("Çizilen yol boş değil ve figürün içinde kalıyor")
    func pathsStayInsideTheFigure() {
        let cache = BodyPathCache()
        let paths = cache.paths(for: BodyGeometry.regions(for: .anterior), in: rect)
        for region in BodyGeometry.regions(for: .anterior) {
            let bounds = paths.path(for: region).boundingRect
            #expect(!bounds.isEmpty, "\(region.id) boş")
            #expect(bounds.minX >= rect.minX - 1 && bounds.maxX <= rect.maxX + 1, "\(region.id) yatayda taşıyor")
            #expect(bounds.minY >= rect.minY - 1 && bounds.maxY <= rect.maxY + 1, "\(region.id) dikeyde taşıyor")
        }
    }
}

@Suite("Biomarker matching does not scale with the catalogue")
struct BiomarkerMatchingCostTests {

    @Test(
        "Bir satır katalogun küçük bir kısmına bakar",
        arguments: [
            "LDL Kolesterol            132   mg/dL   (0 - 130)",
            "hs-CRP (C reaktif protein)  0,8  mg/L",
            "B12 Vitamini              350   pg/mL",
            "TSH 2,10 uIU/mL"
        ]
    )
    func examinesFewCandidates(line: String) {
        let examined = BiomarkerCatalog.candidatesExamined(inLine: line)
        let total = BiomarkerCatalog.totalSynonymCount

        // The old matcher walked every synonym in the catalogue for every line. The index
        // means a line only considers synonyms that could start at one of its own tokens.
        #expect(examined > 0, "hiçbir aday bulunamadı — indeks bozulmuş olabilir")
        #expect(
            examined < total / 4,
            "\(line): \(examined)/\(total) aday — indeks artık ayırt etmiyor"
        )
    }

    @Test("Belirteç içermeyen satır hiçbir adaya bakmaz")
    func plainProseExaminesNothing() {
        let examined = BiomarkerCatalog.candidatesExamined(
            inLine: "Bu rapor yalnızca bilgilendirme amaçlıdır ve tanı yerine geçmez."
        )
        #expect(examined == 0)
    }

    @Test("Katalog büyüdükçe indeks dağılımı bozulmuyor")
    func indexIsWellDistributed() {
        // A synonym set where most needles hang off one token would rebuild the old linear
        // scan under a new name. The check is coarse on purpose: it should fail when the
        // index stops being an index, not when a marker gains a synonym.
        let worst = BiomarkerCatalog.all
            .flatMap { $0.synonyms + [$0.displayName] }
            .compactMap { BiomarkerCatalog.normalize($0).split(separator: " ").first.map(String.init) }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .values
            .max() ?? 0
        #expect(worst < BiomarkerCatalog.totalSynonymCount / 5)
    }
}

@Suite("The spacing scale is the only source of spacing")
struct DesignTokenTests {

    @Test("Ölçek artan ve tekrarsız")
    func scaleIsStrictlyIncreasing() {
        let scale: [CGFloat] = [
            ZenithiumSpacing.none,
            ZenithiumSpacing.xxs,
            ZenithiumSpacing.xs,
            ZenithiumSpacing.s,
            ZenithiumSpacing.m,
            ZenithiumSpacing.l,
            ZenithiumSpacing.xl,
            ZenithiumSpacing.xxl
        ]
        for index in 1..<scale.count {
            #expect(scale[index] > scale[index - 1])
        }
    }

    @Test("Her adım 2pt ızgarasına oturuyor")
    func scaleSitsOnTheGrid() {
        let scale: [CGFloat] = [
            ZenithiumSpacing.xxs, ZenithiumSpacing.xs, ZenithiumSpacing.s,
            ZenithiumSpacing.m, ZenithiumSpacing.l, ZenithiumSpacing.xl, ZenithiumSpacing.xxl
        ]
        for step in scale {
            #expect(step.truncatingRemainder(dividingBy: 2) == 0, "\(step) ızgara dışı")
        }
    }

    @Test("Yarıçaplar da artan")
    func radiiAreIncreasing() {
        #expect(ZenithiumRadius.small < ZenithiumRadius.medium)
        #expect(ZenithiumRadius.medium < ZenithiumRadius.large)
        #expect(ZenithiumRadius.large < ZenithiumRadius.xLarge)
    }
}
