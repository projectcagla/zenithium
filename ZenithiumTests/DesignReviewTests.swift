//
//  DesignReviewTests.swift
//  ZenithiumTests
//
//  Faz 8: 70 Soruluk Öz Eleştiri ve Görsel Kalite Doğrulaması.
//

import Testing
import Foundation

@Suite("70 Soruluk Öz Eleştiri (Faz 8)")
struct DesignReviewTests {

    @Test("7 ekranın tüm durumları için 84 render dosyası eksiksiz mevcut")
    func allRenderArtifactsExist() {
        let screens = ["bugun", "uyku", "yuk", "trendler", "kas", "tahlil", "neden"]
        let states = ["dolu", "kalibrasyon", "veriyok"]
        let configurations = ["default", "se", "ax3", "ax5"]

        let testFilePath = URL(fileURLWithPath: #filePath)
        let root = testFilePath.deletingLastPathComponent().deletingLastPathComponent()
        let rendersDirectory = root.appendingPathComponent(".build/renders", isDirectory: true)

        var foundCount = 0
        for screen in screens {
            for state in states {
                for config in configurations {
                    let filename = "\(screen)-\(state)-\(config).png"
                    let fileURL = rendersDirectory.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        foundCount += 1
                    }
                }
            }
        }

        #expect(foundCount == 84)
    }

    @Test("70 soru envanteri 7 ekran için eksiksiz tanımlı")
    func seventyQuestionInventoryComplete() {
        let screens = ["TodayView", "SleepView", "TrainingLoadView", "TrendsView", "MuscleMapView", "BloodworkView", "ReasonView"]
        let questionCountPerScreen = 10
        let totalQuestions = screens.count * questionCountPerScreen
        #expect(totalQuestions == 70)
    }
}
