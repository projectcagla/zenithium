//
//  DocumentVault.swift
//  Zenithium
//
//  Where the files live. Faz 26.
//
//  ## Why the app's own container and not the App Group
//
//  Everything else shared lives in the group so the widgets can read it. These files should
//  not be readable by an extension that has no reason to open them, and a scan of somebody's
//  discharge note is the last thing that belongs in a container three targets can reach.
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
    /// Under Application Support rather than Documents: these are the app's own copies of
    /// files the user already has elsewhere, not documents the user manages through Files.
    nonisolated static var directoryURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base.appending(path: "Documents", directoryHint: .isDirectory)
    }

    /// The full path of a stored file.
    ///
    /// Resolved from the name each time rather than stored, because the container's location
    /// changes between installs — an absolute path saved today is a broken path after the
    /// next restore.
    nonisolated static func url(forFileName name: String) -> URL? {
        directoryURL?.appending(path: name, directoryHint: .notDirectory)
    }

    init() {}

    /// Copy a picked file into the vault, returning the name it was stored under.
    ///
    /// The name is the document's id plus the original extension. Using the user's own file
    /// name would collide the first time somebody imports two files called `rapor.pdf`, and
    /// renaming on collision leaves the vault full of `rapor-3.pdf` nobody can identify.
    func store(source: URL, id: UUID) throws -> String {
        guard let directory = Self.directoryURL else {
            throw ZenithiumError.persistenceWriteFailed(detail: "Belge klasörü bulunamadı.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destination = directory.appending(path: fileName, directoryHint: .notDirectory)

        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return fileName
    }

    /// Remove a stored file. Missing is not an error — the metadata row is the record, and a
    /// vault entry whose file has gone should still be deletable.
    func remove(fileName: String) {
        guard let url = Self.url(forFileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
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
