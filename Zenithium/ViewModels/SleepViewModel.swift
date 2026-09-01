//
//  SleepViewModel.swift
//  Zenithium
//
//  The Sleep screen. Spec §5.2, §10.
//

import Foundation
import Observation

@MainActor
@Observable
final class SleepViewModel {

    struct Content: Sendable, Equatable {
        let sleep: SleepOutput
        let record: BiometricDaySnapshot
        let stages: [StageSlice]
        let profile: UserProfileSnapshot

        var score: Double { sleep.score ?? 0 }

        /// Hours of shortfall against the night's need, or zero when the need was met.
        var shortfallHours: Double {
            max(0, sleep.needHours - sleep.asleepHours)
        }
    }

    /// One stage's share of the night, pre-measured for the stacked bar.
    struct StageSlice: Sendable, Equatable, Identifiable {
        let stage: SleepStage
        let seconds: Double
        let share: Double

        var id: SleepStage { stage }

        var minutes: Int { Int((seconds / TimeConversion.secondsPerMinute).rounded()) }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isRefreshing = false

    private let coordinator: any RecalculationDriving
    private let health: any HealthAuthorizing
    private let nowProvider: @Sendable () -> Date
    private var observationTask: Task<Void, Never>?

    init(
        coordinator: any RecalculationDriving,
        health: any HealthAuthorizing,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.health = health
        self.nowProvider = nowProvider
    }

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
        startObserving()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard await health.isHealthDataAvailable() else {
            state = .needsAuthorization(.unavailable)
            return
        }
        let report = await health.authorizationReport(now: nowProvider())
        guard report.overall.permitsReads else {
            state = .needsAuthorization(report.overall)
            return
        }
        do {
            apply(try await coordinator.recalculate(now: nowProvider()))
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
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
        switch result.sleep.validity {
        case .noData:
            state = .noData(reason: .noOvernightData)
        case .tooShort, .tooLong:
            state = .noData(reason: .sleepImplausible)
        case .valid:
            state = .loaded(
                Content(
                    sleep: result.sleep,
                    record: result.record,
                    stages: Self.stageSlices(from: result.record),
                    profile: result.profile
                )
            )
        }
    }

    static func stageSlices(from record: BiometricDaySnapshot) -> [StageSlice] {
        let pairs: [(SleepStage, Double)] = [
            (.asleepDeep, record.deepSeconds),
            (.asleepREM, record.remSeconds),
            (.asleepCore, record.coreSeconds),
            (.awake, record.awakeSeconds)
        ]
        let total = pairs.reduce(into: 0.0) { $0 += $1.1 }
        return pairs.map { stage, seconds in
            StageSlice(
                stage: stage,
                seconds: seconds,
                share: MathSupport.safeDivide(seconds, by: total)
            )
        }
    }
}
