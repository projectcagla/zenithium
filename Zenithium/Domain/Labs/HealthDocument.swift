//
//  HealthDocument.swift
//  Zenithium
//
//  Any health document, kept on device. Faz 26.
//
//  The generalisation of Faz 23: the lab importer already reads a PDF and pulls text and a
//  date out of it, and an ECG report, a discharge note or a vaccination card go through the
//  same two steps. What differs is only what happens next — a lab report becomes marker
//  values, and everything else becomes a searchable, dated entry in a timeline.
//
//  §12 draws a short line here. Zenithium **reads and stores**. It does not interpret a
//  radiology report, summarise a discharge note, or tell anybody what a document means. The
//  value is that the document is findable in five years, not that the app has an opinion
//  about it.
//

import Foundation

/// What kind of document this is.
///
/// The user picks; nothing is inferred from the text. Classifying a document by keyword is
/// exactly the kind of quiet guess that turns into a wrong label nobody notices for a year.
enum HealthDocumentKind: String, Sendable, Hashable, CaseIterable, Codable, Identifiable {
    case labReport
    case imaging
    case ecg
    case clinicalNote
    case prescription
    case vaccination
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .labReport: return "Tahlil"
        case .imaging: return "Görüntüleme"
        case .ecg: return "EKG"
        case .clinicalNote: return "Hekim notu"
        case .prescription: return "Reçete"
        case .vaccination: return "Aşı"
        case .other: return "Diğer"
        }
    }

    var symbolName: String {
        switch self {
        case .labReport: return "testtube.2"
        case .imaging: return "photo.on.rectangle"
        case .ecg: return "waveform.path.ecg"
        case .clinicalNote: return "doc.text"
        case .prescription: return "pills"
        case .vaccination: return "syringe"
        case .other: return "doc"
        }
    }
}

/// One stored document.
struct HealthDocument: Sendable, Equatable, Hashable, Identifiable, Codable {

    let id: UUID
    let kind: HealthDocumentKind

    /// What the user called it.
    let title: String

    /// The date the document is *about* — read from the text where possible, otherwise the
    /// day it was added. Distinct from `addedAt`, because a report filed years late still
    /// belongs on its own date in the timeline.
    let documentDate: Date

    let addedAt: Date

    /// The file's name inside the vault directory. Not a full path: the container's location
    /// changes between installs, so storing an absolute path would break every entry the
    /// first time the app is reinstalled.
    let fileName: String

    /// Extracted text, for search. Empty when the document had none and optical recognition
    /// found nothing either.
    let extractedText: String

    /// Free-text note.
    let note: String

    /// How the text was obtained, so a search that misses something can be explained.
    let textSource: LabTextSource

    init(
        id: UUID = UUID(),
        kind: HealthDocumentKind,
        title: String,
        documentDate: Date,
        addedAt: Date = Date(),
        fileName: String,
        extractedText: String,
        note: String = "",
        textSource: LabTextSource
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.documentDate = documentDate
        self.addedAt = addedAt
        self.fileName = fileName
        self.extractedText = extractedText
        self.note = note
        self.textSource = textSource
    }
}
