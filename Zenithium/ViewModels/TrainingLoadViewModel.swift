//
//  TrainingLoadViewModel.swift
//  Zenithium
//
//  The training-load screen. Faz 14.
//
//  Load history comes from the day records the recovery pipeline already writes, so this
//  screen needs no new HealthKit read and no new storage — `dayStrain` is the load series.
//

import Foundation
import Observation

@MainActor
@Observable
final class TrainingLoadViewModel {

    /// One plotted point of the ratio line.
    struct RatioPoint: Sendable, Equatable, Identifiable {
        let dayStart: Date
        let ratio: Double
        var id: Date { dayStart }
    }

    struct Content: Sendable, Equatable {
        let output: TrainingLoadOutput

        /// Daily loads for the chart, oldest first.
        let series: [DailyLoad]

        /// The ratio on each of those days, paired with its date. Empty until there is
        /// enough history for a ratio to mean anything.
        let ratioPoints: [RatioPoint]

        let summary: String
        let monotonySummary: String?

        /// The maximum training load that keeps the acute:chronic workload ratio inside
        /// the productive zone (≤ 1.30) today.
        let sweetSpotCeiling: Double?

        var band: LoadBand? { output.band }

        /// The ratio line shares the load axis, so it is scaled onto it. Without this the
        /// ratio — which lives between roughly 0.6 and 1.6 — would be a flat line pinned to
        /// the bottom of a chart whose bars reach into the tens.
        var ratioScale: Double {
            let peak = series.map(\.load).max() ?? 0
            return peak > 0 ? peak / 2 : 1
        }
    }

    private(set) var state: ViewState<Content> = .loading

    private let records: any BiometricDayRepository
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    /// How much history the chart shows. Longer than the chronic window so the exponential
    /// terms are past their seed by the time the first plotted day is reached.
    private static let historyDays = 120

    init(
        records: any BiometricDayRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.records = records
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        let now = nowProvider()
        let calendar = calendarProvider()
        let start = now.addingTimeInterval(-Double(Self.historyDays) * 86_400)

        do {
            let days = try await records.dayRecords(from: start, through: now)
            guard !days.isEmpty else {
                state = .noData(reason: .notEnoughHistory(daysAvailable: 0, daysRequired: EngineConstants.TrainingLoad.chronicWindowDays))
                return
            }

            let loads = days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) }
            let input = TrainingLoadInput(days: loads, referenceDay: now, calendar: calendar)
            let output = TrainingLoadEngine.analyse(input)
            let series = TrainingLoadEngine.densifiedSeries(input)

            // The ratio line only starts where the ratio starts meaning something. Plotting
            // it from day one would draw the exponential terms settling out of their seed,
            // which looks like a trend and is not one.
            let ratios = TrainingLoadEngine.exponentialTrack(series).dailyRatios
            let warmUp = EngineConstants.TrainingLoad.chronicWindowDays
            let ratioPoints: [RatioPoint] = output.ratio == nil || series.count <= warmUp
                ? []
                : zip(series, ratios).dropFirst(warmUp).map { RatioPoint(dayStart: $0.dayStart, ratio: $1) }

            let ceiling = TrainingLoadEngine.loadCeiling(forInstantRatio: 1.30, from: output)
            state = .loaded(
                Content(
                    output: output,
                    series: series,
                    ratioPoints: ratioPoints,
                    summary: TrainingLoadEngine.summary(for: output),
                    monotonySummary: TrainingLoadEngine.monotonySummary(for: output),
                    sweetSpotCeiling: ceiling
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }
}
