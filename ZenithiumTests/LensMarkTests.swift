//
//  LensMarkTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, B9 — the app's own marks for the four lenses.
//
//  Geometry in code is testable in a way an SVG symbol is not, which is most of why it was
//  chosen. These are the properties that would make a mark render wrong: falling outside its
//  box, collapsing to nothing, or being identical to another mark.
//

import Testing
import Foundation
import SwiftUI
@testable import Zenithium

@Suite("Lens marks")
struct LensMarkTests {

    private let box = CGRect(x: 0, y: 0, width: 24, height: 24)

    @Test("Her mercek bir işaret çiziyor", arguments: TrainingLens.allCases)
    func everyLensDrawsSomething(lens: TrainingLens) {
        let paths = LensMarkGeometry.paths(for: lens, in: box)
        #expect(!paths.isEmpty)
        for path in paths {
            #expect(!path.isEmpty, "\(lens) boş bir yol üretti")
        }
    }

    @Test("İşaretler kutunun içinde kalıyor", arguments: TrainingLens.allCases)
    func marksStayInsideTheBox(lens: TrainingLens) {
        for path in LensMarkGeometry.paths(for: lens, in: box) {
            let bounds = path.boundingRect
            #expect(bounds.minX >= box.minX - 0.5, "\(lens) solda taşıyor")
            #expect(bounds.maxX <= box.maxX + 0.5, "\(lens) sağda taşıyor")
            #expect(bounds.minY >= box.minY - 0.5, "\(lens) üstte taşıyor")
            #expect(bounds.maxY <= box.maxY + 0.5, "\(lens) altta taşıyor")
        }
    }

    @Test("İşaretler kutunun anlamlı bir kısmını dolduruyor", arguments: TrainingLens.allCases)
    func marksFillTheBox(lens: TrainingLens) {
        // A mark occupying a tenth of its box reads as a dot beside symbols that fill theirs.
        let union = LensMarkGeometry.paths(for: lens, in: box)
            .map(\.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
        #expect(union.width >= box.width * 0.5, "\(lens) çok dar: \(union.width)")
        #expect(union.height >= box.height * 0.3, "\(lens) çok kısa: \(union.height)")
    }

    @Test("Dört işaret birbirinden farklı")
    func themarksDiffer() {
        let descriptions = TrainingLens.allCases.map { lens in
            LensMarkGeometry.paths(for: lens, in: box)
                .map(\.description)
                .joined(separator: "|")
        }
        #expect(Set(descriptions).count == TrainingLens.allCases.count)
    }

    @Test("Ölçek değişince işaret ölçekleniyor", arguments: TrainingLens.allCases)
    func marksScaleWithTheBox(lens: TrainingLens) {
        let small = LensMarkGeometry.paths(for: lens, in: box)
            .map(\.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
        let large = LensMarkGeometry.paths(for: lens, in: CGRect(x: 0, y: 0, width: 96, height: 96))
            .map(\.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
        #expect(large.width > small.width * 3.5, "\(lens) ölçeklenmiyor")
    }

    @Test("Sıfır boyutlu kutu çökmüyor", arguments: TrainingLens.allCases)
    func azeroSizedBoxDoesNotCrash(lens: TrainingLens) {
        let paths = LensMarkGeometry.paths(for: lens, in: .zero)
        for path in paths {
            #expect(path.boundingRect.width.isFinite)
            #expect(path.boundingRect.height.isFinite)
        }
    }
}
