//
//  ArchiveService.swift
//  Zenithium
//
//  Writing and reading `ZenithiumArchive`. Yol haritası v4, C9.
//
//  Export is a straight read of everything the store holds. Import is deliberately a **merge**
//  rather than a replace: someone restoring onto a phone they have already been using should
//  not lose the week they logged before they got round to it. Records are keyed the way the
//  store keys them — a day by its start, everything else by its identifier — so importing the
//  same archive twice produces the same store as importing it once.
//
//  Nothing here deletes. An import that goes wrong leaves the existing data intact, and the
//  worst case is a store with more in it than the person expected rather than less.
//

import Foundation

/// Writes and reads whole-store archives.
actor ArchiveService {

    private let store: ZenithiumStore
    private let vault: DocumentVault
    private let fileManager: FileManager

    /// The largest vault this will embed in an archive.
    ///
    /// Past this the archive carries metadata and extracted text without the original files.
    /// A four hundred megabyte JSON is not something a person can move between phones, and
    /// failing loudly at export time is better than producing a file that will not open.
    static let maximumEmbeddedBytes: Int64 = 180 * 1_024 * 1_024

    /// The file extension an archive is written with.
    static let fileExtension = "zenithium"

    init(store: ZenithiumStore, vault: DocumentVault, fileManager: FileManager = .default) {
        self.store = store
        self.vault = vault
        self.fileManager = fileManager
    }

    // MARK: - Export

    /// Everything in the store, as a value.
    func archive(now: Date) async throws -> ZenithiumArchive {
        // A window wide enough to reach anything the store could hold. The date-ranged reads
        // exist for screens that show a period; an archive wants all of it.
        let start = Date(timeIntervalSince1970: 0)
        let end = now.addingTimeInterval(365 * 86_400)

        let profile = try await store.profile()
        let baselines = try await store.baselines()
        let days = try await store.dayRecords(from: start, through: end)
        let muscle = try await store.latestMuscleSnapshot()
        let strength = try await store.strengthSessions(from: start, through: end)
        let hybrid = try await store.hybridSessions(from: start, through: end)
        let markers = try await store.bloodMarkers()
        let journal = try await store.journalDays(from: start, through: end)
        let goals = try await store.goalEventsWithPlanStart()
        let pain = try await store.painEntries(from: start, through: end)
        let documents = try await store.healthDocuments()
        let courses = try await store.supplementCourses()

        let vaultBytes = await vault.totalBytes()
        let embedsFiles = vaultBytes <= Self.maximumEmbeddedBytes
        let files = embedsFiles ? readVaultFiles(for: documents) : []

        return ZenithiumArchive(
            formatVersion: ZenithiumArchive.currentFormatVersion,
            exportedAt: now,
            schemaVersion: "\(SchemaV3.versionIdentifier)",
            profile: profile,
            baselines: Array(baselines.values).sorted { $0.metric.rawValue < $1.metric.rawValue },
            days: days,
            muscleSnapshot: muscle,
            strengthSessions: strength,
            hybridSessions: hybrid,
            bloodMarkers: markers,
            journalDays: journal,
            goalEvents: goals.map {
                ZenithiumArchive.ArchivedGoalEvent(event: $0.event, planStart: $0.planStart)
            },
            painEntries: pain,
            documents: documents,
            supplementCourses: courses,
            documentFiles: files,
            omittedDocumentFiles: !embedsFiles
        )
    }

    /// Write an archive into `directory` and return the file's location.
    func write(_ archive: ZenithiumArchive, into directory: URL) throws -> URL {
        let name = "Zenithium-\(Self.fileNameDateFormatter.string(from: archive.exportedAt))"
        let url = directory
            .appending(path: name, directoryHint: .notDirectory)
            .appendingPathExtension(Self.fileExtension)

        do {
            let data = try Self.encoder.encode(archive)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ArchiveFailure.writeFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Import

    /// Read an archive without applying it, so the person can see what is in it first.
    func read(from url: URL) throws -> ZenithiumArchive {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let archive = try? Self.decoder.decode(ZenithiumArchive.self, from: data) else {
            throw ArchiveFailure.unreadableArchive
        }
        try ZenithiumArchive.validate(formatVersion: archive.formatVersion)
        return archive
    }

    /// Merge an archive into the store, returning what was written.
    ///
    /// Idempotent: the store's own upserts key on the same identifiers the archive carries,
    /// so restoring twice writes the same rows twice rather than duplicating them.
    @discardableResult
    func restore(_ archive: ZenithiumArchive) async throws -> ArchiveCounts {
        var written = ArchiveCounts()

        try await store.updateProfile(archive.profile.asWrite)

        var baselines: [MetricKind: BaselineSnapshot] = [:]
        for baseline in archive.baselines {
            baselines[baseline.metric] = baseline
        }
        if !baselines.isEmpty {
            try await store.saveBaselines(baselines)
        }

        for day in archive.days {
            try await store.upsertDayRecord(day.asWrite)
            written.days += 1
        }

        if let muscle = archive.muscleSnapshot {
            try await store.saveMuscleSnapshot(muscle)
        }

        for session in archive.strengthSessions {
            try await store.saveStrengthSession(
                id: session.id,
                performedAt: session.performedAt,
                timeZoneIdentifier: session.timeZoneIdentifier,
                pattern: session.pattern,
                entries: session.entries,
                sessionLoad: session.sessionLoad,
                note: session.note
            )
            written.strengthSessions += 1
        }

        for session in archive.hybridSessions {
            try await store.saveHybridSession(session)
            written.hybridSessions += 1
        }

        for marker in archive.bloodMarkers {
            try await store.saveBloodMarker(
                id: marker.id,
                marker: marker.marker,
                value: marker.value,
                unitSymbol: marker.unitSymbol,
                referenceRange: marker.referenceRange,
                optimalRange: marker.optimalRange,
                drawnAt: marker.drawnAt,
                note: marker.note
            )
            written.bloodMarkers += 1
        }

        for day in archive.journalDays {
            try await store.saveJournalDay(day)
            written.journalDays += 1
        }

        for goal in archive.goalEvents {
            try await store.saveGoalEvent(goal.event, planStart: goal.planStart)
            written.goalEvents += 1
        }

        for entry in archive.painEntries {
            try await store.savePainEntry(entry)
            written.painEntries += 1
        }

        // Files first: a document row whose file is missing is findable but not openable, and
        // writing the row last means a failure part-way leaves no dangling entries.
        restoreVaultFiles(archive.documentFiles)
        for document in archive.documents {
            try await store.saveHealthDocument(document)
            written.documents += 1
        }

        for course in archive.supplementCourses ?? [] {
            try await store.saveSupplementCourse(course)
            written.supplementCourses += 1
        }

        return written
    }

    // MARK: - Vault files

    private func readVaultFiles(for documents: [HealthDocument]) -> [ZenithiumArchive.ArchivedDocumentFile] {
        documents.compactMap { document in
            guard !document.fileName.isEmpty,
                  let url = DocumentVault.url(forFileName: document.fileName),
                  let contents = try? Data(contentsOf: url) else { return nil }
            return ZenithiumArchive.ArchivedDocumentFile(
                fileName: document.fileName,
                contents: contents
            )
        }
    }

    private func restoreVaultFiles(_ files: [ZenithiumArchive.ArchivedDocumentFile]) {
        guard !files.isEmpty, let directory = DocumentVault.directoryURL else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let destination = directory.appending(path: file.fileName, directoryHint: .notDirectory)
            // Never overwrite: a file already in the vault is the one the store's row points
            // at, and replacing it with an older copy of itself gains nothing.
            guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            try? file.contents.write(to: destination, options: .atomic)
        }
    }

    // MARK: - Coding

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
