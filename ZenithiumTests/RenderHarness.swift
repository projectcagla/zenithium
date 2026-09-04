//
//  RenderHarness.swift
//  ZenithiumTests
//
//  Faz 0 Görsel Test Donanımı (Render Harness).
//  ImageRenderer ile her ekranı ve durumunu PNG formatında render eder.
//

import XCTest
import SwiftUI
import UIKit
@testable import Zenithium

@MainActor
final class RenderHarness: XCTestCase {

    private let size17Pro = CGSize(width: 402, height: 874)
    private let sizeSE = CGSize(width: 375, height: 667)

    private var outputDirectory: URL {
        let testFilePath = URL(fileURLWithPath: #filePath)
        let root = testFilePath.deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent(".build/renders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var artifactDirectory: URL {
        let dir = URL(fileURLWithPath: "/Users/cagla/.gemini/antigravity/brain/39b76099-fbcb-4ada-9184-40e0b8d509b6/renders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func renderView(
        _ view: AnyView,
        size: CGSize,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 3.0
    ) -> Data? {
        let styledView = view
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)

        // Window-backed high fidelity snapshot
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark

        let hosting = UIHostingController(rootView: styledView)
        hosting.overrideUserInterfaceStyle = .dark
        hosting.view.frame = CGRect(origin: .zero, size: size)
        hosting.view.backgroundColor = UIColor(ZenithiumColor.background)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.loadViewIfNeeded()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        // Give the runloop time to layout
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let uiRenderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = uiRenderer.image { ctx in
            let success = hosting.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            if !success {
                hosting.view.layer.render(in: ctx.cgContext)
            }
        }
        window.isHidden = true
        return image.pngData()
    }

    private func savePNG(data: Data, filename: String) {
        let targetURL = outputDirectory.appendingPathComponent(filename)
        try? data.write(to: targetURL)

        let artifactURL = artifactDirectory.appendingPathComponent(filename)
        try? data.write(to: artifactURL)
    }

    func testRenderAllScreensAndStates() async throws {
        let screens = PreviewScreen.allCases
        let states = PreviewState.allCases
        var renderedCount = 0

        for screen in screens {
            for state in states {
                let view = await PreviewFixtures.shared.makeView(screen: screen, state: state)

                // 1. Default (iPhone 17 Pro, standard Dynamic Type)
                if let dataDefault = renderView(view, size: size17Pro, dynamicTypeSize: .large) {
                    let name = "\(screen.rawValue)-\(state.rawValue)-default.png"
                    savePNG(data: dataDefault, filename: name)
                    renderedCount += 1
                }

                // 2. AX3 (iPhone 17 Pro, Accessibility 3)
                if let dataAX3 = renderView(view, size: size17Pro, dynamicTypeSize: .accessibility3) {
                    let name = "\(screen.rawValue)-\(state.rawValue)-ax3.png"
                    savePNG(data: dataAX3, filename: name)
                }

                // 3. AX5 (iPhone 17 Pro, Accessibility 5)
                if let dataAX5 = renderView(view, size: size17Pro, dynamicTypeSize: .accessibility5) {
                    let name = "\(screen.rawValue)-\(state.rawValue)-ax5.png"
                    savePNG(data: dataAX5, filename: name)
                }

                // 4. SE (iPhone SE 375x667)
                if let dataSE = renderView(view, size: sizeSE, dynamicTypeSize: .large) {
                    let name = "\(screen.rawValue)-\(state.rawValue)-se.png"
                    savePNG(data: dataSE, filename: name)
                }
            }
        }

        XCTAssertGreaterThanOrEqual(renderedCount, 21, "En az 21 temel PNG başarıyla render edilmelidir.")
    }

    func testImageRendererDirect() throws {
        let view = Text("ZENITHIUM TEST")
            .font(.largeTitle)
            .foregroundColor(.white)
            .frame(width: 400, height: 200)
            .background(Color.blue)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "ImageRenderer direct text nil olmamalı")
        if let data = image?.pngData() {
            let targetURL = outputDirectory.appendingPathComponent("test-text.png")
            try data.write(to: targetURL)
        }
    }
}
