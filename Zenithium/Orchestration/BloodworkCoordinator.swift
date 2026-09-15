import Foundation

actor BloodworkCoordinator {
    private let markers: any BloodMarkerRepository
    private let records: (any BiometricDayRepository)?

    init(markers: any BloodMarkerRepository, records: (any BiometricDayRepository)? = nil) {
        self.markers = markers
        self.records = records
    }

    func load(now: Date) async throws -> (markers: [BloodMarkerSnapshot], observations: [LabObservation], context: [LabTrainingContext]) {
        let values = try await markers.bloodMarkers()
        var context: [LabTrainingContext] = []
        if let records {
            let calendar = Calendar.autoupdatingCurrent
            let dates = Set(values.map { calendar.startOfDay(for: $0.drawnAt) }).sorted(by: >)
            for date in dates.prefix(24) {
                guard let start = calendar.date(byAdding: .day, value: -60, to: date) else { continue }
                let history = try await records.dayRecords(from: start, through: date)
                context.append(Self.context(day: date, history: history, calendar: calendar))
            }
        }
        return (values, LabInsightEngine.observations(markers: values, sex: .notSet, now: now), context)
    }

    /// Descriptive coincidence. No lab value changes recovery, and future days never enter.
    static func context(day: Date, history: [BiometricDaySnapshot], calendar: Calendar) -> LabTrainingContext {
        let date = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -60, to: date) ?? date
        let prior = history.filter { $0.dayStart >= start && $0.dayStart < date }.sorted { $0.dayStart < $1.dayStart }
        let samples = prior.compactMap { record -> DailyMetricSample? in
            guard let value = record.heartRateVariability else { return nil }
            return DailyMetricSample(dayStart: record.dayStart, value: value, timeZoneIdentifier: record.timeZoneIdentifier)
        }
        let baseline = BaselineEngine.rebuild(metric: .heartRateVariability, from: samples)
        let hrv = history.first { calendar.isDate($0.dayStart, inSameDayAs: date) }?.heartRateVariability
        let mature = baseline.sampleCount >= 14
        let z = mature ? hrv.map { ($0 - baseline.mean) / baseline.effectiveStandardDeviation } : nil
        let cutoff = calendar.date(byAdding: .day, value: -28, to: date) ?? date
        let loadHistory = prior.filter { $0.dayStart >= cutoff && $0.maxHeartRateUsed != nil && $0.trimp.isFinite }
        // An absent sensor day cannot be silently converted into a rest day.
        let loadDays = Set(loadHistory.map { calendar.startOfDay(for: $0.dayStart) }).count
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let ratio = loadDays == 28 ? TrainingLoadEngine.analyse(TrainingLoadInput(
            days: loadHistory.map { DailyLoad(dayStart: $0.dayStart, load: $0.trimp) }, referenceDay: yesterday, calendar: calendar)).ratio : nil
        return LabTrainingContext(day: date, hrv: hrv, hrvBaseline: mature ? baseline.mean : nil, hrvZ: z,
                                  hrvNights: baseline.sampleCount, loadRatio: ratio, loadDays: loadDays)
    }

    func save(id: UUID, marker: BloodMarkerKind, value: Double, unit: String, reference: MarkerRange,
              optimal: MarkerRange, drawnAt: Date, note: String) async throws {
        let prepared = try LabRecording.prepare(marker: marker, value: value, unit: unit, reference: reference)
        let optimalPrepared = try LabRecording.prepare(marker: marker, value: value, unit: unit, reference: optimal)
        try await markers.saveBloodMarker(id: id, marker: marker, value: prepared.value, unitSymbol: prepared.unit,
            referenceRange: prepared.reference, optimalRange: optimalPrepared.reference, drawnAt: drawnAt, note: note)
    }

    func delete(id: UUID) async throws { try await markers.deleteBloodMarker(id: id) }
}
