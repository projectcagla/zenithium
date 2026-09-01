//
//  DocumentsViewModel.swift
//  Zenithium
//
//  The document vault screen. Faz 26.
//

import Foundation
import Observation

@MainActor
@Observable
final class DocumentsViewModel {

    struct Content: Sendable, Equatable {

        let documents: [HealthDocument]

        /// Documents grouped by year, newest year first — the shape a medical history is
        /// actually recalled in.
        ///
        /// Grouped once at load rather than on every access. It was a computed property, and
        /// `filtered` reads it on every keystroke, so typing re-grouped and re-sorted the
        /// whole vault per character. Yol haritası v4, A6.
        let byYear: [YearGroup]

        /// Each document's searchable text, folded once.
        ///
        /// The real cost of the old search was not the grouping: `matches(query:)` normalised
        /// `title + note + extractedText` per document per keystroke, and extracted text is
        /// the whole of a scanned report. Forty documents at fifty kilobytes each meant
        /// folding two megabytes to filter a list — for a result that never changes between
        /// keystrokes. Folded here once, when the documents load.
        let searchText: [UUID: String]

        init(documents: [HealthDocument], calendar: Calendar = .autoupdatingCurrent) {
            self.documents = documents

            let grouped = Dictionary(grouping: documents) {
                calendar.component(.year, from: $0.documentDate)
            }
            self.byYear = grouped
                .map { YearGroup(year: $0.key, documents: $0.value.sorted { $0.documentDate > $1.documentDate }) }
                .sorted { $0.year > $1.year }

            self.searchText = Dictionary(
                uniqueKeysWithValues: documents.map {
                    ($0.id, BiomarkerCatalog.normalize("\($0.title) \($0.note) \($0.extractedText)"))
                }
            )
        }
    }

    /// One year's documents.
    struct YearGroup: Sendable, Equatable, Identifiable {
        let year: Int
        let documents: [HealthDocument]
        var id: Int { year }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isImporting = false
    private(set) var importError: String?

    /// The search query. Filtering happens in `filtered`, so typing never triggers a read.
    var query = ""

    private let repository: any HealthDocumentRepository
    private let reader = LabDocumentReader()
    private let vault = DocumentVault()
    private let nowProvider: @Sendable () -> Date

    init(
        repository: any HealthDocumentRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.nowProvider = nowProvider
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        do {
            state = .loaded(Content(documents: try await repository.healthDocuments()))
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// The documents matching the current query.
    ///
    /// Compares against the index built at load, so a keystroke costs one fold of the query
    /// and a substring search per document — not a fold of every document's full text.
    func filtered(_ content: Content) -> [YearGroup] {
        let needle = BiomarkerCatalog.normalize(query)
        guard !needle.isEmpty else { return content.byYear }
        return content.byYear.compactMap { group in
            let matches = group.documents.filter {
                content.searchText[$0.id]?.contains(needle) ?? false
            }
            return matches.isEmpty ? nil : YearGroup(year: group.year, documents: matches)
        }
    }

    /// Import a picked file: copy it into the vault, read its text, store the metadata.
    ///
    /// The copy happens first. If text extraction fails — a scan too poor to read, a PDF
    /// this build cannot parse — the document is still stored and still findable by its
    /// title. Losing the file because the text could not be read would be the wrong trade.
    func `import`(url: URL, kind: HealthDocumentKind, title: String) async {
        isImporting = true
        defer { isImporting = false }

        let id = UUID()
        let now = nowProvider()

        do {
            let fileName = try await vault.store(source: url, id: id)

            var extractedText = ""
            var source = LabTextSource.textLayer
            var documentDate = now

            if let text = try? await reader.read(fileURL: url) {
                extractedText = text.allLines.joined(separator: "\n")
                source = text.source
                if let detected = LabReportParser.detectDrawDate(in: text.allLines, referenceDate: now) {
                    documentDate = detected
                }
            }

            let trimmed = title.trimmingCharacters(in: .whitespaces)
            try await repository.saveHealthDocument(
                HealthDocument(
                    id: id,
                    kind: kind,
                    title: trimmed.isEmpty ? kind.displayName : trimmed,
                    documentDate: documentDate,
                    addedAt: now,
                    fileName: fileName,
                    extractedText: extractedText,
                    textSource: source
                )
            )
            importError = nil
            await load()
        } catch {
            importError = "Belge kaydedilemedi."
        }
    }

    func delete(_ document: HealthDocument) async {
        do {
            try await repository.deleteHealthDocument(id: document.id)
            await vault.remove(fileName: document.fileName)
            await load()
        } catch {
            importError = "Belge silinemedi."
        }
    }
}
