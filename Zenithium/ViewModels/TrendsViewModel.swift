//
//  TrendsViewModel.swift
//  Zenithium
//
//  The Trends screen: 7 / 30 / 90-day series. Spec §10.
//

import Foundation
import Observation

/// A metric the trends chart can plot.
enum TrendMetric: String, Sendable, CaseIterable, Hashable, Identifiable {
    case recovery
    case strain
    case sleep
    case heartRateVariability
    case restingHeartRate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recovery: return "Toparlanma"
        case .strain: return "Zorlanma"
        case .sleep: return "Uyku"
        case .heartRateVariability: return "HRV"
        case .restingHeartRate: return "İstirahat nabzı"
        }
    }

    var unitSymbol: String {
        switch self {
        case .recovery, .sleep: return "%"
        case .strain: return ""
        case .heartRateVariability: return CanonicalUnit.heartRateVariabilitySymbol
        case .restingHeartRate: return CanonicalUnit.heartRateSymbol
        }
    }

    /// The fixed axis range, when the metric has one. `nil` means fit to the data.
    var fixedRange: ClosedRange<Double>? {
        switch self {
        case .recovery, .sleep: return 0...100
        case .strain: return 0...EngineConstants.Strain.scaleMax
        case .heartRateVariability, .restingHeartRate: return nil
        }
    }

    var fractionDigits: Int {
        switch self {
        case .recovery, .sleep, .heartRateVariability, .restingHeartRate: return 0
        case .strain: return 1
        }
    }

    func value(from record: BiometricDaySnapshot) -> Double? {
        switch self {
        case .recovery: return record.recoveryScore
        case .strain: return record.dayStrain
        case .sleep: return record.sleepScore
        case .heartRateVariability: return record.heartRateVariability
        case .restingHeartRate: return record.restingHeartRate
        }
    }
}

/// The window a trend covers.
enum TrendRange: Int, Sendable, CaseIterable, Hashable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var displayName: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        }
    }

    var accessibilityName: String {
        switch self {
        case .week: return "Yedi gün"
        case .month: return "Otuz gün"
        case .quarter: return "Doksan gün"
        }
    }
}

/// One plotted point.
struct TrendPoint: Sendable, Equatable, Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// A blood draw event plotted on a trend chart.
struct TrendBloodEvent: Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let panelName: String
}

@MainActor
@Observable
final class TrendsViewModel {

    struct Content: Sendable, Equatable {
        let points: [TrendPoint]
        let metric: TrendMetric
        let range: TrendRange
        let average: Double?
        let minimum: Double?
        let maximum: Double?
        let bloodEvents: [TrendBloodEvent]

        init(
            points: [TrendPoint],
            metric: TrendMetric,
            range: TrendRange,
            average: Double?,
            minimum: Double?,
            maximum: Double?,
            bloodEvents: [TrendBloodEvent] = []
        ) {
            self.points = points
            self.metric = metric
            self.range = range
            self.average = average
            self.minimum = minimum
            self.maximum = maximum
            self.bloodEvents = bloodEvents
        }

        /// The axis range: the metric's fixed one, or a padded fit to the data.
        var axisRange: ClosedRange<Double> {
            if let fixed = metric.fixedRange { return fixed }
            guard let minimum, let maximum, maximum > minimum else { return 0...1 }
            let padding = (maximum - minimum) * 0.1
            return (minimum - padding)...(maximum + padding)
        }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var metric: TrendMetric = .recovery
    private(set) var range: TrendRange = .month

    private let repository: any BiometricDayRepository
    private let bloodMarkers: (any BloodMarkerRepository)?
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar
    private var loadTask: Task<Void, Never>?

    init(
        repository: any BiometricDayRepository,
        bloodMarkers: (any BloodMarkerRepository)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.repository = repository
        self.bloodMarkers = bloodMarkers
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    /// Cancels any in-flight load. Called from the view's `.onDisappear`.
    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        let calendar = calendarProvider()
        let now = nowProvider()
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) else {
            state = .failed(.invalidEngineInput(reason: "Tarih aralığı çözülemedi."))
            return
        }
        do {
            let records = try await repository.dayRecords(from: start, through: today)
            let points = records.compactMap { record -> TrendPoint? in
                guard let value = metric.value(from: record) else { return nil }
                return TrendPoint(date: record.dayStart, value: value)
            }
            // A single point is not a trend. Saying so is more useful than drawing a dot and
            // calling it a chart.
            guard points.count >= Self.minimumPointsForTrend else {
                state = .noData(
                    reason: .notEnoughHistory(
                        daysAvailable: points.count,
                        daysRequired: Self.minimumPointsForTrend
                    )
                )
                return
            }
            let values = points.map(\.value)

            var bloodEvents: [TrendBloodEvent] = []
            if (metric == .heartRateVariability || metric == .restingHeartRate), let bloodMarkers {
                if let markers = try? await bloodMarkers.bloodMarkers() {
                    let inRange = markers.filter { $0.drawnAt >= start && $0.drawnAt <= now }
                    // Group by date and panel
                    var seen = Set<String>()
                    for marker in inRange {
                        let panelName = marker.marker.panel?.displayName ?? "Laboratuvar"
                        let key = "\(calendar.startOfDay(for: marker.drawnAt).timeIntervalSince1970)_\(panelName)"
                        if !seen.contains(key) {
                            seen.insert(key)
                            bloodEvents.append(
                                TrendBloodEvent(
                                    id: marker.id,
                                    date: marker.drawnAt,
                                    panelName: panelName
                                )
                            )
                        }
                    }
                }
            }

            state = .loaded(
                Content(
                    points: points,
                    metric: metric,
                    range: range,
                    average: MathSupport.mean(values),
                    minimum: values.min(),
                    maximum: values.max(),
                    bloodEvents: bloodEvents
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Changes the plotted metric and reloads.
    ///
    /// An explicit method rather than a `didSet` on an `@Observable` property: the macro
    /// rewrites stored properties into accessors, and a property observer on top of that is
    /// needless subtlety for something the picker can just call.
    func select(metric newMetric: TrendMetric) {
        guard newMetric != metric else { return }
        metric = newMetric
        reload()
    }

    /// Changes the window and reloads.
    func select(range newRange: TrendRange) {
        guard newRange != range else { return }
        range = newRange
        reload()
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load()
        }
    }

    private static let minimumPointsForTrend = 1
}
