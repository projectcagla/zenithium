import Foundation

struct ScoreDetails: Sendable {
    var history: [BiometricDaySnapshot] = []
    var change: RecoveryChange?
    var comparisonNote: String?
}

actor ScoreDetailsCoordinator {
    private let records: (any BiometricDayRepository)?
    private let health: (any HealthDataProviding)?
    init(records: (any BiometricDayRepository)?, health: (any HealthDataProviding)?) {
        self.records = records
        self.health = health
    }

    func load(for result: RecalculationResult) async throws -> ScoreDetails {
        guard let records else { return ScoreDetails() }
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: result.record.timeZoneIdentifier) ?? .current
        guard let start = calendar.date(byAdding: .day, value: -60, to: result.dayStart),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: result.dayStart) else { return ScoreDetails() }
        let days = try await records.dayRecords(from: start, through: result.dayStart)
            .filter { $0.dayStart < result.dayStart }.sorted { $0.dayStart < $1.dayStart }
        var details = ScoreDetails(history: days)
        guard let previous = days.first(where: { calendar.isDate($0.dayStart, inSameDayAs: yesterday) }),
              let previousScore = previous.recoveryScore, let health else {
            details.comparisonNote = "Dün için karşılaştırılabilir toparlanma kaydı yok. Eksik gün yerine başka bir gün kullanılmaz."
            return details
        }
        let resolver = DayWindowResolver(calendar: calendar, boundary: result.profile.dayBoundary)
        do {
            let night = try await health.fetchOvernightBiometrics(for: resolver.nightWindow(forWakeDay: yesterday), calendar: calendar)
            func observation(_ metric: MetricKind) -> MetricObservation? {
                guard let value = night.value(for: metric), let baseline = result.baselines[metric] else { return nil }
                return MetricObservation(value: value, baseline: BaselineEngine.scoringBaseline(from: baseline))
            }
            let previousOnCurrentBaseline = RecoveryEngine.compute(RecoveryInput(
                heartRateVariability: observation(.heartRateVariability), restingHeartRate: observation(.restingHeartRate),
                wristTemperature: observation(.wristTemperature), respiratoryRate: observation(.respiratoryRate),
                sleepScore: previous.sleepScore, hasOvernightData: !night.isEmpty, sleepWasImplausible: false))
            details.change = RecoveryChangeEngine.compare(previousScore: previousScore,
                previousOnCurrentBaseline: previousOnCurrentBaseline, current: result.recovery)
            if details.change == nil { details.comparisonNote = "Dünkü ham ölçümler karşılaştırma için yetersiz. Katkı payları tahmin edilmedi." }
        } catch {
            details.comparisonNote = "Dünkü ölçümler okunamadığı için fark ayrıştırması şu anda gösterilemiyor. Yenileyerek tekrar deneyebilirsin."
        }
        return details
    }
}
