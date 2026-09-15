//
//  DocumentVault.swift
//  Zenithium
//
//  Where the files live. Faz 26.
//
//  Originals live in the shared on-device container. Extensions do not read these files.
//  Legacy files remain readable until the next successful migration.
//
//  ## Protection
//
//  Written with `.completeFileProtection`: unreadable while the device is locked, including
//  by a background task. Nothing here needs to be read in the background, so the strictest
//  class costs nothing and is the only defensible choice for these documents.
//

import Foundation

actor DocumentVault {

    /// The directory holding stored documents.
    ///
    /// Excluded from automatic device backups; explicit export includes the originals.
    nonisolated static var directoryURL: URL? {
        AppGroup.containerURL?.appending(path: "LaboratoryDocuments", directoryHint: .isDirectory)
    }

    private nonisolated static var legacyDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Documents", directoryHint: .isDirectory)
    }

    /// The full path of a stored file.
    ///
    /// Resolved from the name each time rather than stored, because the container's location
    /// changes between installs — an absolute path saved today is a broken path after the
    /// next restore.
    nonisolated static func url(forFileName name: String) -> URL? {
        guard name == (name as NSString).lastPathComponent, !name.contains("..") else { return nil }
        if let current = directoryURL?.appending(path: name), FileManager.default.fileExists(atPath: current.path) { return current }
        if let legacy = legacyDirectoryURL?.appending(path: name), FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return directoryURL?.appending(path: name)
    }

    init() {}

    /// Copy a picked file into the vault, returning the name it was stored under.
    ///
    /// The name is the document's id plus the original extension. Using the user's own file
    /// name would collide the first time somebody imports two files called `rapor.pdf`, and
    /// renaming on collision leaves the vault full of `rapor-3.pdf` nobody can identify.
    func store(source: URL, id: UUID) throws -> String {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }
        return try store(data: Data(contentsOf: source), fileExtension: source.pathExtension, id: id)
    }

    func store(data: Data, fileExtension: String, id: UUID) throws -> String {
        guard let directory = Self.directoryURL else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(values)
        let ext = fileExtension.lowercased()
        guard ["pdf", "jpg", "jpeg", "png", "heic", "tiff", "gif"].contains(ext) else { throw LabImportFailure.unreadableDocument }
        let name = "\(id.uuidString).\(ext)"
        try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Remove a stored file. Missing is not an error — the metadata row is the record, and a
    /// vault entry whose file has gone should still be deletable.
    func remove(fileName: String) throws {
        guard fileName == (fileName as NSString).lastPathComponent, !fileName.contains("..") else {
            throw ZenithiumError.invalidEngineInput(reason: "Belge adı geçersiz.")
        }
        for folder in [Self.directoryURL, Self.legacyDirectoryURL].compactMap({ $0 }) {
            let url = folder.appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    /// Move originals without replacing an existing copy. A failed move leaves the source.
    func migrateLegacyFiles() throws {
        guard let legacy = Self.legacyDirectoryURL, FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard let directory = Self.directoryURL else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in try FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let target = directory.appending(path: source.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: source, to: target)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            }
        }
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    func removeAll() throws {
        for folder in [Self.directoryURL, Self.legacyDirectoryURL].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }

    /// Total bytes held, for the settings read-out.
    func totalBytes() -> Int64 {
        guard let directory = Self.directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.fileSizeKey]
              ) else { return 0 }

        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }
}
