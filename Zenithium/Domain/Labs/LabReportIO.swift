//
//  LabReportIO.swift
//  Zenithium
//
//  Types crossing the laboratory-import boundary. Faz 23.
//
//  The shape here encodes the rule the whole feature is built on: parsing produces a
//  *draft*, never a record. Nothing reaches SwiftData until a person has looked at every
//  row. `ParsedLabValue` therefore carries its own provenance — which line it came from,
//  how the text was obtained, and how much the parser trusts itself — so the review screen
//  can show its work rather than asking for blind agreement.
//

import Foundation

/// How the text was obtained from the document.
enum LabTextSource: String, Sendable, Codable, Hashable {

    /// The PDF carried a real text layer. Character-exact.
    case textLayer

    /// The page was rasterised and read by Vision. Accurate, but not exact.
    case opticalRecognition

    /// Whether values from this source deserve a confidence penalty.
    var isExact: Bool { self == .textLayer }

    var displayName: String {
        switch self {
        case .textLayer: return "PDF metni"
        case .opticalRecognition: return "Görüntüden okundu"
        }
    }
}

/// One page's worth of extracted text.
struct LabDocumentPage: Sendable, Hashable {

    /// 1-based page number, as printed.
    let pageNumber: Int

    /// Lines in reading order, already trimmed of surrounding whitespace.
    let lines: [String]

    let source: LabTextSource
}

/// A whole document, after extraction and before parsing.
struct LabDocumentText: Sendable, Hashable {

    let pages: [LabDocumentPage]

    /// The file's own name, shown in the review header so the user knows what they opened.
    let fileName: String

    /// Every line across every page, in order.
    var allLines: [String] {
        pages.flatMap(\.lines)
    }

    /// The dominant source. A mixed document (some pages text, some scanned) reports the
    /// weaker of the two, because the weaker one is what limits trust.
    var source: LabTextSource {
        pages.contains { $0.source == .opticalRecognition } ? .opticalRecognition : .textLayer
    }

    var isEmpty: Bool {
        pages.allSatisfy { $0.lines.isEmpty }
    }
}

/// How much the parser trusts one extracted row.
enum ParseConfidence: String, Sendable, Codable, Hashable, CaseIterable {

    /// Marker, value and a recognised unit all agreed.
    case high

    /// Something was inferred — an unrecognised unit, a short abbreviation, a value far
    /// from the published band.
    case medium

    /// Enough was uncertain that the row starts switched off in the review list.
    case low

    /// Below this the row is not offered at all.
    static let discardThreshold = 0.35

    static func bucket(forScore score: Double) -> ParseConfidence {
        if score >= 0.85 { return .high }
        if score >= 0.60 { return .medium }
        return .low
    }

    var displayName: String {
        switch self {
        case .high: return "Yüksek"
        case .medium: return "Orta"
        case .low: return "Düşük"
        }
    }

    /// Whether a row of this confidence is pre-selected for import.
    ///
    /// Low-confidence rows are shown but start unchecked: the user opts *in* to a guess,
    /// rather than having to notice and opt out of one.
    var isPreselected: Bool {
        self != .low
    }
}

/// One marker the parser believes it found.
struct ParsedLabValue: Sendable, Hashable, Identifiable {

    let id: UUID

    /// The matched catalogue marker.
    let marker: BloodMarkerKind

    /// The value exactly as printed, in `unitSymbol`.
    let value: Double

    /// The unit as printed. Empty when the report did not print one on that line.
    let unitSymbol: String

    /// Whether the printed unit is one the marker accepts. A `false` here does not block
    /// import — the user may know better than the catalogue — but it costs confidence.
    let unitIsRecognised: Bool

    /// The reference band printed on the report itself, when the line carried one. This is
    /// the laboratory's own band and takes precedence over the catalogue's.
    let printedRange: MarkerRange?

    /// The value was printed as a threshold ("<0.3"), so the true value is only bounded.
    let isThreshold: Bool

    /// The raw line, shown verbatim under the row so the user can check the parse.
    let sourceLine: String

    let pageNumber: Int

    let confidence: ParseConfidence

    /// The 0…1 score `confidence` was bucketed from, kept for ordering.
    let confidenceScore: Double

    init(
        id: UUID = UUID(),
        marker: BloodMarkerKind,
        value: Double,
        unitSymbol: String,
        unitIsRecognised: Bool,
        printedRange: MarkerRange?,
        isThreshold: Bool,
        sourceLine: String,
        pageNumber: Int,
        confidenceScore: Double
    ) {
        self.id = id
        self.marker = marker
        self.value = value
        self.unitSymbol = unitSymbol
        self.unitIsRecognised = unitIsRecognised
        self.printedRange = printedRange
        self.isThreshold = isThreshold
        self.sourceLine = sourceLine
        self.pageNumber = pageNumber
        self.confidenceScore = confidenceScore
        self.confidence = ParseConfidence.bucket(forScore: confidenceScore)
    }
}

/// Everything one parsed document offers the review screen.
struct LabReportDraft: Sendable, Hashable {

    let fileName: String
    let source: LabTextSource

    /// The draw date the parser found in the document, if it found one. The review screen
    /// always shows a date picker, pre-filled with this or with today.
    let detectedDrawDate: Date?

    /// Rows the parser is offering, strongest first.
    let values: [ParsedLabValue]

    /// Lines that named a marker but yielded no usable number. Surfaced as a count so the
    /// user knows the parser saw something it could not read, rather than silently missing it.
    let unreadableLineCount: Int

    var isEmpty: Bool { values.isEmpty }
}

/// Why an import could not proceed.
enum LabImportFailure: Error, Sendable, Equatable {

    /// The file could not be opened as a PDF.
    case unreadableDocument

    /// The document opened but is locked.
    case passwordProtected

    /// Text came out, but nothing in it looked like a laboratory result.
    case noRecognisableMarkers

    /// The document had no text layer and optical recognition produced nothing.
    case noTextFound

    /// The security-scoped resource could not be accessed.
    case accessDenied

    var message: String {
        switch self {
        case .unreadableDocument:
            return "Bu dosya PDF olarak açılamadı."
        case .passwordProtected:
            return "PDF parola korumalı. Parolasız bir kopyasını dışa aktarıp tekrar dene."
        case .noRecognisableMarkers:
            return "Belge okundu ama tanıdığım bir tahlil değeri bulamadım. Değerleri elle girebilirsin."
        case .noTextFound:
            return "Belgeden metin çıkaramadım. Tarama çok düşük çözünürlüklü olabilir."
        case .accessDenied:
            return "Dosyaya erişilemedi."
        }
    }
}
