//
//  SnapshotRegressionTests.swift
//  ZenithiumTests
//
//  Faz 9: Görsel Gerileme Test Kilidi (Visual Regression Test Lock).
//  21 kanonik ekran görüntüsü referansıyla ≤%0.5 piksel toleranslı karşılaştırma.
//

import Testing
import SwiftUI
import UIKit
import CoreGraphics
@testable import Zenithium

@Suite("Görsel Gerileme Test Kilidi (Faz 9)", .serialized)
@MainActor
struct SnapshotRegressionTests {

    private let size17Pro = CGSize(width: 402, height: 874)

    private var snapshotsDirectory: URL {
        let testFilePath = URL(fileURLWithPath: #filePath)
        let root = testFilePath.deletingLastPathComponent()
        return root.appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    private var diffDirectory: URL {
        let testFilePath = URL(fileURLWithPath: #filePath)
        let root = testFilePath.deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent(".build/renders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func renderViewToImage(_ view: AnyView) -> UIImage? {
        let styledView = view
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .dark)
            .frame(width: size17Pro.width, height: size17Pro.height)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size17Pro))
        }
        window.frame = CGRect(origin: .zero, size: size17Pro)
        window.overrideUserInterfaceStyle = .dark

        let hosting = UIHostingController(rootView: styledView)
        hosting.overrideUserInterfaceStyle = .dark
        hosting.view.frame = CGRect(origin: .zero, size: size17Pro)
        hosting.view.backgroundColor = UIColor(ZenithiumColor.background)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.loadViewIfNeeded()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        let uiRenderer = UIGraphicsImageRenderer(size: size17Pro, format: format)
        let image = uiRenderer.image { ctx in
            let success = hosting.view.drawHierarchy(in: CGRect(origin: .zero, size: size17Pro), afterScreenUpdates: true)
            if !success {
                hosting.view.layer.render(in: ctx.cgContext)
            }
        }
        window.isHidden = true
        guard let pngData = image.pngData(),
              let normalizedImage = UIImage(data: pngData) else {
            return image
        }
        return normalizedImage
    }

    private func compareImages(
        rendered: UIImage,
        reference: UIImage,
        tolerance: Double = 0.005
    ) -> (passes: Bool, diffPercentage: Double, diffImage: UIImage?) {
        guard let cgRendered = rendered.cgImage,
              let cgReference = reference.cgImage else {
            return (false, 1.0, nil)
        }

        let width = cgRendered.width
        let height = cgRendered.height

        guard width == cgReference.width, height == cgReference.height else {
            return (false, 1.0, nil)
        }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var renderedData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        var referenceData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context1 = CGContext(
            data: &renderedData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let context2 = CGContext(
            data: &referenceData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return (false, 1.0, nil)
        }

        context1.draw(cgRendered, in: CGRect(x: 0, y: 0, width: width, height: height))
        context2.draw(cgReference, in: CGRect(x: 0, y: 0, width: width, height: height))

        var diffPixels = 0
        let totalPixels = width * height
        var diffData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for i in 0..<totalPixels {
            let offset = i * bytesPerPixel
            let r1 = Int(renderedData[offset])
            let g1 = Int(renderedData[offset + 1])
            let b1 = Int(renderedData[offset + 2])
            let a1 = Int(renderedData[offset + 3])

            let r2 = Int(referenceData[offset])
            let g2 = Int(referenceData[offset + 1])
            let b2 = Int(referenceData[offset + 2])
            let a2 = Int(referenceData[offset + 3])

            let delta = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) + abs(a1 - a2)
            if delta > 15 {
                diffPixels += 1
                diffData[offset] = 255     // R
                diffData[offset + 1] = 0   // G
                diffData[offset + 2] = 0   // B
                diffData[offset + 3] = 255 // A
            } else {
                diffData[offset] = UInt8(r2 / 4)
                diffData[offset + 1] = UInt8(g2 / 4)
                diffData[offset + 2] = UInt8(b2 / 4)
                diffData[offset + 3] = UInt8(a2)
            }
        }

        let diffPercentage = Double(diffPixels) / Double(totalPixels)
        let passes = diffPercentage <= tolerance

        var diffImage: UIImage? = nil
        if !passes, let diffContext = CGContext(
            data: &diffData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let diffCG = diffContext.makeImage() {
            diffImage = UIImage(cgImage: diffCG)
        }

        return (passes, diffPercentage, diffImage)
    }

    private func verifySnapshot(
        name: String,
        view: AnyView,
        tolerance: Double = 0.005
    ) {
        let referenceURL = snapshotsDirectory.appendingPathComponent("\(name).png")
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            Issue.record("Kanonik referans snapshot bulunamadı: \(referenceURL.path)")
            return
        }

        guard let referenceData = try? Data(contentsOf: referenceURL),
              let referenceImage = UIImage(data: referenceData) else {
            Issue.record("Kanonik referans dosyası okunamadı: \(referenceURL.path)")
            return
        }

        guard let renderedImage = renderViewToImage(view) else {
            Issue.record("Görünüm render edilemedi: \(name)")
            return
        }

        let result = compareImages(
            rendered: renderedImage,
            reference: referenceImage,
            tolerance: tolerance
        )

        if !result.passes {
            if let diffImage = result.diffImage,
               let pngData = diffImage.pngData() {
                let diffURL = diffDirectory.appendingPathComponent("\(name)-diff.png")
                try? pngData.write(to: diffURL)
            }
            #expect(result.passes, "Görsel gerileme farkı eşiği aştı: \(name)")
        } else {
            #expect(result.passes)
        }
    }

    // MARK: - 21 Kanonik Ekran Testi

    @Test("Bugün ekranı · dolu")
    func testBugunDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTodayViewModel(state: .dolu)
        let view = AnyView(TodayView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "bugun-dolu", view: view)
    }

    @Test("Bugün ekranı · kalibrasyon")
    func testBugunKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTodayViewModel(state: .kalibrasyon)
        let view = AnyView(TodayView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "bugun-kalibrasyon", view: view)
    }

    @Test("Bugün ekranı · veri yok")
    func testBugunVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTodayViewModel(state: .veriyok)
        let view = AnyView(TodayView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "bugun-veriyok", view: view)
    }

    @Test("Uyku ekranı · dolu")
    func testUykuDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeSleepViewModel(state: .dolu)
        let view = AnyView(SleepView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "uyku-dolu", view: view)
    }

    @Test("Uyku ekranı · kalibrasyon")
    func testUykuKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeSleepViewModel(state: .kalibrasyon)
        let view = AnyView(SleepView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "uyku-kalibrasyon", view: view)
    }

    @Test("Uyku ekranı · veri yok")
    func testUykuVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeSleepViewModel(state: .veriyok)
        let view = AnyView(SleepView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "uyku-veriyok", view: view)
    }

    @Test("Yük ekranı · dolu")
    func testYukDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrainingLoadViewModel(state: .dolu)
        let view = AnyView(TrainingLoadView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "yuk-dolu", view: view)
    }

    @Test("Yük ekranı · kalibrasyon")
    func testYukKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrainingLoadViewModel(state: .kalibrasyon)
        let view = AnyView(TrainingLoadView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "yuk-kalibrasyon", view: view)
    }

    @Test("Yük ekranı · veri yok")
    func testYukVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrainingLoadViewModel(state: .veriyok)
        let view = AnyView(TrainingLoadView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "yuk-veriyok", view: view)
    }

    @Test("Trendler ekranı · dolu")
    func testTrendlerDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrendsViewModel(state: .dolu)
        let view = AnyView(TrendsView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "trendler-dolu", view: view)
    }

    @Test("Trendler ekranı · kalibrasyon")
    func testTrendlerKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrendsViewModel(state: .kalibrasyon)
        let view = AnyView(TrendsView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "trendler-kalibrasyon", view: view)
    }

    @Test("Trendler ekranı · veri yok")
    func testTrendlerVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeTrendsViewModel(state: .veriyok)
        let view = AnyView(TrendsView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "trendler-veriyok", view: view)
    }

    @Test("Kas haritası ekranı · dolu")
    func testKasDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeMuscleMapViewModel(state: .dolu)
        let view = AnyView(MuscleMapView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "kas-dolu", view: view)
    }

    @Test("Kas haritası ekranı · kalibrasyon")
    func testKasKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeMuscleMapViewModel(state: .kalibrasyon)
        let view = AnyView(MuscleMapView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "kas-kalibrasyon", view: view)
    }

    @Test("Kas haritası ekranı · veri yok")
    func testKasVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeMuscleMapViewModel(state: .veriyok)
        let view = AnyView(MuscleMapView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "kas-veriyok", view: view)
    }

    @Test("Tahlil ekranı · dolu")
    func testTahlilDoluSnapshot() async {
        let vm = await PreviewFixtures.shared.makeBloodworkViewModel(state: .dolu)
        let view = AnyView(BloodworkView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "tahlil-dolu", view: view)
    }

    @Test("Tahlil ekranı · kalibrasyon")
    func testTahlilKalibrasyonSnapshot() async {
        let vm = await PreviewFixtures.shared.makeBloodworkViewModel(state: .kalibrasyon)
        let view = AnyView(BloodworkView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "tahlil-kalibrasyon", view: view)
    }

    @Test("Tahlil ekranı · veri yok")
    func testTahlilVeriyokSnapshot() async {
        let vm = await PreviewFixtures.shared.makeBloodworkViewModel(state: .veriyok)
        let view = AnyView(BloodworkView(viewModel: vm, embedInNavigation: false))
        verifySnapshot(name: "tahlil-veriyok", view: view)
    }

    @Test("Neden ekranı · dolu")
    func testNedenDoluSnapshot() async {
        let view = AnyView(ReasonView(state: .loaded(PreviewFixtures.sampleRecommendation), embedInNavigation: false))
        verifySnapshot(name: "neden-dolu", view: view)
    }

    @Test("Neden ekranı · kalibrasyon")
    func testNedenKalibrasyonSnapshot() async {
        let view = AnyView(ReasonView(state: .calibrating(progress: 0.35, daysCollected: 5, daysRequired: 14), embedInNavigation: false))
        verifySnapshot(name: "neden-kalibrasyon", view: view)
    }

    @Test("Neden ekranı · veri yok")
    func testNedenVeriyokSnapshot() async {
        let view = AnyView(ReasonView(state: .noData(reason: .notEnoughHistory(daysAvailable: 0, daysRequired: 14)), embedInNavigation: false))
        verifySnapshot(name: "neden-veriyok", view: view)
    }
}
