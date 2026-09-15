import Foundation
import Testing
import PDFKit
import UIKit
@testable import Zenithium

@Suite("Türkçe PDF golden vektörleri", .serialized)
struct LabPDFGoldenTests {
    private func draft(_ name: String) async throws -> LabReportDraft {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/Laboratory/\(name).pdf")
        let text = try await LabDocumentReader().read(data: Data(contentsOf: file), fileName: file.lastPathComponent, laboratory: true)
        let draft = LabReportParser.parse(text)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/lab-extraction")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try text.allLines.joined(separator: "\n").write(to: output.appending(path: name + ".txt"), atomically: true, encoding: .utf8)
        return draft
    }

    @Test("Düzen açıklamalı görsel rapor: sonuç ve önceki sonuç sütunları ayrılır")
    func annotatedReport() async throws {
        let report = try await draft("duzen-annotated")
        let ferritin = try #require(report.values.first { $0.marker.storageKey == "ferritin" })
        #expect(abs(ferritin.value - 52.6) < 0.001)
        #expect(ferritin.printedRange == MarkerRange(minimum: 15, maximum: 150))
    }

    @Test("Biruni metin PDF: nesne sırası sütunları karıştırmaz")
    func textColumns() async throws {
        let report = try await draft("biruni-text-columns")
        let ferritin = try #require(report.values.first { $0.marker.storageKey == "ferritin" })
        let glucose = try #require(report.values.first { $0.marker.storageKey == "fastingGlucose" })
        #expect(ferritin.value == 83)
        #expect(ferritin.printedRange == MarkerRange(minimum: 13, maximum: 150))
        #expect(glucose.value == 103)
        #expect(glucose.printedRange == MarkerRange(minimum: 70, maximum: 100))
        let crp = try #require(report.values.first { $0.marker.storageKey == "highSensitivityCRP" })
        #expect(crp.value == 4.7)
        #expect(!crp.isThreshold)
    }

    @Test("Biruni kodlanmış yazı tipi: sonuç ve referans korunur")
    func encodedFont() async throws {
        let report = try await draft("biruni-encoded-font")
        let vitamin = try #require(report.values.first { $0.marker.storageKey == "vitaminD" })
        #expect(abs(vitamin.value - 35.5) < 0.001)
        #expect(vitamin.printedRange == MarkerRange(minimum: 30, maximum: 80))

    }

    @Test("Fotoğraf yolu sayısal sonucu cihaz içi OCR ile korur")
    func imageImport() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/Laboratory/biruni-encoded-font.pdf")
        let page = try #require(PDFDocument(url: file)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let data = try #require(page.thumbnail(of: CGSize(width: bounds.width * 3, height: bounds.height * 3), for: .mediaBox).pngData())
        let text = try await LabDocumentReader().read(data: data, fileName: "rapor.png", laboratory: true)
        let report = LabReportParser.parse(text)
        let vitamin = try #require(report.values.first { $0.marker.storageKey == "vitaminD" })
        #expect(abs(vitamin.value - 35.5) < 0.001)
        #expect(report.source == .opticalRecognition)
    }
}
