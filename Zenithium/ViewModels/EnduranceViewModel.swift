//
//  EnduranceViewModel.swift
//  Zenithium
//
//  The endurance screen. Faz 15.
//

import Foundation
import Observation

@MainActor
@Observable
final class EnduranceViewModel {

    struct Content: Sendable, Equatable {

        /// The fitted model, or `nil` when there are not enough efforts yet.
        let model: CriticalSpeedModel?

        let predictions: [RacePrediction]
        let zones: [PaceZoneBand]

        /// The efforts the fit used, newest first, so the user can see what it was built on.
        let efforts: [BestEffort]

        /// Where heat adaptation stands, from the sessions that recorded weather.
        /// Yol haritası v4, C7.
        let heat: HeatAcclimationState

        /// Sessions this person keeps repeating. Yol haritası v4, C8.
        let shapes: [SessionShape]

        /// Weekly distance over the recent window, oldest first.
        let weeklyDistance: [WeeklyDistance]

        let summary: String?

        /// How many more efforts are needed before a model exists.
        var effortsNeeded: Int {
            max(0, EnduranceEngine.minimumEfforts - efforts.count)
        }
    }

    struct WeeklyDistance: Sendable, Equatable, Identifiable {
        let weekStart: Date
        /// Kilometres.
        let distance: Double
        var id: Date { weekStart }
    }

    private(set) var state: ViewState<Content> = .loading

    private let health: any HealthDataProviding
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    /// How far back workouts are read. Longer than the effort window so the weekly-distance
    /// chart has something to show even for someone who has not raced recently.
    private static let workoutWindowDays = 180

    init(
        health: any HealthDataProviding,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.health = health
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        let now = nowProvider()
        let calendar = calendarProvider()
        let start = now.addingTimeInterval(-Double(Self.workoutWindowDays) * 86_400)

        do {
            let workouts = try await health.fetchWorkouts(in: DateInterval(start: start, end: now))
            let runs = workouts.filter { Self.countsAsRun($0.activity) }
            guard !runs.isEmpty else {
                state = .noData(reason: .nothingLogged(what: "koşu"))
                return
            }

            let efforts = Self.efforts(from: runs)
            let model = EnduranceEngine.fit(efforts: efforts, now: now)

            state = .loaded(
                Content(
                    model: model,
                    predictions: model.map(EnduranceEngine.predictions(from:)) ?? [],
                    zones: model.map(EnduranceEngine.paceZones(from:)) ?? [],
                    efforts: efforts.sorted { $0.date > $1.date },
                    heat: HeatAcclimationEngine.state(
                        // Every workout, not only runs: a hot bike ride adapts the same
                        // physiology, and restricting this to running would understate it.
                        exposures: HeatAcclimationEngine.exposures(from: workouts),
                        now: now,
                        calendar: calendar
                    ),
                    shapes: SessionShapeEngine.shapes(from: workouts, now: now),
                    weeklyDistance: Self.weeklyDistance(from: runs, calendar: calendar),
                    summary: model.map(EnduranceEngine.summary(for:))
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Which activities the endurance lens treats as running.
    ///
    /// Deliberately narrow. Walking and hiking have distance and duration but a completely
    /// different speed–duration relationship, and folding them in would drag critical speed
    /// down towards a walking pace.
    private static func countsAsRun(_ activity: WorkoutActivity) -> Bool {
        activity == .running
    }

    /// Turn whole workouts into best efforts.
    ///
    /// One effort per workout, using its total distance and duration. This is the honest
    /// limit of what HealthKit gives cheaply: a proper rolling-best segment needs a
    /// per-second distance series, which is not available from a workout summary. A steady
    /// tempo run therefore contributes a good point and an interval session contributes a
    /// poor one — which is why the fit takes only the fastest effort at each distance and
    /// reports its own R².
    static func efforts(from runs: [WorkoutSummary]) -> [BestEffort] {
        runs.compactMap { run in
            guard let distance = run.distanceMeters, distance > 0, run.duration > 0 else { return nil }
            return BestEffort(distance: distance, duration: run.duration, date: run.start)
        }
    }

    /// Kilometres per calendar week.
    static func weeklyDistance(from runs: [WorkoutSummary], calendar: Calendar) -> [WeeklyDistance] {
        var byWeek: [Date: Double] = [:]
        for run in runs {
            guard let distance = run.distanceMeters else { continue }
            guard let week = calendar.dateInterval(of: .weekOfYear, for: run.start)?.start else { continue }
            byWeek[week, default: 0] += distance / 1000
        }
        return byWeek
            .map { WeeklyDistance(weekStart: $0.key, distance: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }
}
