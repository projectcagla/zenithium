//
//  ZenithiumArchiveTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C9 — the archive is the only way years of data survive a new phone, so
//  the format gets tests that fail loudly rather than quietly.
//
//  Two kinds of test here, and they guard different things. The round trip proves the
//  encoder and decoder agree with each other. The fixture proves they agree with what was
//  written *last year*: it is a literal archive, typed out by hand, and it fails the moment
//  a stored property is renamed — which is exactly the failure mode of conforming the
//  snapshot types to `Codable` directly instead of mirroring them into DTOs.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Archive format")
struct ZenithiumArchiveTests {

    private let reference = Date(timeIntervalSince1970: 1_760_000_000)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Round trip

    @Test("Dolu bir arşiv kodlanıp çözüldüğünde aynı kalıyor")
    func fullArchiveRoundTrips() throws {
        let archive = sampleArchive()
        let data = try encoder.encode(archive)
        let decoded = try decoder.decode(ZenithiumArchive.self, from: data)
        #expect(decoded == archive)
    }

    @Test("Boş bir arşiv de kodlanıp çözülüyor")
    func emptyArchiveRoundTrips() throws {
        let archive = ZenithiumArchive(
            formatVersion: ZenithiumArchive.currentFormatVersion,
            exportedAt: reference,
            schemaVersion: "1.0.0",
            profile: .empty,
            baselines: [],
            days: [],
            muscleSnapshot: nil,
            strengthSessions: [],
            hybridSessions: [],
            bloodMarkers: [],
            journalDays: [],
            goalEvents: [],
            painEntries: [],
            documents: [],
            documentFiles: [],
            omittedDocumentFiles: false
        )
        let decoded = try decoder.decode(ZenithiumArchive.self, from: encoder.encode(archive))
        #expect(decoded == archive)
        #expect(decoded.counts.total == 0)
        #expect(decoded.counts.summary == "Kayıt yok")
    }

    @Test("Belge dosyaları base64 olarak taşınıyor")
    func documentFilesSurvive() throws {
        let contents = Data("bir PDF değil ama baytları taşınıyor".utf8)
        var archive = sampleArchive()
        archive.documentFiles = [
            ZenithiumArchive.ArchivedDocumentFile(fileName: "abc.pdf", contents: contents)
        ]
        let decoded = try decoder.decode(ZenithiumArchive.self, from: encoder.encode(archive))
        #expect(decoded.documentFiles.first?.contents == contents)
    }

    // MARK: - Wire format

    /// An archive as it is written today, typed out by hand.
    ///
    /// If this stops decoding, the format changed. That is allowed — but it means
    /// `formatVersion` has to go up and a reader for the old shape has to exist, because
    /// somebody's only copy of four years of data is in the old shape.
    private static let fixture = """
    {
      "baselines" : [
        {
          "mean" : 62.5,
          "metric" : "heartRateVariability",
          "sampleCount" : 41,
          "seedValues" : [],
          "variance" : 30.25
        }
      ],
      "days" : [],
      "documentFiles" : [],
      "documents" : [],
      "exportedAt" : "2025-10-09T09:33:20Z",
      "formatVersion" : 1,
      "goalEvents" : [],
      "hybridSessions" : [],
      "journalDays" : [
        {
          "behaviors" : ["alcohol"],
          "dayStart" : "2025-10-08T21:00:00Z",
          "note" : "iki kadeh"
        }
      ],
      "omittedDocumentFiles" : false,
      "painEntries" : [],
      "profile" : {
        "baselineSleepNeedHours" : 8,
        "biologicalSex" : "female",
        "dayBoundary" : "wakeAnchored",
        "hasCompletedOnboarding" : true,
        "tracksMenstrualCycle" : true,
        "trainingLens" : "endurance",
        "unitPreference" : "metric"
      },
      "schemaVersion" : "1.0.0",
      "strengthSessions" : [],
      "bloodMarkers" : []
    }
    """

    @Test("Elle yazılmış arşiv bugünkü okuyucuyla çözülüyor")
    func fixtureStillDecodes() throws {
        let data = Data(Self.fixture.utf8)
        let archive = try decoder.decode(ZenithiumArchive.self, from: data)

        #expect(archive.formatVersion == 1)
        #expect(archive.schemaVersion == "1.0.0")
        #expect(archive.profile.biologicalSex == .female)
        #expect(archive.profile.tracksMenstrualCycle)
        #expect(archive.profile.baselineSleepNeedHours == 8)
        // The fixture predates the appearance setting, so it must read as the default rather
        // than failing to decode. Yol haritası v4, B6.
        #expect(archive.profile.appearance == .dark)
        #expect(archive.baselines.first?.metric == .heartRateVariability)
        #expect(archive.baselines.first?.sampleCount == 41)
        #expect(archive.journalDays.first?.behaviors == [.alcohol])
        #expect(archive.journalDays.first?.note == "iki kadeh")
        #expect(archive.counts.journalDays == 1)
    }

    @Test("Takviye kürü olmayan eski bir arşiv hâlâ okunuyor")
    func anarchiveWithoutSupplementsStillDecodes() throws {
        // The fixture predates the field. Swift's synthesised decoder does not fall back to
        // a property's default when a key is missing, so this is the test that decides
        // whether the field may be non-optional. It may not.
        let archive = try decoder.decode(ZenithiumArchive.self, from: Data(Self.fixture.utf8))
        #expect(archive.supplementCourses == nil)
        #expect(archive.counts.supplementCourses == 0)
    }

    @Test("Takviye kürleri arşivde gidip geliyor")
    func supplementCoursesRoundTrip() throws {
        var archive = sampleArchive()
        archive.supplementCourses = [
            SupplementCourse(
                name: "Kreatin",
                startedAt: reference.addingTimeInterval(-120 * 86_400),
                endedAt: nil,
                note: "5 g"
            )
        ]
        let decoded = try decoder.decode(ZenithiumArchive.self, from: encoder.encode(archive))
        #expect(decoded.supplementCourses?.first?.name == "Kreatin")
        #expect(decoded.supplementCourses?.first?.isOngoing == true)
        #expect(decoded.counts.supplementCourses == 1)
    }

    @Test("Bilinmeyen bir sürüm reddediliyor, tahmin edilmiyor")
    func rejectsNewerFormat() {
        #expect(throws: ArchiveFailure.unsupportedFormatVersion(
            found: ZenithiumArchive.currentFormatVersion + 1,
            supported: ZenithiumArchive.currentFormatVersion
        )) {
            try ZenithiumArchive.validate(
                formatVersion: ZenithiumArchive.currentFormatVersion + 1
            )
        }
    }

    @Test("Bugünkü ve daha eski sürümler kabul ediliyor")
    func acceptsCurrentAndOlderFormats() {
        for version in 1...ZenithiumArchive.currentFormatVersion {
            #expect(throws: Never.self) {
                try ZenithiumArchive.validate(formatVersion: version)
            }
        }
        #expect(throws: ArchiveFailure.unsupportedFormatVersion(found: 0, supported: ZenithiumArchive.currentFormatVersion)) {
            try ZenithiumArchive.validate(formatVersion: 0)
        }
        #expect(throws: ArchiveFailure.unsupportedFormatVersion(found: -1, supported: ZenithiumArchive.currentFormatVersion)) {
            try ZenithiumArchive.validate(formatVersion: -1)
        }
    }

    @Test("Her hata bir sebep ve bir çıkış yolu söylüyor")
    func failuresExplainThemselves() {
        let failures: [ArchiveFailure] = [
            .unreadableArchive,
            .unsupportedFormatVersion(found: 9, supported: 1),
            .writeFailed(detail: "disk dolu")
        ]
        for failure in failures {
            #expect(failure.errorDescription?.isEmpty == false)
            #expect(failure.recoverySuggestion?.isEmpty == false)
        }
    }

    // MARK: - Counts

    @Test("Özet, içinde bir şey olan türleri sayıyor")
    func summaryNamesWhatIsThere() {
        let counts = ArchiveCounts(days: 412, bloodMarkers: 26, journalDays: 300)
        #expect(counts.total == 738)
        #expect(counts.summary.contains("412 gün kaydı"))
        #expect(counts.summary.contains("26 tahlil değeri"))
        #expect(!counts.summary.contains("kuvvet seansı"))
    }

    // MARK: - Sample

    private func sampleArchive() -> ZenithiumArchive {
        ZenithiumArchive(
            formatVersion: ZenithiumArchive.currentFormatVersion,
            exportedAt: reference,
            schemaVersion: "1.0.0",
            profile: UserProfileSnapshot(
                dateOfBirth: reference.addingTimeInterval(-30 * 365 * 86_400),
                biologicalSex: .female,
                maxHeartRateOverride: 188,
                baselineSleepNeedHours: 8,
                dayBoundary: .wakeAnchored,
                unitPreference: .metric,
                trainingLens: .hybrid,
                appearance: .dark,
                tracksMenstrualCycle: true,
                hasCompletedOnboarding: true,
                disclaimerAcknowledgedAt: reference
            ),
            baselines: [
                BaselineSnapshot(
                    metric: .heartRateVariability,
                    mean: 62.5,
                    variance: 30.25,
                    sampleCount: 41,
                    lastUpdated: reference,
                    seedValues: []
                )
            ],
            days: [sampleDay()],
            muscleSnapshot: MuscleFatigueSnapshotRecord(
                computedAt: reference,
                fatigueValues: Array(repeating: 12.5, count: MuscleGroup.allCases.count),
                halfLifeHours: Array(repeating: 36, count: MuscleGroup.allCases.count),
                sleepScoreUsed: 78,
                engineVersion: 1
            ),
            strengthSessions: [],
            hybridSessions: [],
            bloodMarkers: [
                BloodMarkerSnapshot(
                    id: UUID(uuidString: "1F5B2E0A-0000-4000-8000-000000000001") ?? UUID(),
                    marker: .ferritin,
                    value: 44,
                    unitSymbol: "ng/mL",
                    referenceRange: MarkerRange(minimum: 15, maximum: 150),
                    optimalRange: MarkerRange(minimum: 40, maximum: 100),
                    drawnAt: reference,
                    note: ""
                )
            ],
            journalDays: [
                JournalDay(dayStart: reference, behaviors: [.alcohol], mood: .good, note: "iki kadeh")
            ],
            goalEvents: [
                ZenithiumArchive.ArchivedGoalEvent(
                    event: GoalEvent(
                        id: UUID(uuidString: "1F5B2E0A-0000-4000-8000-000000000002") ?? UUID(),
                        kind: .race,
                        name: "İstanbul Maratonu",
                        date: reference.addingTimeInterval(60 * 86_400)
                    ),
                    planStart: reference
                )
            ],
            painEntries: [
                PainEntry(
                    id: UUID(uuidString: "1F5B2E0A-0000-4000-8000-000000000003") ?? UUID(),
                    muscle: .calves,
                    laterality: .left,
                    severity: 4,
                    quality: .ache,
                    loggedAt: reference,
                    note: ""
                )
            ],
            documents: [],
            documentFiles: [],
            omittedDocumentFiles: false
        )
    }

    private func sampleDay() -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: reference,
            timeZoneIdentifier: "Europe/Istanbul",
            heartRateVariability: 62,
            restingHeartRate: 48,
            wristTemperatureDelta: -0.2,
            respiratoryRate: 14.1,
            oxygenSaturation: 97,
            recoveryScore: 71,
            recoveryConfidence: 1,
            recoveryZTotal: 0.4,
            dayStrain: 11.2,
            targetCeiling: 14,
            trimp: 96,
            zoneSeconds: [600, 1_200, 900, 300, 0],
            maxHeartRateUsed: 188,
            sleepDurationSeconds: 27_000,
            sleepScore: 78,
            sleepEfficiency: 0.91,
            deepSeconds: 4_200,
            remSeconds: 5_400,
            coreSeconds: 16_200,
            awakeSeconds: 1_200,
            timeInBedSeconds: 29_700,
            sleepMidpointMinutes: 205,
            sleepStart: reference.addingTimeInterval(-8 * 3_600),
            wakeTime: reference,
            napSeconds: 0,
            dataQuality: .good,
            dataQualityReasons: [],
            computedAt: reference,
            engineVersion: 1
        )
    }
}
