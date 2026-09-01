//
//  LabDocumentReader.swift
//  Zenithium
//
//  Gets text out of a laboratory PDF. Faz 23.
//
//  ASSUMPTION LAB-1: this file imports PDFKit and Vision, which are not on the §2.2
//  framework list. Both are first-party, both run entirely on device, and neither adds a
//  capability beyond reading a file the user handed us — no network, no service, no model
//  download. Reversal: drop the importer and keep manual entry, which still works.
//
//  ASSUMPTION LAB-2: pages are rasterised at 2× and read in greyscale. Laboratory reports
//  are black text on white; colour carries nothing, and greyscale halves the buffer.
//  Reversal: change `renderScale` and the colour space in `image(of:)`.
//
//  The reader deliberately knows nothing about biomarkers. It returns lines; `LabReportParser`
//  decides what they mean.
//

import Foundation
import CoreGraphics
import PDFKit
import Vision

actor LabDocumentReader {

    /// How much a page is scaled up before optical recognition. Below 2× the smaller print
    /// on a laboratory report starts losing digits, which is the one thing we cannot afford.
    private static let renderScale: CGFloat = 2.0

    /// A page whose text layer yields less than this is treated as an image. Reports with a
    /// thin text layer — a scanner that embedded only the header — would otherwise parse as
    /// an almost-empty document.
    private static let minimumTextLayerCharacters = 60

    /// How far apart two recognised fragments can sit vertically and still count as one
    /// line, as a fraction of page height.
    ///
    /// Only the fallback. The band is normally derived from the fragments' own heights —
    /// see `assembleLines` — because a fixed fraction of the page is wrong in both
    /// directions: too wide for a dense hemogram printed at eight points, too narrow for a
    /// report set large. This value is what is used when the observations carry no usable
    /// height at all.
    private static let lineGroupingTolerance: Double = 0.008

    /// The band, as a multiple of the median fragment height.
    ///
    /// Below one, so two adjacent printed rows cannot merge; well above zero, so a unit set
    /// slightly lower than its value stays on its own row.
    private static let bandHeightFactor: Double = 0.7

    init() {}

    // MARK: - Reading

    /// Read a PDF into lines of text, falling back to optical recognition per page.
    func read(fileURL: URL) async throws -> LabDocumentText {
        // Signposted because this is the one path in the app that can plausibly take
        // seconds: a scanned report falls through to Vision, page by page. Yol haritası v4, A9.
        try await ZenithiumSignpost.interval(ZenithiumSignpost.labs, "readDocument") {
            try await readDocument(fileURL: fileURL)
        }
    }

    private func readDocument(fileURL: URL) async throws -> LabDocumentText {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: fileURL) else {
            throw LabImportFailure.unreadableDocument
        }
        guard !document.isLocked else {
            throw LabImportFailure.passwordProtected
        }

        var pages: [LabDocumentPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append(try read(page: page, number: index + 1))
        }

        let text = LabDocumentText(pages: pages, fileName: fileURL.lastPathComponent)
        guard !text.isEmpty else { throw LabImportFailure.noTextFound }
        return text
    }

    /// Read raw data rather than a file, for the share sheet and for tests.
    func read(data: Data, fileName: String) async throws -> LabDocumentText {
        guard let document = PDFDocument(data: data) else {
            throw LabImportFailure.unreadableDocument
        }
        guard !document.isLocked else {
            throw LabImportFailure.passwordProtected
        }

        var pages: [LabDocumentPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append(try read(page: page, number: index + 1))
        }

        let text = LabDocumentText(pages: pages, fileName: fileName)
        guard !text.isEmpty else { throw LabImportFailure.noTextFound }
        return text
    }

    private func read(page: PDFPage, number: Int) throws -> LabDocumentPage {
        let embedded = page.string ?? ""
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumTextLayerCharacters {
            return LabDocumentPage(pageNumber: number, lines: split(embedded), source: .textLayer)
        }
        let recognised = try recogniseText(on: page)
        return LabDocumentPage(pageNumber: number, lines: recognised, source: .opticalRecognition)
    }

    // MARK: - Text layer

    /// Break a page's embedded text into trimmed, non-empty lines.
    private func split(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Optical recognition

    /// Read a page as an image.
    ///
    /// Language correction is off on purpose: it exists to fix words, and everything that
    /// matters on this page is a number. Correcting "45,2" into a likelier word would be
    /// exactly the wrong kind of help.
    private func recogniseText(on page: PDFPage) throws -> [String] {
        guard let image = self.image(of: page) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["tr-TR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        return assembleLines(from: observations)
    }

    /// Rasterise one page.
    private func image(of page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let width = Int((bounds.width * Self.renderScale).rounded())
        let height = Int((bounds.height * Self.renderScale).rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Reports are black on white; without the fill, unpainted areas come out black and
        // recognition sees an inverted page.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: Self.renderScale, y: Self.renderScale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    /// Stitch recognised fragments back into reading order.
    ///
    /// This matters more than the recognition itself. Vision returns a laboratory table as
    /// scattered fragments — "Ferritin" in one, "45,2" in another, "ng/mL" in a third — and
    /// a parser handed those separately can never pair a marker with its value. Fragments
    /// sharing a horizontal band are therefore merged, left to right, into one line.
    private func assembleLines(from observations: [VNRecognizedTextObservation]) -> [String] {
        let fragments: [LabTextFragment] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Explicit conversions rather than relying on the CGFloat/Double bridge, so the
            // geometry type stays Foundation-only and shareable with the watch target.
            return LabTextFragment(
                text: candidate.string,
                midY: Double(box.midY),
                minX: Double(box.minX),
                height: Double(box.height)
            )
        }
        return LabTextFragment.assembleLines(
            from: fragments,
            bandHeightFactor: Self.bandHeightFactor,
            fallbackTolerance: Self.lineGroupingTolerance
        )
    }
}
