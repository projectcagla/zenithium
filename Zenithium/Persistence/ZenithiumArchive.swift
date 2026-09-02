//
//  ZenithiumArchive.swift
//  Zenithium
//
//  The whole store, as one portable value. Yol haritası v4, C9.
//
//  ## Why this exists
//
//  Zenithium has no account and no server, which is the point — nothing about a person's
//  health leaves their device unless they send it. The cost of that choice is that a new
//  phone is a new install with nothing in it, and years of baselines, journal entries,
//  laboratory values and pain history simply end. That is not a missing feature; it is a
//  standing risk that grows with every day the app is used.
//
//  So: a versioned archive the person writes themselves, reads themselves, and keeps
//  wherever they keep their own files.
//
//  ## The format
//
//  One `.zenithium` file: JSON, with the vault's original PDFs carried inside it as base64.
//
//  A zipped folder would be smaller, but Foundation can only write zips, not read them, and
//  an export that cannot be imported without a third-party archiver is not a transfer — it is
//  a backup nobody can restore. One self-describing file that both halves of the feature can
//  handle is worth the roughly thirty per cent that base64 costs. Vaults past
//  `maximumEmbeddedBytes` export their metadata and text without the files, and say so, rather
//  than producing something too large to move.
//
//  `formatVersion` is the archive's own version and is independent of `SchemaV1`: the store's
//  schema may change without the wire format changing, and vice versa. A reader refuses a
//  version it does not know rather than guessing, because a half-understood health record is
//  worse than none.
//
//  ## What it deliberately does not contain
//
//  No identifiers beyond the ones already in the store, no device information, no timestamps
//  other than the ones the records carry. An archive read by someone else discloses exactly
//  what the app itself holds, and nothing about the phone it came from.
//

import Foundation

/// Everything in the store, in one value.
struct ZenithiumArchive: Codable, Sendable, Equatable {

    /// The archive format's version. Bumped when the wire shape changes, never for a
    /// schema change that leaves the shape intact.
    static let currentFormatVersion = 1

    let formatVersion: Int

    /// When the archive was written. Informational — nothing keys off it.
    let exportedAt: Date

    /// The store schema the archive came from, so a future reader can tell what the values
    /// meant even if the format version did not need to change.
    let schemaVersion: String

    var profile: UserProfileSnapshot
    var baselines: [BaselineSnapshot]
    var days: [BiometricDaySnapshot]
    var muscleSnapshot: MuscleFatigueSnapshotRecord?
    var strengthSessions: [StrengthSessionSnapshot]
    var hybridSessions: [HybridSessionSnapshot]
    var bloodMarkers: [BloodMarkerSnapshot]
    var journalDays: [JournalDay]
    var goalEvents: [ArchivedGoalEvent]
    var painEntries: [PainEntry]
    var documents: [HealthDocument]

    /// Supplement courses. Yol haritası v4, C5.
    ///
    /// Optional rather than defaulted to empty, because Swift's synthesised decoder does not
    /// fall back to a property's default value when the key is absent — it fails. An archive
    /// written before this field existed has no `supplementCourses` key, and making the
    /// property optional is what lets it still be read. The fixture test in
    /// `ZenithiumArchiveTests` is exactly the thing that would have caught the other choice.
    var supplementCourses: [SupplementCourse]?

    /// The vault's files, by name. Empty when the vault was too large to embed.
    var documentFiles: [ArchivedDocumentFile]

    /// Whether `documentFiles` was left empty because the vault exceeded the size limit.
    var omittedDocumentFiles: Bool

    /// One file from the document vault, carried whole.
    struct ArchivedDocumentFile: Codable, Sendable, Equatable {

        /// The name the vault knows it by. Matches `HealthDocument.fileName`.
        let fileName: String

        /// The file itself. `JSONEncoder` writes `Data` as base64.
        let contents: Data
    }

    /// A goal and the plan start that was stored beside it.
    ///
    /// The store keeps those two together but hands them back separately, so the archive
    /// pairs them explicitly rather than relying on ordering.
    struct ArchivedGoalEvent: Codable, Sendable, Equatable {
        let event: GoalEvent
        let planStart: Date?
    }

    /// Refuse an archive this build does not understand.
    ///
    /// A newer archive is rejected rather than read leniently. Silently dropping the fields
    /// a future version added would produce a plausible-looking store missing a year of
    /// something, and the person would have no way to notice.
    static func validate(formatVersion: Int) throws {
        guard formatVersion >= 1, formatVersion <= currentFormatVersion else {
            throw ArchiveFailure.unsupportedFormatVersion(
                found: formatVersion,
                supported: currentFormatVersion
            )
        }
    }

    /// How many records of each kind the archive holds. Shown before a restore, so the
    /// person confirms against something concrete rather than against the word "everything".
    var counts: ArchiveCounts {
        ArchiveCounts(
            days: days.count,
            strengthSessions: strengthSessions.count,
            hybridSessions: hybridSessions.count,
            bloodMarkers: bloodMarkers.count,
            journalDays: journalDays.count,
            goalEvents: goalEvents.count,
            painEntries: painEntries.count,
            documents: documents.count,
            supplementCourses: supplementCourses?.count ?? 0
        )
    }
}

/// What an archive holds, or what a restore wrote.
struct ArchiveCounts: Codable, Sendable, Equatable {

    var days = 0
    var strengthSessions = 0
    var hybridSessions = 0
    var bloodMarkers = 0
    var journalDays = 0
    var goalEvents = 0
    var painEntries = 0
    var documents = 0
    var supplementCourses = 0

    /// Everything, for the one-line summary.
    var total: Int {
        days + strengthSessions + hybridSessions + bloodMarkers
            + journalDays + goalEvents + painEntries + documents + supplementCourses
    }

    /// A sentence naming the largest few kinds, for a confirmation prompt.
    var summary: String {
        let parts: [(Int, String)] = [
            (days, "gün kaydı"),
            (journalDays, "günlük girdisi"),
            (bloodMarkers, "tahlil değeri"),
            (strengthSessions, "kuvvet seansı"),
            (hybridSessions, "hibrit seans"),
            (painEntries, "ağrı kaydı"),
            (documents, "belge"),
            (supplementCourses, "takviye kürü"),
            (goalEvents, "hedef")
        ]
        let named = parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        guard !named.isEmpty else { return "Kayıt yok" }
        return named.joined(separator: ", ")
    }
}

/// What went wrong reading or writing an archive.
enum ArchiveFailure: Error, Sendable, Equatable {

    /// The file is not a Zenithium archive, or its manifest is unreadable.
    case unreadableArchive

    /// The archive was written by a newer version of the app.
    case unsupportedFormatVersion(found: Int, supported: Int)

    /// The archive could not be written to disk.
    case writeFailed(detail: String)
}

extension ArchiveFailure: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            return "Bu dosya bir Zenithium arşivi değil"
        case .unsupportedFormatVersion(let found, let supported):
            return "Arşiv sürümü \(found), bu uygulama \(supported) okuyor"
        case .writeFailed:
            return "Arşiv yazılamadı"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadableArchive:
            return "Zenithium'dan dışa aktardığın .zenithium dosyasını seç."
        case .unsupportedFormatVersion:
            return "Uygulamayı güncelledikten sonra yeniden dene."
        case .writeFailed:
            return "Cihazda yer açıp yeniden dene."
        }
    }
}

// MARK: - Codable conformances
//
// The snapshot types are the archive's wire format. Conforming them directly rather than
// mirroring each one into a parallel DTO keeps a single definition of what a day record is —
// at the cost that renaming a stored property would silently change the format. That is what
// `formatVersion` and the fixture test in `ZenithiumArchiveTests` are for: the fixture is a
// literal archive written by hand, and it fails the moment a key moves.
//

// MARK: - Snapshots as writes
//
// The store writes through `…Write` types whose optional fields mean "leave alone". An
// archive is the opposite case — every field is known and every field should land — so these
// fill in all of them explicitly rather than leaving a gap the store would preserve.

extension BiometricDaySnapshot {

    /// This day, as a write that sets every field it carries.
    var asWrite: DayRecordWrite {
        var write = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: timeZoneIdentifier,
            computedAt: computedAt,
            engineVersion: engineVersion
        )
        write.heartRateVariability = heartRateVariability
        write.restingHeartRate = restingHeartRate
        write.wristTemperatureDelta = wristTemperatureDelta
        write.respiratoryRate = respiratoryRate
        write.oxygenSaturation = oxygenSaturation

        write.recoveryScore = recoveryScore
        write.recoveryConfidence = recoveryConfidence
        write.recoveryZTotal = recoveryZTotal

        write.dayStrain = dayStrain
        write.targetCeiling = targetCeiling
        write.trimp = trimp
        write.zoneSeconds = zoneSeconds
        write.maxHeartRateUsed = maxHeartRateUsed

        write.sleepDurationSeconds = sleepDurationSeconds
        write.sleepScore = sleepScore
        write.sleepEfficiency = sleepEfficiency
        write.deepSeconds = deepSeconds
        write.remSeconds = remSeconds
        write.coreSeconds = coreSeconds
        write.awakeSeconds = awakeSeconds
        write.timeInBedSeconds = timeInBedSeconds
        write.sleepMidpointMinutes = sleepMidpointMinutes
        write.sleepStart = sleepStart
        write.wakeTime = wakeTime
        write.napSeconds = napSeconds

        write.dataQuality = dataQuality
        write.dataQualityReasons = dataQualityReasons
        return write
    }
}

extension UserProfileSnapshot {

    /// This profile, as a write that sets every field.
    var asWrite: UserProfileWrite {
        var write = UserProfileWrite()
        write.dateOfBirth = .some(dateOfBirth)
        write.biologicalSex = biologicalSex
        write.maxHeartRateOverride = .some(maxHeartRateOverride)
        write.baselineSleepNeedHours = baselineSleepNeedHours
        write.dayBoundary = dayBoundary
        write.unitPreference = unitPreference
        write.trainingLens = trainingLens
        write.appearance = appearance
        write.tracksMenstrualCycle = tracksMenstrualCycle
        write.hasCompletedOnboarding = hasCompletedOnboarding
        write.disclaimerAcknowledgedAt = .some(disclaimerAcknowledgedAt)
        return write
    }
}
