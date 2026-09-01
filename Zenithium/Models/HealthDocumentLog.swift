//
//  HealthDocumentLog.swift
//  Zenithium
//
//  A stored document's metadata. Faz 26.
//
//  The PDF itself lives on disk under the app's own container; only its name and extracted
//  text are in SwiftData. Putting a multi-megabyte scan in the store would bloat every fetch
//  that touches the model, and the file system is already very good at holding files.
//

import Foundation
import SwiftData

@Model
final class HealthDocumentLog {

    @Attribute(.unique) var id: UUID

    /// `HealthDocumentKind.rawValue`.
    var kindRawValue: String

    var title: String
    var documentDate: Date
    var addedAt: Date

    /// Name inside the vault directory, never an absolute path.
    var fileName: String

    /// Extracted text, kept for search.
    ///
    /// `.externalStorage` so a long report does not sit inline in every row SwiftData reads.
    @Attribute(.externalStorage) var extractedText: String

    var note: String

    /// `LabTextSource.rawValue`.
    var textSourceRawValue: String

    init(document: HealthDocument) {
        self.id = document.id
        self.kindRawValue = document.kind.rawValue
        self.title = document.title
        self.documentDate = document.documentDate
        self.addedAt = document.addedAt
        self.fileName = document.fileName
        self.extractedText = document.extractedText
        self.note = document.note
        self.textSourceRawValue = document.textSource.rawValue
    }

    var document: HealthDocument? {
        guard let kind = HealthDocumentKind(rawValue: kindRawValue),
              let source = LabTextSource(rawValue: textSourceRawValue) else { return nil }
        return HealthDocument(
            id: id,
            kind: kind,
            title: title,
            documentDate: documentDate,
            addedAt: addedAt,
            fileName: fileName,
            extractedText: extractedText,
            note: note,
            textSource: source
        )
    }
}
