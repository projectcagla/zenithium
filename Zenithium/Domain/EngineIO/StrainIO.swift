//
//  StrainIO.swift
//  Zenithium
//
//  Strain engine input and output. Spec §5.3 in full.
//  ASSUMPTION STRAIN-1 (monotonic anchor), STRAIN-2 (gap rules), ZONE-1 (%HRR zones),
//  HRMAX-1 and HRMAX-2 (HRmax resolution).
//

import Foundation

/// How `HRmax` was arrived at, so the UI and the log can say which rule applied (§5.3).
enum MaxHeartRateSource: String, Sendable, Codable, CaseIterable, Hashable {

    /// The user entered an override in Settings.
    case userOverride

    /// The 99.5th percentile of the trailing 365 days of intraday HR (ASSUMPTION HRMAX-2).
    case observed

    /// Tanaka: `208 − 0.7 · age`.
    case tanaka

    /// Tanaka with the assumed age of 35 because no date of birth was available
    /// (ASSUMPTION HRMAX-1).
    case tanakaAssumedAge

    var displayName: String {
        switch self {
        case .userOverride: return "Senin ayarın"
        case .observed: return "Bu yıl gözlendi"
        case .tanaka: return "Yaştan tahmin edildi"
        case .tanakaAssumedAge: return "Tahmini (yaş girilmemiş)"
        }
    }

    /// Whether the UI should invite the user to improve the estimate.
    var invitesCorrection: Bool {
        self == .tanakaAssumedAge
    }
}

/// The six %HRR zones, in fixed order (ASSUMPTION ZONE-1).
///
/// The declaration order is load-bearing: `BiometricDayRecord.zoneSecondsRaw` persists zone
/// durations positionally.
enum HeartRateZone: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case zone1
    case zone2
    case zone3
    case zone4
    case zone5
    case zone6

    var id: String { rawValue }

    /// Position in the fixed order.
    var index: Int {
        switch self {
        case .zone1: return 0
        case .zone2: return 1
        case .zone3: return 2
        case .zone4: return 3
        case .zone5: return 4
        case .zone6: return 5
        }
    }

    /// The %HRR band, as a fraction of heart-rate reserve (ASSUMPTION ZONE-1).
    ///
    /// `[0–20, 20–40, 40–60, 60–80, 80–90, 90–100]`. Bands are lower-inclusive and
    /// upper-exclusive except the last, which is closed so `x = 1.0` lands in zone 6.
    var reserveRange: (lower: Double, upper: Double) {
        switch self {
        case .zone1: return (0.00, 0.20)
        case .zone2: return (0.20, 0.40)
        case .zone3: return (0.40, 0.60)
        case .zone4: return (0.60, 0.80)
        case .zone5: return (0.80, 0.90)
        case .zone6: return (0.90, 1.00)
        }
    }

    /// The zone a heart-rate reserve fraction falls in.
    static func zone(forReserveFraction fraction: Double) -> HeartRateZone {
        let clamped = min(max(fraction, 0), 1)
        for zone in HeartRateZone.allCases where clamped < zone.reserveRange.upper {
            return zone
        }
        return .zone6
    }

    var displayName: String {
        switch self {
        case .zone1: return "Bölge 1"
        case .zone2: return "Bölge 2"
        case .zone3: return "Bölge 3"
        case .zone4: return "Bölge 4"
        case .zone5: return "Bölge 5"
        case .zone6: return "Bölge 6"
        }
    }

    var effortLabel: String {
        switch self {
        case .zone1: return "Çok hafif"
        case .zone2: return "Hafif"
        case .zone3: return "Orta"
        case .zone4: return "Zor"
        case .zone5: return "Çok zor"
        case .zone6: return "Maksimal"
        }
    }
}

/// The point up to which TRIMP has already been accumulated (ASSUMPTION STRAIN-1).
///
/// Carrying an anchor is what lets a recompute extend the day forward without ever lowering
/// a value the user has already seen (§5.3).
struct StrainAnchor: Sendable, Equatable, Hashable {

    /// TRIMP accumulated from the start of the physiological day through `throughTimestamp`.
    let trimp: Double

    /// The timestamp of the last sample folded in.
    let throughTimestamp: Date

    /// Zone seconds accumulated alongside `trimp`, in `HeartRateZone` order.
    let zoneSeconds: [Double]

    init(trimp: Double, throughTimestamp: Date, zoneSeconds: [Double]) {
        self.trimp = trimp
        self.throughTimestamp = throughTimestamp
        self.zoneSeconds = zoneSeconds
    }

    /// A zeroed anchor at the start of a day.
    static func start(of dayStart: Date) -> StrainAnchor {
        StrainAnchor(
            trimp: 0,
            throughTimestamp: dayStart,
            zoneSeconds: Array(repeating: 0, count: HeartRateZone.allCases.count)
        )
    }
}

/// Everything the strain engine needs.
struct StrainInput: Sendable, Equatable {

    /// The intraday series for the physiological day, already downsampled to ≤ 1 sample / 5 s
    /// at the HealthKit boundary (§8). The engine sorts by time; it does not assume order.
    let samples: [HeartRateSample]

    /// The window the samples belong to — the physiological day (ASSUMPTION DAY-1).
    let dayWindow: DayWindow

    /// The resting-heart-rate baseline used in the HRR denominator, bpm (§5.3).
    let restingHeartRate: Double

    /// `HRmax`, bpm (§5.3).
    let maxHeartRate: Double

    /// How `maxHeartRate` was derived, for display and logging.
    let maxHeartRateSource: MaxHeartRateSource

    /// Biological sex, which selects the Banister constants `b` and `c` (§5.3).
    let biologicalSex: BiologicalSexValue

    /// Where the previous computation left off, so the recompute is incremental and
    /// monotonic (ASSUMPTION STRAIN-1). `nil` recomputes the whole day from scratch.
    let anchor: StrainAnchor?

    /// The strain value already shown to the user, which the result may never fall below
    /// (§5.3). `nil` when nothing has been shown yet.
    let previouslyReportedStrain: Double?

    /// Today's recovery score, which sets the target ceiling (§5.3). `nil` suppresses the
    /// ceiling rather than defaulting it.
    let recoveryScore: Double?

    init(
        samples: [HeartRateSample],
        dayWindow: DayWindow,
        restingHeartRate: Double,
        maxHeartRate: Double,
        maxHeartRateSource: MaxHeartRateSource,
        biologicalSex: BiologicalSexValue,
        anchor: StrainAnchor?,
        previouslyReportedStrain: Double?,
        recoveryScore: Double?
    ) {
        self.samples = samples
        self.dayWindow = dayWindow
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.maxHeartRateSource = maxHeartRateSource
        self.biologicalSex = biologicalSex
        self.anchor = anchor
        self.previouslyReportedStrain = previouslyReportedStrain
        self.recoveryScore = recoveryScore
    }
}

/// The strain engine's result.
struct StrainOutput: Sendable, Equatable {

    /// `DailyStrain = 21 · (1 − e^(−k · TRIMP))`, 0.0…21.0 (§5.3).
    let strain: Double

    /// Accumulated Banister TRIMP for the day.
    let trimp: Double

    /// The anchor to persist for the next incremental recompute.
    let anchor: StrainAnchor

    /// Seconds in each zone, in `HeartRateZone` order (ASSUMPTION ZONE-1).
    let zoneSeconds: [Double]

    /// `Ceiling = 21 · (Recovery/100)^0.65`, or `nil` when recovery is unavailable (§5.3).
    let targetCeiling: Double?

    /// Whether the computed value was raised to the previously reported one to preserve
    /// monotonicity (ASSUMPTION STRAIN-1).
    let wasClampedToPreviousValue: Bool

    /// `HRmax` actually used.
    let maxHeartRateUsed: Double

    /// How that `HRmax` was derived.
    let maxHeartRateSource: MaxHeartRateSource

    /// How many samples contributed a non-zero segment.
    let contributingSampleCount: Int

    /// How many seconds of the day were covered by gaps longer than the cut-off, so the UI
    /// can say coverage was sparse rather than implying an easy day (§5.3, ASSUMPTION STRAIN-2).
    let uncoveredSeconds: Double

    init(
        strain: Double,
        trimp: Double,
        anchor: StrainAnchor,
        zoneSeconds: [Double],
        targetCeiling: Double?,
        wasClampedToPreviousValue: Bool,
        maxHeartRateUsed: Double,
        maxHeartRateSource: MaxHeartRateSource,
        contributingSampleCount: Int,
        uncoveredSeconds: Double
    ) {
        self.strain = strain
        self.trimp = trimp
        self.anchor = anchor
        self.zoneSeconds = zoneSeconds
        self.targetCeiling = targetCeiling
        self.wasClampedToPreviousValue = wasClampedToPreviousValue
        self.maxHeartRateUsed = maxHeartRateUsed
        self.maxHeartRateSource = maxHeartRateSource
        self.contributingSampleCount = contributingSampleCount
        self.uncoveredSeconds = uncoveredSeconds
    }

    /// Seconds spent in one zone.
    func seconds(in zone: HeartRateZone) -> Double {
        guard zone.index < zoneSeconds.count else { return 0 }
        return zoneSeconds[zone.index]
    }

    /// Strain as a fraction of the target ceiling, 0…1+, for the ring gauge.
    /// `nil` when there is no ceiling to compare against.
    var ceilingProgress: Double? {
        guard let targetCeiling, targetCeiling > 0 else { return nil }
        return strain / targetCeiling
    }

    /// Whether the day has already passed its target ceiling.
    var hasExceededCeiling: Bool {
        guard let targetCeiling else { return false }
        return strain > targetCeiling
    }
}
