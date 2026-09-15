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
import ImageIO

actor LabDocumentReader {

    /// How much a page is scaled up before optical recognition. Below 2× the smaller print
    /// on a laboratory report starts losing digits, which is the one thing we cannot afford.
    private static let renderScale: CGFloat = 3.0

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

        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40 * 1_024 * 1_024 else { throw LabImportFailure.documentTooLarge }
        return try await read(data: Data(contentsOf: fileURL), fileName: fileURL.lastPathComponent)
    }

    /// Data stays in memory until the person explicitly approves the import.
    func read(data: Data, fileName: String, laboratory: Bool = false) async throws -> LabDocumentText {
        guard data.count <= 40 * 1_024 * 1_024 else { throw LabImportFailure.documentTooLarge }
        var pages: [LabDocumentPage] = []
        if let document = PDFDocument(data: data) {
            guard !document.isLocked else { throw LabImportFailure.passwordProtected }
            guard document.pageCount <= 50 else { throw LabImportFailure.documentTooLarge }
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                pages.append(try read(page: page, number: index + 1, laboratory: laboratory))
            }
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3_000
                  ] as CFDictionary) else { throw LabImportFailure.unreadableDocument }
            pages = [LabDocumentPage(pageNumber: 1, lines: try recogniseText(on: image), source: .opticalRecognition)]
        }
        let text = LabDocumentText(pages: pages, fileName: fileName)
        guard !text.isEmpty else { throw LabImportFailure.noTextFound }
        return text
    }

    private func read(page: PDFPage, number: Int, laboratory: Bool) throws -> LabDocumentPage {
        let embedded = page.string ?? ""
        let controls = embedded.unicodeScalars.filter { CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        if embedded.count >= Self.minimumTextLayerCharacters, controls * 50 < embedded.count {
            let lines = laboratory ? positionedLines(on: page, text: embedded) : split(embedded)
            let candidate = LabDocumentPage(pageNumber: number, lines: lines, source: .textLayer)
            if !laboratory || !LabReportParser.parse(LabDocumentText(pages: [candidate], fileName: "")).isEmpty {
                return candidate
            }
        }
        let recognised = try recogniseText(on: page)
        return LabDocumentPage(pageNumber: number, lines: recognised, source: .opticalRecognition)
    }

    nonisolated static func fileExtension(for data: Data) throws -> String {
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else {
            throw LabImportFailure.unreadableDocument
        }
        switch type as String {
        case "public.png": return "png"
        case "public.heic", "public.heif": return "heic"
        case "public.tiff": return "tiff"
        case "com.compuserve.gif": return "gif"
        case "public.jpeg": return "jpg"
        default: throw LabImportFailure.unreadableDocument
        }
    }

    // MARK: - Text layer

    /// PDF object order is not table order. Group whole words by their printed positions,
    /// preserving exact digits and keeping result/reference columns on the same row.
    private func positionedLines(on page: PDFPage, text: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: "\\S+") else { return [] }
        let string = text as NSString
        let fragments = pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match -> LabTextFragment? in
            guard let selection = page.selection(for: match.range) else { return nil }
            let bounds = selection.bounds(for: page)
            guard !bounds.isNull, bounds.height > 0, bounds.height.isFinite, bounds.midY.isFinite else { return nil }
            return LabTextFragment(text: string.substring(with: match.range), midY: Double(bounds.midY),
                minX: Double(bounds.minX), height: Double(bounds.height))
        }
        return LabTextFragment.assembleLines(from: fragments, bandHeightFactor: 0.45,
            fallbackTolerance: 3, estimateRotation: false)
    }

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

        return try recogniseText(on: image, estimateRotation: false)
    }

    private func recogniseText(on image: CGImage, estimateRotation: Bool = true) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["tr-TR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        return assembleLines(from: observations, estimateRotation: estimateRotation)
    }

    /// Rasterise one page.
    private func image(of page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0, bounds.width <= 4_000, bounds.height <= 4_000 else { return nil }

        let width = Int((bounds.width * Self.renderScale).rounded())
        let height = Int((bounds.height * Self.renderScale).rounded())
        guard width > 0, height > 0, width <= 8_000, height <= 8_000, width * height <= 24_000_000 else { return nil }

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
    private func assembleLines(from observations: [VNRecognizedTextObservation], estimateRotation: Bool) -> [String] {
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
            fallbackTolerance: Self.lineGroupingTolerance,
            estimateRotation: estimateRotation
        )
    }
}
