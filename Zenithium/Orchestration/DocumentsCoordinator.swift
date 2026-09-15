import Foundation

actor DocumentsCoordinator {
    private let repository: any HealthDocumentRepository
    private let reader = LabDocumentReader()
    private let vault = DocumentVault()

    init(repository: any HealthDocumentRepository) { self.repository = repository }

    func load() async throws -> [HealthDocument] {
        try await vault.migrateLegacyFiles()
        return try await repository.healthDocuments()
    }

    /// A readable original can be kept even when OCR fails; the caller shows that warning.
    func store(url: URL, kind: HealthDocumentKind, title: String, now: Date) async throws -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40 * 1_024 * 1_024 else { throw LabImportFailure.documentTooLarge }
        let data = try Data(contentsOf: url)
        let ext = try LabDocumentReader.fileExtension(for: data)
        var text: LabDocumentText?
        var warning: String?
        do { text = try await reader.read(data: data, fileName: url.lastPathComponent) }
        catch is CancellationError { throw CancellationError() }
        catch { warning = "Belgenin aslı saklandı; metni okunamadı: \(error.localizedDescription)" }
        let id = UUID()
        let name = try await vault.store(data: data, fileExtension: ext, id: id)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await repository.saveHealthDocument(HealthDocument(id: id, kind: kind,
                title: trimmed.isEmpty ? kind.displayName : trimmed,
                documentDate: text.flatMap { LabReportParser.detectDrawDate(in: $0.allLines, referenceDate: now) } ?? now,
                addedAt: now, fileName: name, extractedText: text?.allLines.joined(separator: "\n") ?? "",
                textSource: text?.source ?? .textLayer))
        } catch {
            let writeError = error
            do { try await vault.remove(fileName: name) }
            catch { throw ZenithiumError.persistenceWriteFailed(detail: "Belge kaydı ve dosya temizliği tamamlanamadı: \(writeError.localizedDescription); \(error.localizedDescription)") }
            throw writeError
        }
        return warning
    }

    func delete(_ document: HealthDocument) async throws {
        try await vault.remove(fileName: document.fileName)
        try await repository.deleteHealthDocument(id: document.id)
    }
}
