//
//  ZenithiumStore.swift
//  Zenithium
//
//  The `@ModelActor` store. Spec §6 (`@ModelActor` for background SwiftData writes), §7.
//
//  ASSUMPTION STORE-1: every method here returns `Sendable` snapshots and takes `Sendable`
//  writes. No `PersistentModel` crosses the boundary, which is what makes the store safe to
//  call from the coordinator, the view models and a background task at the same time.
//

import Foundation
import SwiftData

@ModelActor
actor ZenithiumStore {

    // MARK: - Profile

    /// The single profile, created on first read so callers never handle "no profile yet".
    func profile() throws -> UserProfileSnapshot {
        let model = try profileModel()
        return snapshot(of: model)
    }

    @discardableResult
    func updateProfile(_ write: UserProfileWrite) throws -> UserProfileSnapshot {
        let model = try profileModel()
        if let dateOfBirth = write.dateOfBirth { model.dateOfBirth = dateOfBirth }
        if let sex = write.biologicalSex { model.biologicalSex = sex }
        if let override = write.maxHeartRateOverride { model.maxHeartRateOverride = override }
        if let need = write.baselineSleepNeedHours {
            model.baselineSleepNeedHours = min(
                max(need, UserProfile.sleepNeedRange.lowerBound),
                UserProfile.sleepNeedRange.upperBound
            )
        }
        if let boundary = write.dayBoundary { model.dayBoundary = boundary }
        if let units = write.unitPreference { model.unitPreference = units }
        if let lens = write.trainingLens { model.trainingLens = lens }
        if let appearance = write.appearance { model.appearance = appearance }
        if let tracksCycle = write.tracksMenstrualCycle { model.tracksMenstrualCycle = tracksCycle }
        if let onboarded = write.hasCompletedOnboarding { model.hasCompletedOnboarding = onboarded }
        if let acknowledged = write.disclaimerAcknowledgedAt {
            model.disclaimerAcknowledgedAt = acknowledged
        }
        model.updatedAt = Date()
        try save()
        return snapshot(of: model)
    }

    private func profileModel() throws -> UserProfile {
        let identifier = UserProfile.primaryIdentifier
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                return existing
            }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
        let now = Date()
        let created = UserProfile(createdAt: now, updatedAt: now)
        modelContext.insert(created)
        try save()
        return created
    }

    private func snapshot(of model: UserProfile) -> UserProfileSnapshot {
        UserProfileSnapshot(
            dateOfBirth: model.dateOfBirth,
            biologicalSex: model.biologicalSex,
            maxHeartRateOverride: model.maxHeartRateOverride,
            baselineSleepNeedHours: model.baselineSleepNeedHours,
            dayBoundary: model.dayBoundary,
            unitPreference: model.unitPreference,
            trainingLens: model.trainingLens,
            appearance: model.appearance,
            tracksMenstrualCycle: model.tracksMenstrualCycle,
            hasCompletedOnboarding: model.hasCompletedOnboarding,
            disclaimerAcknowledgedAt: model.disclaimerAcknowledgedAt
        )
    }

    // MARK: - Baselines

    /// Every persisted baseline, keyed by metric. Metrics with no row are absent.
    func baselines() throws -> [MetricKind: BaselineSnapshot] {
        do {
            let models = try modelContext.fetch(FetchDescriptor<BaselineState>())
            var result: [MetricKind: BaselineSnapshot] = [:]
            for model in models {
                guard let snapshot = model.snapshot else { continue }
                result[snapshot.metric] = snapshot
            }
            return result
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Upserts a metric's baseline.
    func saveBaseline(_ snapshot: BaselineSnapshot) throws {
        let raw = snapshot.metric.rawValue
        var descriptor = FetchDescriptor<BaselineState>(
            predicate: #Predicate { $0.metricRawValue == raw }
        )
        descriptor.fetchLimit = 1
        do {
            let now = Date()
            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(snapshot, engineVersion: EngineConstants.engineVersion, updatedAt: now)
            } else {
                modelContext.insert(
                    BaselineState(
                        metric: snapshot.metric,
                        mean: snapshot.mean,
                        variance: snapshot.variance,
                        sampleCount: snapshot.sampleCount,
                        lastUpdated: snapshot.lastUpdated,
                        seedValues: snapshot.seedValues,
                        engineVersion: EngineConstants.engineVersion,
                        updatedAt: now
                    )
                )
            }
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func saveBaselines(_ snapshots: [MetricKind: BaselineSnapshot]) throws {
        for snapshot in snapshots.values {
            try saveBaseline(snapshot)
        }
    }

    /// Clears every baseline, for an engine-version rebuild (§7).
    func resetBaselines() throws {
        do {
            let models = try modelContext.fetch(FetchDescriptor<BaselineState>())
            for model in models { modelContext.delete(model) }
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Day records

    func dayRecord(for dayStart: Date) throws -> BiometricDaySnapshot? {
        var descriptor = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first.map { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Day records in a closed date range, oldest first.
    func dayRecords(from start: Date, through end: Date) throws -> [BiometricDaySnapshot] {
        let descriptor = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart <= end },
            sortBy: [SortDescriptor(\.dayStart, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// The most recent `limit` records, newest first.
    func recentDayRecords(limit: Int) throws -> [BiometricDaySnapshot] {
        var descriptor = FetchDescriptor<BiometricDayRecord>(
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 0)
        do {
            return try modelContext.fetch(descriptor).map { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Upserts a day. Fields left `nil` on the write keep whatever is already stored, so a
    /// strain-only refresh cannot clobber the morning's recovery score.
    @discardableResult
    func upsertDayRecord(_ write: DayRecordWrite) throws -> BiometricDaySnapshot {
        let dayStart = write.dayStart
        var descriptor = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1

        do {
            let model: BiometricDayRecord
            if let existing = try modelContext.fetch(descriptor).first {
                model = existing
            } else {
                model = BiometricDayRecord(
                    dayStart: write.dayStart,
                    timeZoneIdentifier: write.timeZoneIdentifier,
                    computedAt: write.computedAt,
                    engineVersion: write.engineVersion
                )
                modelContext.insert(model)
            }
            apply(write, to: model)
            try save()
            return snapshot(of: model)
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    private func apply(_ write: DayRecordWrite, to model: BiometricDayRecord) {
        model.timeZoneIdentifier = write.timeZoneIdentifier
        model.computedAt = write.computedAt
        model.engineVersion = write.engineVersion

        // §5.6 — when HealthKit reports the night's samples were deleted, the stored values
        // must go with them rather than lingering behind a score for data that is gone.
        if write.clearsOvernightValues {
            model.hrvSDNN = nil
            model.restingHR = nil
            model.wristTempDelta = nil
            model.respiratoryRate = nil
            model.oxygenSaturation = nil
            model.recoveryScore = nil
            model.recoveryZTotal = nil
            model.recoveryConfidence = 0
            model.sleepScore = nil
            model.sleepEfficiency = nil
            model.sleepDurationSeconds = 0
            model.deepSeconds = 0
            model.remSeconds = 0
            model.coreSeconds = 0
            model.awakeSeconds = 0
            model.timeInBedSeconds = 0
            model.sleepMidpointMinutes = nil
            model.sleepStart = nil
            model.wakeTime = nil
        }

        if let value = write.heartRateVariability { model.hrvSDNN = value }
        if let value = write.restingHeartRate { model.restingHR = value }
        if let value = write.wristTemperatureDelta { model.wristTempDelta = value }
        if let value = write.respiratoryRate { model.respiratoryRate = value }
        if let value = write.oxygenSaturation { model.oxygenSaturation = value }

        if let value = write.recoveryScore { model.recoveryScore = value }
        if let value = write.recoveryConfidence { model.recoveryConfidence = value }
        if let value = write.recoveryZTotal { model.recoveryZTotal = value }

        if let value = write.dayStrain { model.dayStrain = value }
        if let value = write.targetCeiling { model.targetCeiling = value }
        if let value = write.trimp { model.trimp = value }
        if let value = write.strainAnchorTRIMP { model.strainAnchorTRIMP = value }
        if let value = write.strainAnchorThrough { model.strainAnchorThrough = value }
        if let value = write.zoneSeconds { model.setZoneSeconds(value) }
        if let value = write.maxHeartRateUsed { model.maxHeartRateUsed = value }

        if let value = write.sleepDurationSeconds { model.sleepDurationSeconds = value }
        if let value = write.sleepScore { model.sleepScore = value }
        if let value = write.sleepEfficiency { model.sleepEfficiency = value }
        if let value = write.deepSeconds { model.deepSeconds = value }
        if let value = write.remSeconds { model.remSeconds = value }
        if let value = write.coreSeconds { model.coreSeconds = value }
        if let value = write.awakeSeconds { model.awakeSeconds = value }
        if let value = write.timeInBedSeconds { model.timeInBedSeconds = value }
        if let value = write.sleepMidpointMinutes { model.sleepMidpointMinutes = value }
        if let value = write.sleepStart { model.sleepStart = value }
        if let value = write.wakeTime { model.wakeTime = value }
        if let value = write.napSeconds { model.napSeconds = value }

        if let value = write.dataQuality { model.dataQuality = value }
        if let value = write.dataQualityReasons { model.dataQualityReasons = value }
    }

    private func snapshot(of model: BiometricDayRecord) -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: model.dayStart,
            timeZoneIdentifier: model.timeZoneIdentifier,
            heartRateVariability: model.hrvSDNN,
            restingHeartRate: model.restingHR,
            wristTemperatureDelta: model.wristTempDelta,
            respiratoryRate: model.respiratoryRate,
            oxygenSaturation: model.oxygenSaturation,
            recoveryScore: model.recoveryScore,
            recoveryConfidence: model.recoveryConfidence,
            recoveryZTotal: model.recoveryZTotal,
            dayStrain: model.dayStrain,
            targetCeiling: model.targetCeiling,
            trimp: model.trimp,
            zoneSeconds: model.zoneSecondsRaw.map { Double($0) },
            maxHeartRateUsed: model.maxHeartRateUsed,
            sleepDurationSeconds: model.sleepDurationSeconds,
            sleepScore: model.sleepScore,
            sleepEfficiency: model.sleepEfficiency,
            deepSeconds: model.deepSeconds,
            remSeconds: model.remSeconds,
            coreSeconds: model.coreSeconds,
            awakeSeconds: model.awakeSeconds,
            timeInBedSeconds: model.timeInBedSeconds,
            sleepMidpointMinutes: model.sleepMidpointMinutes,
            sleepStart: model.sleepStart,
            wakeTime: model.wakeTime,
            napSeconds: model.napSeconds,
            dataQuality: model.dataQuality,
            dataQualityReasons: model.dataQualityReasons,
            computedAt: model.computedAt,
            engineVersion: model.engineVersion
        )
    }

    /// The strain anchor stored for a day, for the incremental monotonic recompute
    /// (ASSUMPTION STRAIN-1).
    func strainAnchor(for dayStart: Date) throws -> StrainAnchor? {
        var descriptor = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first?.strainAnchor
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Days computed by an older engine, oldest first (§7 backfill).
    func dayRecordsNeedingBackfill(currentEngineVersion: Int) throws -> [Date] {
        let descriptor = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.engineVersion < currentEngineVersion },
            sortBy: [SortDescriptor(\.dayStart, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(\.dayStart)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Strength sessions

    func strengthSessions(from start: Date, through end: Date) throws -> [StrengthSessionSnapshot] {
        let descriptor = FetchDescriptor<StrengthSessionLog>(
            predicate: #Predicate { $0.performedAt >= start && $0.performedAt <= end },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).compactMap { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func saveStrengthSession(
        id: UUID,
        performedAt: Date,
        timeZoneIdentifier: String,
        pattern: MovementPattern,
        entries: [StrengthEntry],
        sessionLoad: Double,
        note: String
    ) throws -> StrengthSessionSnapshot {
        // The load arrives already computed. Persistence stores what the engines decide; it
        // does not call them (§6 — no arrow from Persistence to Engines).
        let load = sessionLoad
        var descriptor = FetchDescriptor<StrengthSessionLog>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            let model: StrengthSessionLog
            if let existing = try modelContext.fetch(descriptor).first {
                model = existing
                model.performedAt = performedAt
                model.timeZoneIdentifier = timeZoneIdentifier
                model.patternStorageKey = pattern.storageKey
                model.entries = entries
                model.sessionLoad = load
                model.note = note
                model.engineVersion = EngineConstants.engineVersion
            } else {
                model = StrengthSessionLog(
                    id: id,
                    performedAt: performedAt,
                    timeZoneIdentifier: timeZoneIdentifier,
                    pattern: pattern,
                    entries: entries,
                    sessionLoad: load,
                    note: note,
                    engineVersion: EngineConstants.engineVersion,
                    createdAt: Date()
                )
                modelContext.insert(model)
            }
            try save()
            guard let snapshot = snapshot(of: model) else {
                throw ZenithiumError.persistenceWriteFailed(detail: "Unrecognised movement pattern.")
            }
            return snapshot
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteStrengthSession(id: UUID) throws {
        var descriptor = FetchDescriptor<StrengthSessionLog>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    private func snapshot(of model: StrengthSessionLog) -> StrengthSessionSnapshot? {
        guard let pattern = model.pattern else { return nil }
        return StrengthSessionSnapshot(
            id: model.id,
            performedAt: model.performedAt,
            timeZoneIdentifier: model.timeZoneIdentifier,
            pattern: pattern,
            entries: model.entries,
            sessionLoad: model.sessionLoad,
            note: model.note,
            engineVersion: model.engineVersion
        )
    }

    // MARK: - Blood markers

    func bloodMarkers() throws -> [BloodMarkerSnapshot] {
        let descriptor = FetchDescriptor<BloodMarker>(
            sortBy: [SortDescriptor(\.drawnAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).compactMap { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

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
    ) throws -> BloodMarkerSnapshot {
        var descriptor = FetchDescriptor<BloodMarker>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            let model: BloodMarker
            if let existing = try modelContext.fetch(descriptor).first {
                model = existing
                model.markerStorageKey = marker.storageKey
                model.value = value
                model.unitSymbol = unitSymbol
                model.refMin = referenceRange.minimum
                model.refMax = referenceRange.maximum
                model.optimalMin = optimalRange.minimum
                model.optimalMax = optimalRange.maximum
                model.drawnAt = drawnAt
                model.note = note
            } else {
                model = BloodMarker(
                    id: id,
                    marker: marker,
                    value: value,
                    unitSymbol: unitSymbol,
                    refMin: referenceRange.minimum,
                    refMax: referenceRange.maximum,
                    optimalMin: optimalRange.minimum,
                    optimalMax: optimalRange.maximum,
                    drawnAt: drawnAt,
                    note: note,
                    createdAt: Date()
                )
                modelContext.insert(model)
            }
            try save()
            guard let snapshot = snapshot(of: model) else {
                throw ZenithiumError.persistenceWriteFailed(detail: "Unrecognised marker.")
            }
            return snapshot
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteBloodMarker(id: UUID) throws {
        var descriptor = FetchDescriptor<BloodMarker>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    private func snapshot(of model: BloodMarker) -> BloodMarkerSnapshot? {
        guard let marker = model.marker else { return nil }
        return BloodMarkerSnapshot(
            id: model.id,
            marker: marker,
            value: model.value,
            unitSymbol: model.unitSymbol,
            referenceRange: model.effectiveReferenceRange,
            optimalRange: model.effectiveOptimalRange,
            drawnAt: model.drawnAt,
            note: model.note
        )
    }

    // MARK: - Hybrid sessions

    func hybridSessions(from start: Date, through end: Date) throws -> [HybridSessionSnapshot] {
        let descriptor = FetchDescriptor<HybridSessionLog>(
            predicate: #Predicate { $0.performedAt >= start && $0.performedAt <= end },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).compactMap { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    func recentHybridSessions(limit: Int) throws -> [HybridSessionSnapshot] {
        var descriptor = FetchDescriptor<HybridSessionLog>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 0)
        do {
            return try modelContext.fetch(descriptor).compactMap { snapshot(of: $0) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func saveHybridSession(_ session: HybridSessionSnapshot) throws -> HybridSessionSnapshot {
        let id = session.id
        var descriptor = FetchDescriptor<HybridSessionLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            let model: HybridSessionLog
            if let existing = try modelContext.fetch(descriptor).first {
                model = existing
                model.performedAt = session.performedAt
                model.timeZoneIdentifier = session.timeZoneIdentifier
                model.kindRawValue = session.kind.rawValue
                model.segments = session.segments
                model.freshPaceSecondsPerKilometre = session.freshPaceSecondsPerKilometre
                model.totalDurationSeconds = session.totalDurationSeconds
                model.roxzoneSeconds = session.roxzoneSeconds
                model.compromisedPenalty = session.compromisedPenalty
                model.sessionLoad = session.sessionLoad
                model.note = session.note
                model.engineVersion = EngineConstants.engineVersion
            } else {
                model = HybridSessionLog(
                    id: session.id,
                    performedAt: session.performedAt,
                    timeZoneIdentifier: session.timeZoneIdentifier,
                    kind: session.kind,
                    segments: session.segments,
                    freshPaceSecondsPerKilometre: session.freshPaceSecondsPerKilometre,
                    totalDurationSeconds: session.totalDurationSeconds,
                    roxzoneSeconds: session.roxzoneSeconds,
                    compromisedPenalty: session.compromisedPenalty,
                    sessionLoad: session.sessionLoad,
                    note: session.note,
                    engineVersion: EngineConstants.engineVersion,
                    createdAt: Date()
                )
                modelContext.insert(model)
            }
            try save()
            guard let snapshot = snapshot(of: model) else {
                throw ZenithiumError.persistenceWriteFailed(detail: "Tanınmayan seans türü.")
            }
            return snapshot
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteHybridSession(id: UUID) throws {
        var descriptor = FetchDescriptor<HybridSessionLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    private func snapshot(of model: HybridSessionLog) -> HybridSessionSnapshot? {
        guard let kind = model.kind else { return nil }
        return HybridSessionSnapshot(
            id: model.id,
            performedAt: model.performedAt,
            timeZoneIdentifier: model.timeZoneIdentifier,
            kind: kind,
            segments: model.segments,
            freshPaceSecondsPerKilometre: model.freshPaceSecondsPerKilometre,
            totalDurationSeconds: model.totalDurationSeconds,
            roxzoneSeconds: model.roxzoneSeconds,
            compromisedPenalty: model.compromisedPenalty,
            sessionLoad: model.sessionLoad,
            note: model.note
        )
    }

    // MARK: - Journal

    /// Bir günün kaydı. Kayıt yoksa `nil` — boş bir kayıtla ayırt edilebilmesi için.
    func journalDay(for dayStart: Date) throws -> JournalDay? {
        var descriptor = FetchDescriptor<JournalDayLog>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first?.journalDay
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Bir aralıktaki kayıtlar, eskiden yeniye.
    func journalDays(from start: Date, through end: Date) throws -> [JournalDay] {
        let descriptor = FetchDescriptor<JournalDayLog>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart <= end },
            sortBy: [SortDescriptor(\.dayStart, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(\.journalDay)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Bir günün kaydını yazar. Boş kayıt satırı siler — böylece "hiç kaydetmedim" ile
    /// "kaydettim ama hepsini kaldırdım" aynı şeye iner ve korelasyon motoru boş satırları
    /// gözlem sanmaz.
    @discardableResult
    func saveJournalDay(_ day: JournalDay) throws -> JournalDay {
        let dayStart = day.dayStart
        var descriptor = FetchDescriptor<JournalDayLog>(
            predicate: #Predicate { $0.dayStart == dayStart }
        )
        descriptor.fetchLimit = 1
        do {
            let existing = try modelContext.fetch(descriptor).first
            if day.isEmpty {
                if let existing { modelContext.delete(existing) }
                try save()
                return day
            }
            let now = Date()
            if let existing {
                existing.behaviors = day.behaviors
                existing.mood = day.mood
                existing.note = day.note
                existing.updatedAt = now
            } else {
                modelContext.insert(
                    JournalDayLog(
                        dayStart: day.dayStart,
                        behaviorRawValues: day.behaviors.map(\.rawValue).sorted(),
                        moodRawValue: day.mood?.rawValue,
                        note: day.note,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            try save()
            return day
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Muscle snapshots

    /// Replaces the cached projection. Only the newest is kept — ASSUMPTION MUSCLE-3 makes
    /// this a cache, always re-derivable from the trailing sessions.
    func saveMuscleSnapshot(_ record: MuscleFatigueSnapshotRecord) throws {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<MuscleFatigueSnapshot>())
            for model in existing { modelContext.delete(model) }
            modelContext.insert(
                MuscleFatigueSnapshot(
                    computedAt: record.computedAt,
                    fatigueValues: record.fatigueValues,
                    halfLifeHours: record.halfLifeHours,
                    sleepScoreUsed: record.sleepScoreUsed,
                    engineVersion: record.engineVersion
                )
            )
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func latestMuscleSnapshot() throws -> MuscleFatigueSnapshotRecord? {
        var descriptor = FetchDescriptor<MuscleFatigueSnapshot>(
            sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return nil }
            return MuscleFatigueSnapshotRecord(
                computedAt: model.computedAt,
                fatigueValues: model.fatigueValues,
                halfLifeHours: model.halfLifeHours,
                sleepScoreUsed: model.sleepScoreUsed,
                engineVersion: model.engineVersion
            )
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Goal events (Faz 20)

    func goalEvents() throws -> [GoalEvent] {
        let descriptor = FetchDescriptor<GoalEventLog>(
            sortBy: [SortDescriptor(\.eventDate, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(\.event)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// Every goal with the plan start stored beside it.
    ///
    /// `goalEvents()` drops the plan start because no screen needs it; an archive does, and
    /// pairing the two after the fact would mean guessing. Yol haritası v4, C9.
    func goalEventsWithPlanStart() throws -> [(event: GoalEvent, planStart: Date?)] {
        let descriptor = FetchDescriptor<GoalEventLog>(
            sortBy: [SortDescriptor(\.eventDate, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ($0.event, $0.planStart) }
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    /// The soonest event not yet past.
    ///
    /// Only one matters to a prescription: planning towards two events at once is a coaching
    /// decision the app is not equipped to make, and silently biasing towards the further
    /// one would be worse than picking the near one.
    func nextGoalEvent(onOrAfter day: Date) throws -> (event: GoalEvent, planStart: Date?)? {
        var descriptor = FetchDescriptor<GoalEventLog>(
            predicate: #Predicate { $0.eventDate >= day },
            sortBy: [SortDescriptor(\.eventDate, order: .forward)]
        )
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return nil }
            return (model.event, model.planStart)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func saveGoalEvent(_ event: GoalEvent, planStart: Date?) throws -> GoalEvent {
        let id = event.id
        var descriptor = FetchDescriptor<GoalEventLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.kind = event.kind
                existing.name = event.name
                existing.eventDate = event.date
                existing.planStart = planStart
            } else {
                modelContext.insert(
                    GoalEventLog(
                        id: event.id,
                        kind: event.kind,
                        name: event.name,
                        eventDate: event.date,
                        planStart: planStart
                    )
                )
            }
            try save()
            return event
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteGoalEvent(id: UUID) throws {
        var descriptor = FetchDescriptor<GoalEventLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Pain entries (Faz 32)

    func painEntries(from start: Date, through end: Date) throws -> [PainEntry] {
        let descriptor = FetchDescriptor<PainEntryLog>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt <= end },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).compactMap(\.entry)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func savePainEntry(_ entry: PainEntry) throws -> PainEntry {
        let id = entry.id
        var descriptor = FetchDescriptor<PainEntryLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.muscleRawValue = entry.muscle.rawValue
                existing.lateralityRawValue = entry.laterality.rawValue
                existing.severity = entry.severity
                existing.qualityRawValue = entry.quality.rawValue
                existing.loggedAt = entry.loggedAt
                existing.note = entry.note
            } else {
                modelContext.insert(PainEntryLog(entry: entry))
            }
            try save()
            return entry
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deletePainEntry(id: UUID) throws {
        var descriptor = FetchDescriptor<PainEntryLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Supplement courses (Yol haritası v4, C5)

    func supplementCourses() throws -> [SupplementCourse] {
        let descriptor = FetchDescriptor<SupplementCourseLog>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map(\.course)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func saveSupplementCourse(_ course: SupplementCourse) throws -> SupplementCourse {
        let id = course.id
        var descriptor = FetchDescriptor<SupplementCourseLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = course.name
                existing.startedAt = course.startedAt
                existing.endedAt = course.endedAt
                existing.note = course.note
            } else {
                modelContext.insert(
                    SupplementCourseLog(
                        id: course.id,
                        name: course.name,
                        startedAt: course.startedAt,
                        endedAt: course.endedAt,
                        note: course.note
                    )
                )
            }
            try save()
            return course
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteSupplementCourse(id: UUID) throws {
        var descriptor = FetchDescriptor<SupplementCourseLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Health documents (Faz 26)

    func healthDocuments() throws -> [HealthDocument] {
        let descriptor = FetchDescriptor<HealthDocumentLog>(
            sortBy: [SortDescriptor(\.documentDate, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).compactMap(\.document)
        } catch {
            throw ZenithiumError.persistenceReadFailed(detail: error.localizedDescription)
        }
    }

    @discardableResult
    func saveHealthDocument(_ document: HealthDocument) throws -> HealthDocument {
        let id = document.id
        var descriptor = FetchDescriptor<HealthDocumentLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.kindRawValue = document.kind.rawValue
                existing.title = document.title
                existing.documentDate = document.documentDate
                existing.note = document.note
            } else {
                modelContext.insert(HealthDocumentLog(document: document))
            }
            try save()
            return document
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func deleteHealthDocument(id: UUID) throws {
        var descriptor = FetchDescriptor<HealthDocumentLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(model)
            try save()
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Saving

    private func save() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            ZenithiumLog.store.error("Save failed")
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }
}
