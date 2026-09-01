//
//  Repositories.swift
//  Zenithium
//
//  Narrow protocols over the store. Spec §2.5 — dependency injection through protocols.
//
//  Each protocol is the smallest surface its consumer actually needs, so a view model that
//  reads blood markers cannot accidentally write a baseline, and a test can supply a stub
//  covering four methods instead of forty.
//

import Foundation

/// Reads and writes the single user profile.
protocol ProfileRepository: Sendable {
    func profile() async throws -> UserProfileSnapshot
    @discardableResult
    func updateProfile(_ write: UserProfileWrite) async throws -> UserProfileSnapshot
}

/// Reads and writes EWMA baselines (§4).
protocol BaselineRepository: Sendable {
    func baselines() async throws -> [MetricKind: BaselineSnapshot]
    func saveBaselines(_ snapshots: [MetricKind: BaselineSnapshot]) async throws
    func resetBaselines() async throws
}

/// Reads and writes daily records (§7).
protocol BiometricDayRepository: Sendable {
    func dayRecord(for dayStart: Date) async throws -> BiometricDaySnapshot?
    func dayRecords(from start: Date, through end: Date) async throws -> [BiometricDaySnapshot]
    func recentDayRecords(limit: Int) async throws -> [BiometricDaySnapshot]
    func strainAnchor(for dayStart: Date) async throws -> StrainAnchor?
    @discardableResult
    func upsertDayRecord(_ write: DayRecordWrite) async throws -> BiometricDaySnapshot
    func dayRecordsNeedingBackfill(currentEngineVersion: Int) async throws -> [Date]
}

/// Reads and writes supplement courses (Yol haritası v4, C5).
protocol SupplementRepository: Sendable {
    func supplementCourses() async throws -> [SupplementCourse]
    @discardableResult
    func saveSupplementCourse(_ course: SupplementCourse) async throws -> SupplementCourse
    func deleteSupplementCourse(id: UUID) async throws
}

/// Reads and writes logged strength sessions (§5.4).
protocol StrengthSessionRepository: Sendable {
    func strengthSessions(from start: Date, through end: Date) async throws -> [StrengthSessionSnapshot]
    @discardableResult
    func saveStrengthSession(
        id: UUID,
        performedAt: Date,
        timeZoneIdentifier: String,
        pattern: MovementPattern,
        entries: [StrengthEntry],
        sessionLoad: Double,
        note: String
    ) async throws -> StrengthSessionSnapshot
    func deleteStrengthSession(id: UUID) async throws
}

/// Reads and writes goal events (Faz 20).
protocol GoalEventRepository: Sendable {
    func goalEvents() async throws -> [GoalEvent]
    /// The next event on or after a day, which is the only one a prescription cares about.
    func nextGoalEvent(onOrAfter day: Date) async throws -> (event: GoalEvent, planStart: Date?)?
    @discardableResult
    func saveGoalEvent(_ event: GoalEvent, planStart: Date?) async throws -> GoalEvent
    func deleteGoalEvent(id: UUID) async throws
}

/// Reads and writes stored health documents (Faz 26).
protocol HealthDocumentRepository: Sendable {
    func healthDocuments() async throws -> [HealthDocument]
    @discardableResult
    func saveHealthDocument(_ document: HealthDocument) async throws -> HealthDocument
    func deleteHealthDocument(id: UUID) async throws
}

/// Reads and writes pain entries (Faz 32).
protocol PainEntryRepository: Sendable {
    func painEntries(from start: Date, through end: Date) async throws -> [PainEntry]
    @discardableResult
    func savePainEntry(_ entry: PainEntry) async throws -> PainEntry
    func deletePainEntry(id: UUID) async throws
}

/// Reads and writes blood markers (§7, §12 — storage and trends only).
protocol BloodMarkerRepository: Sendable {
    func bloodMarkers() async throws -> [BloodMarkerSnapshot]
    @discardableResult
    func saveBloodMarker(
        id: UUID,
        marker: BloodMarkerKind,
        value: Double,
        unitSymbol: String,
        referenceRange: MarkerRange,
        optimalRange: MarkerRange,
        drawnAt: Date,
        note: String
    ) async throws -> BloodMarkerSnapshot
    func deleteBloodMarker(id: UUID) async throws
}

/// Hibrit seansları okur ve yazar.
protocol HybridSessionRepository: Sendable {
    func hybridSessions(from start: Date, through end: Date) async throws -> [HybridSessionSnapshot]
    func recentHybridSessions(limit: Int) async throws -> [HybridSessionSnapshot]
    @discardableResult
    func saveHybridSession(_ session: HybridSessionSnapshot) async throws -> HybridSessionSnapshot
    func deleteHybridSession(id: UUID) async throws
}

/// Günlük kayıtlarını okur ve yazar.
protocol JournalRepository: Sendable {
    func journalDay(for dayStart: Date) async throws -> JournalDay?
    func journalDays(from start: Date, through end: Date) async throws -> [JournalDay]
    @discardableResult
    func saveJournalDay(_ day: JournalDay) async throws -> JournalDay
}

/// Reads and writes the cached muscle projection (ASSUMPTION MUSCLE-3).
protocol MuscleSnapshotRepository: Sendable {
    func saveMuscleSnapshot(_ record: MuscleFatigueSnapshotRecord) async throws
    func latestMuscleSnapshot() async throws -> MuscleFatigueSnapshotRecord?
}

/// The union, for the composition root and the coordinator.
typealias ZenithiumRepository = ProfileRepository
    & BaselineRepository
    & BiometricDayRepository
    & StrengthSessionRepository
    & BloodMarkerRepository
    & MuscleSnapshotRepository
    & JournalRepository
    & HybridSessionRepository

// The store's methods are actor-isolated and therefore `async` at every call site, which is
// exactly the shape these protocols declare.
extension ZenithiumStore: ProfileRepository {}
extension ZenithiumStore: BaselineRepository {}
extension ZenithiumStore: BiometricDayRepository {}
extension ZenithiumStore: StrengthSessionRepository {}
extension ZenithiumStore: BloodMarkerRepository {}
extension ZenithiumStore: MuscleSnapshotRepository {}
extension ZenithiumStore: JournalRepository {}
extension ZenithiumStore: HybridSessionRepository {}
extension ZenithiumStore: GoalEventRepository {}
extension ZenithiumStore: PainEntryRepository {}
extension ZenithiumStore: SupplementRepository {}
extension ZenithiumStore: HealthDocumentRepository {}
