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
//  Imports validate before writing. Storage failures can leave a partial merge; retrying
//  the same archive is idempotent. Explicit erasure is a separate user action.
//

import Foundation

/// Writes and reads whole-store archives.
actor ArchiveService {

    private let store: ZenithiumStore
    private let vault: DocumentVault
    private let fileManager: FileManager
    private let preferences: (any PersonalPreferenceRepository)?
    private let beforeRestore: @Sendable () async -> Void
    private let afterRestore: @Sendable () async -> Void

    /// The largest vault this will embed in an archive.
    ///
    /// Exports above this limit fail explicitly; original files are never silently omitted.
    static let maximumEmbeddedBytes: Int64 = 180 * 1_024 * 1_024

    /// The file extension an archive is written with.
    static let fileExtension = "zenithium"

    init(store: ZenithiumStore, vault: DocumentVault, preferences: (any PersonalPreferenceRepository)? = nil,
         fileManager: FileManager = .default,
         beforeRestore: @escaping @Sendable () async -> Void = {},
         afterRestore: @escaping @Sendable () async -> Void = {}) {
        self.store = store
        self.vault = vault
        self.fileManager = fileManager
        self.preferences = preferences
        self.beforeRestore = beforeRestore
        self.afterRestore = afterRestore
    }

    func eraseAll() async throws {
        try await vault.removeAll()
        try await store.eraseAll()
        try await preferences?.reset()
        for url in try fileManager.contentsOfDirectory(at: fileManager.temporaryDirectory, includingPropertiesForKeys: nil) {
            if url.lastPathComponent.hasPrefix("Zenithium-") && url.pathExtension == Self.fileExtension {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Export

    /// Everything in the store, as a value.
    func archive(now: Date) async throws -> ZenithiumArchive {
        // A window wide enough to reach anything the store could hold. The date-ranged reads
        // exist for screens that show a period; an archive wants all of it.
        let start = Date.distantPast
        let end = Date.distantFuture
        try await vault.migrateLegacyFiles()

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
        guard vaultBytes <= Self.maximumEmbeddedBytes else {
            throw ArchiveFailure.writeFailed(detail: "Belge boyutu bu cihazda tek dosya sınırını aşıyor. Eksik bir arşiv oluşturulmadı.")
        }
        let files = try readVaultFiles(for: documents)

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
            omittedDocumentFiles: false,
            preferences: try await preferences?.load()
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
            try data.write(to: url, options: [.atomic, .completeFileProtection])
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

        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= 320 * 1_024 * 1_024 else { throw ArchiveFailure.unreadableArchive }
        guard let data = try? Data(contentsOf: url),
              let archive = try? Self.decoder.decode(ZenithiumArchive.self, from: data) else {
            throw ArchiveFailure.unreadableArchive
        }
        try Self.validate(archive)
        return archive
    }

    /// Merge an archive into the store, returning what was written.
    ///
    /// Idempotent: the store's own upserts key on the same identifiers the archive carries,
    /// so restoring twice writes the same rows twice rather than duplicating them.
    @discardableResult
    func restore(_ archive: ZenithiumArchive) async throws -> ArchiveCounts {
        try Self.validate(archive)
        try validateVaultCollisions(archive.documentFiles)
        await beforeRestore()
        do {
            let written = try await merge(archive)
            await afterRestore()
            return written
        } catch {
            await afterRestore()
            throw error
        }
    }

    private func merge(_ archive: ZenithiumArchive) async throws -> ArchiveCounts {
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
        try restoreVaultFiles(archive.documentFiles)
        for document in archive.documents {
            try await store.saveHealthDocument(document)
            written.documents += 1
        }

        for course in archive.supplementCourses ?? [] {
            try await store.saveSupplementCourse(course)
            written.supplementCourses += 1
        }

        if let restoredPreferences = archive.preferences { try await preferences?.save(restoredPreferences) }
        return written
    }

    // MARK: - Vault files

    private func readVaultFiles(for documents: [HealthDocument]) throws -> [ZenithiumArchive.ArchivedDocumentFile] {
        try documents.filter { !$0.fileName.isEmpty }.map { document in
            guard let url = DocumentVault.url(forFileName: document.fileName) else {
                throw ArchiveFailure.writeFailed(detail: "Belge yolu geçersiz; eksik arşiv oluşturulmadı.")
            }
            return ZenithiumArchive.ArchivedDocumentFile(fileName: document.fileName, contents: try Data(contentsOf: url))
        }
    }

    nonisolated static func validate(_ archive: ZenithiumArchive) throws {
        try ZenithiumArchive.validate(formatVersion: archive.formatVersion)
        _ = try archive.preferences?.validated()
        // Reject malformed values before any upsert. These are format bounds, not clinical
        // reference intervals; unusual measurements remain importable within numeric bounds.
        let encoded = try JSONEncoder().encode(archive)
        guard validNumbers(try JSONSerialization.jsonObject(with: encoded)),
              (5...12).contains(archive.profile.baselineSleepNeedHours),
              archive.days.allSatisfy({ day in
                  (day.recoveryScore.map { (0...100).contains($0) } ?? true) &&
                  (day.sleepScore.map { (0...100).contains($0) } ?? true) &&
                  (0...1).contains(day.recoveryConfidence) && (0...21).contains(day.dayStrain) &&
                  day.trimp >= 0 && day.sleepDurationSeconds >= 0
              }),
              archive.baselines.allSatisfy({ $0.sampleCount >= 0 && $0.variance >= 0 }),
              archive.bloodMarkers.allSatisfy({ $0.value >= 0 }) else {
            throw ArchiveFailure.unreadableArchive
        }
        let names = archive.documentFiles.map(\.fileName)
        let documentNames = archive.documents.map(\.fileName).filter { !$0.isEmpty }
        guard Set(names).count == names.count, (names + documentNames).allSatisfy(validFileName),
              Set(names).isSubset(of: Set(documentNames)) else {
            throw ArchiveFailure.unreadableArchive
        }
        if !archive.omittedDocumentFiles, !Set(documentNames).isSubset(of: Set(names)) {
            throw ArchiveFailure.writeFailed(detail: "Arşivdeki belgelerden birinin aslı eksik. İçe aktarma başlamadı.")
        }
    }

    private nonisolated static func validNumbers(_ value: Any) -> Bool {
        if let number = value as? NSNumber { return number.doubleValue.isFinite && abs(number.doubleValue) <= 1e12 }
        if let values = value as? [Any] { return values.allSatisfy(validNumbers) }
        if let values = value as? [String: Any] { return values.values.allSatisfy(validNumbers) }
        return true
    }

    private func validateVaultCollisions(_ files: [ZenithiumArchive.ArchivedDocumentFile]) throws {
        for file in files {
            guard let url = DocumentVault.url(forFileName: file.fileName) else { throw ArchiveFailure.unreadableArchive }
            if fileManager.fileExists(atPath: url.path), try Data(contentsOf: url) != file.contents {
                throw ArchiveFailure.writeFailed(detail: "Aynı kimlikle farklı bir belge zaten kayıtlı. İçe aktarma başlamadı.")
            }
        }
    }

    private nonisolated static func validFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 200 && name == (name as NSString).lastPathComponent &&
        !name.contains("..") && !name.contains("\\") && !name.contains("\0")
    }

    private func restoreVaultFiles(_ files: [ZenithiumArchive.ArchivedDocumentFile]) throws {
        guard !files.isEmpty else { return }
        guard let directory = DocumentVault.directoryURL else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        for file in files {
            let destination = directory.appending(path: file.fileName)
            if fileManager.fileExists(atPath: destination.path) {
                guard try Data(contentsOf: destination) == file.contents else {
                    throw ArchiveFailure.writeFailed(detail: "Aynı kimlikle farklı bir belge zaten kayıtlı. Var olan dosya korunuyor.")
                }
            } else { try file.contents.write(to: destination, options: [.atomic, .completeFileProtection]) }
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
