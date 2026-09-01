//
//  StrainViewModel.swift
//  Zenithium
//
//  The Strain screen: how hard should I go. Spec §1, §5.3, §10.
//

import Foundation
import Observation

@MainActor
@Observable
final class StrainViewModel {

    struct Content: Sendable, Equatable {
        let strain: StrainOutput
        let record: BiometricDaySnapshot
        let zoneBars: [ZoneBar]
        let guidance: String
        let dayStart: Date
        let history: [BiometricDaySnapshot]

        /// The day split into training and everything else (Faz 13). `nil` until the split
        /// has been computed, or when there was no intraday series to split.
        var stress: StressDay?

        var ceiling: Double? { strain.targetCeiling }

        /// Strain against the ceiling, clamped for the gauge. `nil` when recovery is absent,
        /// which the view renders as an open ring rather than a full one.
        var ceilingProgress: Double? {
            guard let ceiling = strain.targetCeiling, ceiling > 0 else { return nil }
            return MathSupport.clamp(strain.strain / ceiling, 0, 1)
        }
    }

    /// One zone's bar, pre-measured so the view lays out without arithmetic.
    struct ZoneBar: Sendable, Equatable, Identifiable {
        let zone: HeartRateZone
        let seconds: Double
        /// Share of the day's zone time, 0…1, for the bar width.
        let share: Double

        var id: HeartRateZone { zone }

        var minutes: Int { Int((seconds / TimeConversion.secondsPerMinute).rounded()) }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isRefreshing = false

    private let coordinator: any RecalculationDriving
    private let records: (any BiometricDayRepository)?

    /// Re-reads the intraday series for the training / rest-of-life split (Faz 13).
    private let stressSource: (any HealthDataProviding)?

    /// Used only when the day has no recorded resting heart rate, which happens before the
    /// first night. The split's bands shift slightly; nothing else depends on it.
    private static let assumedRestingHeartRate: Double = 60
    private var stressTask: Task<Void, Never>?
    private let health: any HealthAuthorizing
    private let nowProvider: @Sendable () -> Date
    private var observationTask: Task<Void, Never>?

    init(
        coordinator: any RecalculationDriving,
        health: any HealthAuthorizing,
        records: (any BiometricDayRepository)? = nil,
        stressSource: (any HealthDataProviding)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.health = health
        self.records = records
        self.stressSource = stressSource
        self.nowProvider = nowProvider
    }

    /// Stops observing. Called from the view's `.onDisappear`.
    ///
    /// This is an explicit method rather than a `deinit`: `deinit` is nonisolated, so reading
    /// a `@MainActor` stored property from it is a strict-concurrency error.
    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
        stressTask?.cancel()
        stressTask = nil
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
            let result = try await coordinator.recalculate(now: nowProvider())
            await apply(result)
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
                await self.apply(result)
            }
        }
    }

    private func apply(_ result: RecalculationResult) async {
        guard let strain = result.strain else {
            // No intraday heart rate yet. Normal first thing in the morning, and honest to
            // say so rather than rendering a zero as though it were a measurement.
            state = .noData(reason: .noHeartRateYet)
            return
        }

        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        let history = (try? await records?.dayRecords(from: start, through: today)) ?? []

        state = .loaded(
            Content(
                strain: strain,
                record: result.record,
                zoneBars: Self.zoneBars(from: strain.zoneSeconds),
                guidance: SafetyCopy.strainGuidance(
                    strain: strain.strain,
                    ceiling: strain.targetCeiling
                ),
                dayStart: result.dayStart,
                history: history,
                stress: nil
            )
        )
        startStressSplit(for: result)
    }

    /// Split the day into training and the rest of life, off the critical path.
    ///
    /// Not awaited by `apply`: the strain number must appear as soon as it exists, and the
    /// split — which re-reads the intraday series — arrives a moment later. Deliberately
    /// silent on failure; a missing split leaves the card absent rather than showing an
    /// error for something nobody asked for.
    private func startStressSplit(for result: RecalculationResult) {
        stressTask?.cancel()
        guard let health = stressSource, let strain = result.strain else { return }

        stressTask = Task { [weak self] in
            guard let self else { return }
            let window = result.dayWindow
            guard let samples = try? await health.fetchIntradayHeartRates(in: window),
                  let workouts = try? await health.fetchWorkouts(in: window) else { return }
            guard !Task.isCancelled else { return }

            let day = StressEngine.analyse(
                samples: samples,
                workouts: workouts,
                dayWindow: window,
                restingHeartRate: result.record.restingHeartRate ?? Self.assumedRestingHeartRate,
                maxHeartRate: strain.maxHeartRateUsed,
                biologicalSex: result.profile.biologicalSex
            )
            guard !Task.isCancelled else { return }

            if case .loaded(var content) = self.state {
                content.stress = day
                self.state = .loaded(content)
            }
        }
    }

    static func zoneBars(from zoneSeconds: [Double]) -> [ZoneBar] {
        let total = zoneSeconds.reduce(0, +)
        return HeartRateZone.allCases.map { zone in
            let seconds = zone.index < zoneSeconds.count ? zoneSeconds[zone.index] : 0
            return ZoneBar(
                zone: zone,
                seconds: seconds,
                share: MathSupport.safeDivide(seconds, by: total)
            )
        }
    }
}
