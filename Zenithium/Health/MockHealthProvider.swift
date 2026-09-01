//
//  MockHealthProvider.swift
//  Zenithium
//
//  A deterministic, seeded stand-in for HealthKit. Spec §8: 90 days of deterministic data.
//
//  Determinism is structural, not incidental: every value is a pure hash of
//  (seed, day index, channel), so the same day always produces the same number regardless of
//  call order, thread, or how many times it is asked. Nothing here uses `random`, and there
//  is no mutable state, which is what lets the pipeline test in §11 assert exact values.
//

import Foundation

/// A seeded fake health source for previews, tests and Simulator runs.
struct MockHealthProvider: HealthDataProviding {

    /// What the fake device supports and how much history it has.
    struct Configuration: Sendable, Equatable {

        /// Days of history the source will answer for. Spec §8 asks for 90.
        var daysOfHistory: Int

        /// Whether the fake watch records sleeping wrist temperature (ASSUMPTION API-1 —
        /// set `false` to exercise the §4.3 renormalization path).
        var recordsWristTemperature: Bool

        /// Whether sleep is staged. Set `false` to exercise the §5.2 `Restorative` drop.
        var recordsSleepStages: Bool

        /// The fraction of nights with no data at all, exercising §4.2.5 gap handling.
        var missingNightFraction: Double

        /// The authorization picture the fake reports.
        var authorizationState: HealthAuthorizationState

        static let `default` = Configuration(
            daysOfHistory: 90,
            recordsWristTemperature: true,
            recordsSleepStages: true,
            missingNightFraction: 0.08,
            authorizationState: .authorized
        )

        /// A Series 6-style device: no wrist temperature.
        static let withoutWristTemperature = Configuration(
            daysOfHistory: 90,
            recordsWristTemperature: false,
            recordsSleepStages: true,
            missingNightFraction: 0.08,
            authorizationState: .authorized
        )

        /// A source that records sleep but does not stage it.
        static let withoutSleepStages = Configuration(
            daysOfHistory: 90,
            recordsWristTemperature: true,
            recordsSleepStages: false,
            missingNightFraction: 0.0,
            authorizationState: .authorized
        )

        /// A perfectly complete source, for tests that want no gaps at all.
        static let complete = Configuration(
            daysOfHistory: 90,
            recordsWristTemperature: true,
            recordsSleepStages: true,
            missingNightFraction: 0.0,
            authorizationState: .authorized
        )
    }

    let seed: UInt64
    let configuration: Configuration
    let characteristics: UserCharacteristics

    init(
        seed: UInt64 = 0x5A6E_1748,
        configuration: Configuration = .default,
        characteristics: UserCharacteristics = MockHealthProvider.defaultCharacteristics
    ) {
        self.seed = seed
        self.configuration = configuration
        self.characteristics = characteristics
    }

    /// A 34-year-old female profile, so the female TRIMP constants are the default path (§5.3).
    static let defaultCharacteristics = UserCharacteristics(
        dateOfBirth: Date(timeIntervalSince1970: 700_000_000),
        biologicalSex: .female,
        maxHeartRateOverride: nil
    )

    // MARK: - HealthDataProviding

    func isHealthDataAvailable() async -> Bool {
        configuration.authorizationState != .unavailable
    }

    func requestAuthorization() async throws {
        switch configuration.authorizationState {
        case .unavailable: throw ZenithiumError.healthDataUnavailable
        case .denied: throw ZenithiumError.healthAuthorizationDenied
        case .notDetermined, .authorized: return
        }
    }

    func authorizationReport(now: Date) async -> HealthAuthorizationReport {
        var byKind: [HealthDataKind: HealthAuthorizationState] = [:]
        for kind in HealthDataKind.allCases {
            byKind[kind] = configuration.authorizationState
        }
        return HealthAuthorizationReport(
            overall: configuration.authorizationState,
            byKind: byKind,
            checkedAt: now
        )
    }

    func fetchCharacteristics() async throws -> UserCharacteristics {
        try requireAuthorization()
        return characteristics
    }

    func fetchBaselineSeries(
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> BaselineSeries {
        try requireAuthorization()
        let end = calendar.startOfDay(for: now)
        let span = min(days, configuration.daysOfHistory)
        guard span > 0, let start = calendar.date(byAdding: .day, value: -span, to: end) else {
            return .empty(rangeStart: end, rangeEnd: end)
        }
        let timeZoneIdentifier = calendar.timeZone.identifier
        var samplesByMetric: [MetricKind: [DailyMetricSample]] = [:]

        for metric in MetricKind.allCases {
            guard supports(metric) else { continue }
            var samples: [DailyMetricSample] = []
            for offset in 0..<span {
                guard let dayStart = calendar.date(byAdding: .day, value: offset, to: start) else {
                    continue
                }
                let index = dayIndex(for: dayStart, calendar: calendar)
                guard !isMissingNight(dayIndex: index) else { continue }
                samples.append(
                    DailyMetricSample(
                        dayStart: dayStart,
                        value: dailyValue(for: metric, dayIndex: index),
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
            }
            if !samples.isEmpty {
                samplesByMetric[metric] = samples
            }
        }
        return BaselineSeries(samplesByMetric: samplesByMetric, rangeStart: start, rangeEnd: end)
    }

    func fetchOvernightBiometrics(
        for night: DateInterval,
        calendar: Calendar
    ) async throws -> OvernightData {
        try requireAuthorization()
        let timeZoneIdentifier = calendar.timeZone.identifier
        let wakeDay = calendar.startOfDay(for: night.end)
        let index = dayIndex(for: wakeDay, calendar: calendar)

        guard !isMissingNight(dayIndex: index) else {
            // §5.6 — watch not worn: no values, no segments, baselines unchanged.
            return .empty(night: night, timeZoneIdentifier: timeZoneIdentifier)
        }

        let segments = sleepSegments(
            forWakeDay: wakeDay,
            dayIndex: index,
            calendar: calendar,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let naps = napSegments(
            forWakeDay: wakeDay,
            dayIndex: index,
            calendar: calendar,
            timeZoneIdentifier: timeZoneIdentifier
        )

        return OvernightData(
            night: night,
            timeZoneIdentifier: timeZoneIdentifier,
            heartRateVariability: dailyValue(for: .heartRateVariability, dayIndex: index),
            restingHeartRate: dailyValue(for: .restingHeartRate, dayIndex: index),
            wristTemperature: configuration.recordsWristTemperature
                ? dailyValue(for: .wristTemperature, dayIndex: index)
                : nil,
            respiratoryRate: dailyValue(for: .respiratoryRate, dayIndex: index),
            oxygenSaturation: 0.96 + 0.01 * unitNoise(dayIndex: index, channel: Channel.oxygen),
            sleepSegments: segments,
            napSegments: naps,
            wristTemperatureSupported: configuration.recordsWristTemperature
        )
    }

    func fetchIntradayHeartRates(in interval: DateInterval) async throws -> [HeartRateSample] {
        try requireAuthorization()
        guard interval.duration > 0 else { return [] }
        let step = Self.intradayStepSeconds
        var samples: [HeartRateSample] = []
        samples.reserveCapacity(Int(interval.duration / step) + 1)
        var cursor = interval.start
        var tick = 0
        while cursor <= interval.end {
            let value = heartRate(at: cursor, tick: tick)
            samples.append(
                HeartRateSample(
                    timestamp: cursor,
                    beatsPerMinute: value,
                    sourceBundleIdentifier: Self.mockSourceBundleIdentifier
                )
            )
            cursor = cursor.addingTimeInterval(step)
            tick += 1
        }
        return samples
    }

    func fetchWorkouts(in interval: DateInterval) async throws -> [WorkoutSummary] {
        try requireAuthorization()
        var workouts: [WorkoutSummary] = []
        var cursor = interval.start
        let calendar = Calendar(identifier: .gregorian)
        while cursor < interval.end {
            let day = calendar.startOfDay(for: cursor)
            let index = dayIndex(for: day, calendar: calendar)
            if let workout = workout(forDayIndex: index, dayStart: day),
               interval.intersects(workout.interval) {
                workouts.append(workout)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            cursor = next
        }
        return workouts.sorted { $0.start < $1.start }
    }

    /// Deterministic vital-sign history.
    ///
    /// Every value is a smooth function of the sign's own centre plus a slow sinusoid and a
    /// stable per-day jitter, so a screenshot is reproducible and a test can assert on an
    /// exact number. Roughly one day in nine is skipped, because a real history has gaps and
    /// a screen that has never seen one will not handle one.
    func fetchVitalSamples(
        sign: VitalSign,
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [VitalSample] {
        try requireAuthorization()
        guard days > 0 else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        var samples: [VitalSample] = []
        samples.reserveCapacity(days)

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let index = Double(days - offset)
            guard Int(index) % 9 != 0 else { continue }

            let centre = Self.mockCentre(for: sign)
            let swing = centre * 0.06 * sin(index / 11.0)
            let jitter = centre * 0.02 * Self.stableJitter(sign: sign, dayIndex: Int(index))
            samples.append(VitalSample(sign: sign, dayStart: day, value: centre + swing + jitter))
        }
        return samples
    }

    /// A plausible resting centre for each sign.
    private static func mockCentre(for sign: VitalSign) -> Double {
        switch sign {
        case .restingHeartRate: return 52
        case .walkingHeartRate: return 96
        case .heartRateRecovery: return 34
        case .vo2Max: return 48
        case .heartRateVariability: return 62
        case .respiratoryRate: return 14.2
        case .oxygenSaturation: return 97.5
        case .sleepingBreathingDisturbance: return 1.4
        case .walkingSpeed: return 1.32
        case .walkingStepLength: return 74
        case .walkingAsymmetry: return 1.8
        case .walkingDoubleSupport: return 26.5
        case .walkingSteadiness: return 88
        case .stairAscentSpeed: return 0.46
        case .sixMinuteWalkDistance: return 620
        case .timeInDaylight: return 78
        case .environmentalAudioExposure: return 62
        case .headphoneAudioExposure: return 71
        }
    }

    /// A repeatable pseudo-random value in −1…1, keyed by sign and day.
    private static func stableJitter(sign: VitalSign, dayIndex: Int) -> Double {
        var hash = UInt64(truncatingIfNeeded: abs(dayIndex &* 2_654_435_761))
        for scalar in sign.rawValue.unicodeScalars {
            hash = hash &* 31 &+ UInt64(scalar.value)
        }
        return Double(hash % 2_000) / 1_000.0 - 1.0
    }

    /// A deterministic 28-day cycle with five bleeding days, so the phase estimator has
    /// something to work against without a device.
    func fetchMenstrualFlowDays(
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [MenstrualFlowDay] {
        try requireAuthorization()
        guard days > 0 else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        var result: [MenstrualFlowDay] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let dayOfCycle = offset % 28
            guard dayOfCycle < 5 else { continue }
            result.append(MenstrualFlowDay(dayStart: day, isCycleStart: dayOfCycle == 0))
        }
        return result.sorted { $0.dayStart < $1.dayStart }
    }

    func fetchObservedMaxHeartRate(
        lookbackDays: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> Double? {
        try requireAuthorization()
        guard lookbackDays > 0 else { return nil }
        return Self.observedMaxHeartRate
    }

    func enableBackgroundDelivery() async throws {
        try requireAuthorization()
    }

    func observationStream() async -> AsyncStream<HealthChangeEvent> {
        // The mock is a pull-only source: it never reports changes, so the stream finishes
        // immediately rather than hanging a consumer forever.
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stopObserving() async {}

    // MARK: - Generation

    private func requireAuthorization() throws {
        switch configuration.authorizationState {
        case .authorized: return
        case .denied: throw ZenithiumError.healthAuthorizationDenied
        case .notDetermined: throw ZenithiumError.healthAuthorizationNotDetermined
        case .unavailable: throw ZenithiumError.healthDataUnavailable
        }
    }

    private func supports(_ metric: MetricKind) -> Bool {
        metric != .wristTemperature || configuration.recordsWristTemperature
    }

    /// Days since 2000-01-01, so a value depends on the calendar date rather than on when the
    /// test runs.
    private func dayIndex(for date: Date, calendar: Calendar) -> Int {
        let epoch = Date(timeIntervalSince1970: 946_684_800)
        let days = calendar.dateComponents([.day], from: epoch, to: date).day ?? 0
        return days
    }

    private func isMissingNight(dayIndex: Int) -> Bool {
        guard configuration.missingNightFraction > 0 else { return false }
        return Self.uniform(hash(dayIndex: dayIndex, channel: Channel.presence))
            < configuration.missingNightFraction
    }

    /// The day's value for a baselined metric, drawn from a stable normal around a mean that
    /// drifts slowly and dips on a weekly rhythm.
    private func dailyValue(for metric: MetricKind, dayIndex: Int) -> Double {
        let weekly = sin(Double(dayIndex) * 2 * .pi / 7)
        let drift = sin(Double(dayIndex) * 2 * .pi / 90)
        let noise = normalNoise(dayIndex: dayIndex, channel: channel(for: metric))

        let raw: Double
        switch metric {
        case .heartRateVariability:
            raw = 58 + 7 * weekly + 4 * drift + 9 * noise
        case .restingHeartRate:
            raw = 52 - 2 * weekly - 1.2 * drift + 3 * noise
        case .wristTemperature:
            raw = 34.2 + 0.12 * weekly + 0.06 * drift + 0.22 * noise
        case .respiratoryRate:
            raw = 14.4 - 0.3 * weekly + 0.2 * drift + 0.7 * noise
        }
        let range = metric.plausibleRange
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    /// The night's segments, built from a stable start time and duration.
    private func sleepSegments(
        forWakeDay wakeDay: Date,
        dayIndex: Int,
        calendar: Calendar,
        timeZoneIdentifier: String
    ) -> [SleepSegment] {
        let startOffsetMinutes = -45.0 + 40 * normalNoise(dayIndex: dayIndex, channel: Channel.sleepStart)
        let durationHours = min(max(7.4 + 0.9 * normalNoise(dayIndex: dayIndex, channel: Channel.sleepDuration), 4.0), 10.5)

        // 23:15 local ± noise, on the evening before the wake day.
        guard let bedtimeAnchor = calendar.date(
            bySettingHour: 23, minute: 15, second: 0,
            of: wakeDay.addingTimeInterval(-TimeConversion.secondsPerDay)
        ) else {
            return []
        }
        let sleepStart = bedtimeAnchor.addingTimeInterval(startOffsetMinutes * TimeConversion.secondsPerMinute)
        let asleepSeconds = durationHours * TimeConversion.secondsPerHour
        let inBedStart = sleepStart.addingTimeInterval(-12 * TimeConversion.secondsPerMinute)
        let sleepEnd = sleepStart.addingTimeInterval(asleepSeconds)

        var segments: [SleepSegment] = [
            SleepSegment(
                interval: DateInterval(start: inBedStart, end: sleepEnd.addingTimeInterval(6 * TimeConversion.secondsPerMinute)),
                stage: .inBed,
                sourceBundleIdentifier: Self.mockSourceBundleIdentifier,
                timeZoneIdentifier: timeZoneIdentifier
            )
        ]

        guard configuration.recordsSleepStages else {
            segments.append(
                SleepSegment(
                    interval: DateInterval(start: sleepStart, end: sleepEnd),
                    stage: .asleepUnspecified,
                    sourceBundleIdentifier: Self.mockSourceBundleIdentifier,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            )
            return segments.chronological
        }

        // Five cycles of roughly 90 minutes: deep front-loaded, REM back-loaded, with one
        // short wake interruption per cycle so the contiguity tolerance is exercised
        // (ASSUMPTION SLEEP-2).
        let cycleCount = 5
        let cycleSeconds = asleepSeconds / Double(cycleCount)
        var cursor = sleepStart
        for cycle in 0..<cycleCount {
            let progress = Double(cycle) / Double(cycleCount - 1)
            let deepShare = 0.34 - 0.24 * progress
            let remShare = 0.10 + 0.26 * progress
            let wakeSeconds = 90.0 + 60 * unitNoise(dayIndex: dayIndex &+ cycle, channel: Channel.wakeBreak)
            let usable = max(cycleSeconds - wakeSeconds, 0)
            let deepSeconds = usable * deepShare
            let remSeconds = usable * remShare
            let coreSeconds = max(usable - deepSeconds - remSeconds, 0)

            for (stage, duration) in [
                (SleepStage.asleepCore, coreSeconds),
                (SleepStage.asleepDeep, deepSeconds),
                (SleepStage.asleepREM, remSeconds),
                (SleepStage.awake, wakeSeconds)
            ] where duration > 0 {
                let end = cursor.addingTimeInterval(duration)
                segments.append(
                    SleepSegment(
                        interval: DateInterval(start: cursor, end: end),
                        stage: stage,
                        sourceBundleIdentifier: Self.mockSourceBundleIdentifier,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
                cursor = end
            }
        }
        return segments.chronological
    }

    /// A nap on roughly one day in six, always ≥ 20 min so it clears the §5.2 threshold.
    private func napSegments(
        forWakeDay wakeDay: Date,
        dayIndex: Int,
        calendar: Calendar,
        timeZoneIdentifier: String
    ) -> [SleepSegment] {
        let draw = Self.uniform(hash(dayIndex: dayIndex, channel: Channel.nap))
        guard draw < 0.17 else { return [] }
        guard let napStart = calendar.date(
            bySettingHour: 14, minute: 30, second: 0,
            of: wakeDay.addingTimeInterval(-TimeConversion.secondsPerDay)
        ) else {
            return []
        }
        let minutes = 22.0 + 18 * Self.uniform(hash(dayIndex: dayIndex, channel: Channel.napLength))
        return [
            SleepSegment(
                interval: DateInterval(
                    start: napStart,
                    end: napStart.addingTimeInterval(minutes * TimeConversion.secondsPerMinute)
                ),
                stage: .asleepCore,
                sourceBundleIdentifier: Self.mockSourceBundleIdentifier,
                timeZoneIdentifier: timeZoneIdentifier
            )
        ]
    }

    /// A heart rate with a circadian shape, a workout bump in the early evening on training
    /// days, and stable per-tick noise.
    private func heartRate(at date: Date, tick: Int) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: date)
        let index = dayIndex(for: day, calendar: calendar)
        let secondsIntoDay = date.timeIntervalSince(day)
        let hour = secondsIntoDay / TimeConversion.secondsPerHour

        // Sleeping trough around 04:00, waking plateau through the day.
        let circadian = 10 * sin((hour - 10) * 2 * .pi / 24)
        let base = 62 + circadian
        let noise = 3 * normalNoise(dayIndex: index &+ tick &* 7919, channel: Channel.intraday)

        var value = base + noise
        if let window = workoutWindow(forDayIndex: index, dayStart: day),
           window.contains(date) {
            let progress = date.timeIntervalSince(window.start) / max(window.duration, 1)
            // Warm-up, plateau, cool-down.
            let shape = sin(progress * .pi)
            value += 78 * shape
        }
        return min(max(value, 38), 195)
    }

    /// The workout window for a day, on roughly one day in three.
    private func workoutWindow(forDayIndex index: Int, dayStart: Date) -> DateInterval? {
        let draw = Self.uniform(hash(dayIndex: index, channel: Channel.workoutPresence))
        guard draw < 0.36 else { return nil }
        let startHour = 17.0 + 2 * Self.uniform(hash(dayIndex: index, channel: Channel.workoutStart))
        let minutes = 38.0 + 34 * Self.uniform(hash(dayIndex: index, channel: Channel.workoutLength))
        let start = dayStart.addingTimeInterval(startHour * TimeConversion.secondsPerHour)
        return DateInterval(start: start, duration: minutes * TimeConversion.secondsPerMinute)
    }

    private func workout(forDayIndex index: Int, dayStart: Date) -> WorkoutSummary? {
        guard let window = workoutWindow(forDayIndex: index, dayStart: dayStart) else { return nil }
        let activityDraw = Self.uniform(hash(dayIndex: index, channel: Channel.workoutActivity))
        let activity = Self.rotatedActivities[
            min(Int(activityDraw * Double(Self.rotatedActivities.count)), Self.rotatedActivities.count - 1)
        ]
        let minutes = window.duration / TimeConversion.secondsPerMinute
        return WorkoutSummary(
            id: Self.stableIdentifier(dayIndex: index, channel: Channel.workoutIdentity),
            activity: activity,
            interval: window,
            activeEnergyKilocalories: minutes * 9.4,
            distanceMeters: Self.distancelessActivities.contains(activity) ? nil : minutes * 195,
            averageHeartRate: 142 + 8 * unitNoise(dayIndex: index, channel: Channel.workoutHeartRate),
            sourceBundleIdentifier: Self.mockSourceBundleIdentifier,
            // A warm late-summer block, so the heat card has something to show in previews.
            // Indoor activities carry no weather, which is also what the real data looks
            // like. Yol haritası v4, C7.
            ambientTemperatureCelsius: Self.distancelessActivities.contains(activity)
                ? nil
                : 29 + 4 * unitNoise(dayIndex: index, channel: Channel.workoutHeartRate),
            ambientHumidity: Self.distancelessActivities.contains(activity)
                ? nil
                : 0.55
        )
    }

    /// Activities the mock never attaches a distance to.
    private static let distancelessActivities: Set<WorkoutActivity> = [
        .traditionalStrengthTraining,
        .functionalStrengthTraining,
        .highIntensityIntervalTraining,
        .yoga
    ]

    // MARK: - Deterministic noise

    private enum Channel {
        static let hrv: UInt64 = 1
        static let restingHR: UInt64 = 2
        static let temperature: UInt64 = 3
        static let respiratory: UInt64 = 4
        static let presence: UInt64 = 5
        static let sleepStart: UInt64 = 6
        static let sleepDuration: UInt64 = 7
        static let wakeBreak: UInt64 = 8
        static let nap: UInt64 = 9
        static let napLength: UInt64 = 10
        static let intraday: UInt64 = 11
        static let workoutPresence: UInt64 = 12
        static let workoutStart: UInt64 = 13
        static let workoutLength: UInt64 = 14
        static let workoutActivity: UInt64 = 15
        static let workoutHeartRate: UInt64 = 16
        static let workoutIdentity: UInt64 = 17
        static let oxygen: UInt64 = 18
    }

    private func channel(for metric: MetricKind) -> UInt64 {
        switch metric {
        case .heartRateVariability: return Channel.hrv
        case .restingHeartRate: return Channel.restingHR
        case .wristTemperature: return Channel.temperature
        case .respiratoryRate: return Channel.respiratory
        }
    }

    private func hash(dayIndex: Int, channel: UInt64) -> UInt64 {
        Self.mix(seed, UInt64(bitPattern: Int64(dayIndex)), channel)
    }

    /// A standard normal draw, stable for a given (seed, day, channel).
    private func normalNoise(dayIndex: Int, channel: UInt64) -> Double {
        let u1 = max(Self.uniform(Self.mix(seed, UInt64(bitPattern: Int64(dayIndex)), channel &* 2)), 1e-12)
        let u2 = Self.uniform(Self.mix(seed, UInt64(bitPattern: Int64(dayIndex)), channel &* 2 &+ 1))
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// A stable draw in −1…1.
    private func unitNoise(dayIndex: Int, channel: UInt64) -> Double {
        Self.uniform(hash(dayIndex: dayIndex, channel: channel)) * 2 - 1
    }

    /// SplitMix64-style mixing. Pure, branch-free, and stable across platforms.
    private static func mix(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> UInt64 {
        var x = a &+ (b &* 0x9E37_79B9_7F4A_7C15) &+ (c &* 0xBF58_476D_1CE4_E5B9)
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    /// Maps a hash to 0…1 using the top 53 bits, which is the exactly representable range.
    private static func uniform(_ value: UInt64) -> Double {
        Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A stable UUID, so a re-fetch of the same day returns the same workout identity and the
    /// pipeline stays idempotent.
    private static func stableIdentifier(dayIndex: Int, channel: UInt64) -> UUID {
        let day = UInt64(bitPattern: Int64(dayIndex))
        let high = mix(0xAE01_A5A5_0000_0001, day, channel)
        let low = mix(0xAE02_5A5A_0000_0002, day, channel &+ 1)
        func byte(_ value: UInt64, _ index: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: value >> UInt64(56 - index * 8))
        }
        return UUID(uuid: (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ))
    }

    private static let rotatedActivities: [WorkoutActivity] = [
        .running, .cycling, .traditionalStrengthTraining, .rowing,
        .swimming, .highIntensityIntervalTraining, .hiking, .walking
    ]

    private static let mockSourceBundleIdentifier = "com.zenithium.mock"

    /// One sample every 30 seconds. Downstream code downsamples to 5 s spacing, so a coarser
    /// source is the honest thing to model — a real watch does not sample continuously.
    private static let intradayStepSeconds: TimeInterval = 30

    /// A plausible observed maximum for the mock profile (ASSUMPTION HRMAX-2).
    private static let observedMaxHeartRate: Double = 186
}
