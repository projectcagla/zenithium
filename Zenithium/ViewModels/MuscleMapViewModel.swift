//
//  MuscleMapViewModel.swift
//  Zenithium
//
//  The Muscle Map screen and the strength logger. Spec §5.4, §10.
//

import Foundation
import Observation

@MainActor
@Observable
final class MuscleMapViewModel {

    struct Content: Sendable, Equatable {
        /// Readiness for all 16 groups, in the fixed enum order (§5.4).
        let readiness: [MuscleReadiness]
        let computedAt: Date
        let sleepScoreUsed: Double

        func readiness(for muscle: MuscleGroup) -> MuscleReadiness? {
            readiness.first { $0.muscle == muscle }
        }

        /// The groups with the most headroom, for the "train these" summary.
        var mostReady: [MuscleReadiness] {
            readiness.sorted { $0.readiness > $1.readiness }.prefix(3).map { $0 }
        }

        /// The groups still carrying the most load.
        var leastReady: [MuscleReadiness] {
            readiness.sorted { $0.readiness < $1.readiness }.prefix(3).map { $0 }
        }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var sessions: [StrengthSessionSnapshot] = []
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?
    var selectedSide: BodySide = .anterior
    var selectedMuscle: MuscleGroup?

    /// Pain insights, refreshed whenever an entry is saved (Faz 32).
    private(set) var painInsights: [PainInsight] = []

    /// Logged pain entries in the active window.
    private(set) var painEntries: [PainEntry] = []

    private let coordinator: any RecalculationDriving
    private let repository: any StrengthSessionRepository

    /// Pain entries and the load history they are compared against (Faz 32). Optional: the
    /// map works without them, and a missing pain log leaves the card absent rather than
    /// blanking the screen.
    private let painRepository: (any PainEntryRepository)?
    private let records: (any BiometricDayRepository)?

    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar
    private var observationTask: Task<Void, Never>?

    init(
        coordinator: any RecalculationDriving,
        repository: any StrengthSessionRepository,
        painRepository: (any PainEntryRepository)? = nil,
        records: (any BiometricDayRepository)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.coordinator = coordinator
        self.repository = repository
        self.painRepository = painRepository
        self.records = records
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    /// Save a pain entry and refresh the insights.
    func savePain(_ entry: PainEntry) async {
        guard let painRepository else { return }
        do {
            try await painRepository.savePainEntry(entry)
            await loadPainInsights()
        } catch {
            saveError = error as? ZenithiumError
                ?? .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    /// Delete a pain entry and refresh the insights.
    func deletePain(id: UUID) async {
        guard let painRepository else { return }
        do {
            try await painRepository.deletePainEntry(id: id)
            await loadPainInsights()
        } catch {
            saveError = error as? ZenithiumError
                ?? .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    /// Compare logged entries against the load that preceded them.
    ///
    /// Silent on failure: this is a secondary read, and an error here should not take the
    /// muscle map down with it.
    func loadPainInsights() async {
        guard let painRepository, let records else { return }
        let now = nowProvider()
        let start = now.addingTimeInterval(-Double(Self.painWindowDays) * 86_400)

        guard let entries = try? await painRepository.painEntries(from: start, through: now),
              !entries.isEmpty,
              let days = try? await records.dayRecords(from: start, through: now) else {
            painEntries = []
            painInsights = []
            return
        }

        painEntries = entries.sorted { $0.loggedAt > $1.loggedAt }
        painInsights = PainEngine.insights(
            entries: entries,
            dailyLoads: days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) },
            calendar: calendarProvider()
        )
    }

    /// How far back the pain log is compared.
    private static let painWindowDays = 90

    /// Stops observing. Called from the view's `.onDisappear`.
    ///
    /// This is an explicit method rather than a `deinit`: `deinit` is nonisolated, so reading
    /// a `@MainActor` stored property from it is a strict-concurrency error.
    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
    }

    func onAppear() async {
        if state.isLoading {
            await refresh()
        }
        await loadPainInsights()
        startObserving()
    }

    func refresh() async {
        do {
            let result = try await coordinator.recalculate(now: nowProvider())
            apply(result)
            await loadSessions()
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Saves a logged strength session and re-projects fatigue.
    ///
    /// The session load is computed here rather than in the store: §6 keeps engine calls out
    /// of the persistence layer, so the view model does the maths and persists the answer.
    func saveSession(
        id: UUID = UUID(),
        pattern: MovementPattern,
        performedAt: Date,
        entries: [StrengthEntry],
        note: String
    ) async {
        let valid = entries.filter(\.isValid)
        guard !valid.isEmpty else {
            saveError = .invalidEngineInput(reason: "Set, tekrar ve RPE'si olan en az bir hareket ekle.")
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let load = StrainEngine.sessionLoad(forVolumeLoad: valid.totalVolumeLoad)
            _ = try await repository.saveStrengthSession(
                id: id,
                performedAt: performedAt,
                timeZoneIdentifier: calendarProvider().timeZone.identifier,
                pattern: pattern,
                entries: valid,
                sessionLoad: load,
                note: note
            )
            await refresh()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    func deleteSession(id: UUID) async {
        do {
            try await repository.deleteStrengthSession(id: id)
            await refresh()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    /// A live preview of the session load while the user is still typing (§5.4).
    func previewSessionLoad(for entries: [StrengthEntry]) -> Double {
        StrainEngine.sessionLoad(forVolumeLoad: entries.filter(\.isValid).totalVolumeLoad)
    }

    private func loadSessions() async {
        let calendar = calendarProvider()
        let now = nowProvider()
        let start = calendar.date(
            byAdding: .day,
            value: -EngineConstants.Fatigue.projectionWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? now
        sessions = (try? await repository.strengthSessions(from: start, through: now)) ?? []
    }

    private func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.coordinator.results()
            for await result in stream {
                guard !Task.isCancelled else { return }
                self.apply(result)
            }
        }
    }

    private func apply(_ result: RecalculationResult) {
        let ordered = MuscleGroup.allCases.compactMap { result.muscle[$0] }
        guard ordered.count == MuscleGroup.allCases.count else {
            state = .noData(reason: .nothingLogged(what: "training"))
            return
        }
        state = .loaded(
            Content(
                readiness: ordered,
                computedAt: result.computedAt,
                sleepScoreUsed: result.sleep.score ?? DailyRecalculationCoordinator.neutralSleepScore
            )
        )
    }
}
