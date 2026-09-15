import Foundation

/// Stable row IDs make retry safe even if a store committed before reporting an error.
actor LabImportCoordinator {
    private let repository: any BloodMarkerRepository
    private let reader = LabDocumentReader()
    private let documents: (any HealthDocumentRepository)?
    private let vault = DocumentVault()
    private var pendingData: Data?
    private var pendingText: LabDocumentText?
    private var documentID = UUID()
    private var documentStored = false

    init(repository: any BloodMarkerRepository, documents: (any HealthDocumentRepository)? = nil) {
        self.repository = repository
        self.documents = documents
    }

    func read(fileURL: URL) async throws -> LabReportDraft {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40 * 1_024 * 1_024 else { throw LabImportFailure.documentTooLarge }
        return try await read(data: Data(contentsOf: fileURL), fileName: fileURL.lastPathComponent)
    }

    func read(data: Data, fileName: String) async throws -> LabReportDraft {
        let text = try await reader.read(data: data, fileName: fileName, laboratory: true)
        pendingData = data
        pendingText = text
        documentID = UUID()
        documentStored = false
        return LabReportParser.parse(text)
    }

    private func saveDocument(drawnAt: Date) async throws {
        guard !documentStored, let documents, let data = pendingData, let text = pendingText else { return }
        let ext = try LabDocumentReader.fileExtension(for: data)
        let name = try await vault.store(data: data, fileExtension: ext, id: documentID)
        do {
            try await documents.saveHealthDocument(HealthDocument(id: documentID, kind: .labReport, title: text.fileName,
                documentDate: drawnAt, fileName: name, extractedText: text.allLines.joined(separator: "\n"), textSource: text.source))
        } catch {
            let writeError = error
            do { try await vault.remove(fileName: name) }
            catch { throw ZenithiumError.persistenceWriteFailed(detail: "Belge kaydı ve dosya temizliği tamamlanamadı: \(writeError.localizedDescription); \(error.localizedDescription)") }
            throw writeError
        }
        documentStored = true
    }

    func saveOriginal(drawnAt: Date) async throws {
        guard documents != nil, pendingData != nil else { throw LabImportFailure.unreadableDocument }
        try await saveDocument(drawnAt: drawnAt)
    }

    func save(_ rows: [LabApprovedRow], drawnAt: Date) async -> LabSaveOutcome {
        var saved = Set<UUID>()
        guard !rows.isEmpty else { return LabSaveOutcome(savedIDs: saved, failure: "Kaydedilecek onaylı satır yok.") }
        do {
            for row in rows { _ = try LabRecording.prepare(marker: row.marker, value: row.value, unit: row.unit, reference: row.reference) }
            try await saveDocument(drawnAt: drawnAt)
        }
        catch { return LabSaveOutcome(savedIDs: saved, failure: "Kaynak belge kaydedilemedi: \(error.localizedDescription)") }
        for row in rows {
            do {
                try Task.checkCancellation()
                let record = try LabRecording.prepare(marker: row.marker, value: row.value, unit: row.unit, reference: row.reference)
                try await repository.saveBloodMarker(id: row.id, marker: row.marker, value: record.value,
                    unitSymbol: record.unit, referenceRange: record.reference, optimalRange: .unbounded,
                    drawnAt: drawnAt, note: row.note)
                saved.insert(row.id)
            } catch {
                return LabSaveOutcome(savedIDs: saved, failure: "Kaydedilemeyen satırlar var: \(error.localizedDescription)")
            }
        }
        return LabSaveOutcome(savedIDs: saved, failure: nil)
    }
}
