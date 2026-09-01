//
//  MetricKind.swift
//  Zenithium
//
//  The four baselined metrics. Spec §4.2.3 (σ floors), §4.2.4 (population priors), §3 (units).
//  ASSUMPTION CONST-1: taxonomy types own the numbers that define the taxonomy; EngineConstants
//  owns formula numbers and forwards here, so each value has exactly one definition site.
//

import Foundation

/// A population prior for a metric, used to blend a thin personal baseline (§4.2.4).
struct MetricPrior: Sendable, Equatable, Hashable {

    /// Population mean in the metric's canonical unit.
    let mean: Double

    /// Population standard deviation in the metric's canonical unit.
    let standardDeviation: Double
}

/// A metric that carries a 60-day EWMA baseline (§4.1).
///
/// Only these four are baselined. Sleep score is derived, not baselined; blood oxygen is
/// displayed but never scored (§3).
enum MetricKind: String, Sendable, Codable, CaseIterable, Hashable {

    /// Heart rate variability, SDNN, milliseconds.
    case heartRateVariability

    /// Resting heart rate, beats per minute.
    case restingHeartRate

    /// Sleeping wrist temperature, degrees Celsius, absolute.
    ///
    /// ASSUMPTION BASE-3: Zenithium baselines the *absolute* reading and derives `ΔT`
    /// itself, because `appleSleepingWristTemperature` is absolute on some sources and a
    /// delta on others.
    case wristTemperature

    /// Respiratory rate, breaths per minute.
    case respiratoryRate

    /// The HealthKit category this metric is read from.
    var healthDataKind: HealthDataKind {
        switch self {
        case .heartRateVariability: return .heartRateVariability
        case .restingHeartRate: return .restingHeartRate
        case .wristTemperature: return .wristTemperature
        case .respiratoryRate: return .respiratoryRate
        }
    }

    /// Spec §4.2.3 — the σ floor that prevents divide-by-tiny blow-ups.
    ///
    /// HRV 3.0 ms · RHR 1.5 bpm · Temp 0.15 °C · BR 0.30 br/min.
    var sigmaFloor: Double {
        switch self {
        case .heartRateVariability: return 3.0
        case .restingHeartRate: return 1.5
        case .wristTemperature: return 0.15
        case .respiratoryRate: return 0.30
        }
    }

    /// Spec §4.2.4 — the population prior blended in while `5 ≤ n < 14`.
    ///
    /// HRV 45 ms (σ 18) · RHR 60 bpm (σ 7) · BR 15 br/min (σ 2) · ΔT 0 °C (σ 0.35).
    ///
    /// The temperature prior is expressed on the *delta* scale, which is the scale the
    /// z-score is taken on (§5.1). Its mean is therefore 0 while the stored baseline mean
    /// tracks the absolute reading (ASSUMPTION BASE-3).
    var prior: MetricPrior {
        switch self {
        case .heartRateVariability: return MetricPrior(mean: 45.0, standardDeviation: 18.0)
        case .restingHeartRate: return MetricPrior(mean: 60.0, standardDeviation: 7.0)
        case .wristTemperature: return MetricPrior(mean: 0.0, standardDeviation: 0.35)
        case .respiratoryRate: return MetricPrior(mean: 15.0, standardDeviation: 2.0)
        }
    }

    /// Whether the scored quantity is the raw value or its deviation from the baseline mean.
    ///
    /// Only wrist temperature is scored as a deviation (`ΔT`, §3).
    var isScoredAsDeviation: Bool {
        self == .wristTemperature
    }

    /// The plausible physiological range. Values outside it are rejected on ingest before
    /// winsorization, because they are sensor artefacts rather than extreme-but-real days.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .heartRateVariability: return 1.0...400.0
        case .restingHeartRate: return 25.0...120.0
        case .wristTemperature: return 20.0...45.0
        case .respiratoryRate: return 4.0...40.0
        }
    }

    var displayName: String {
        switch self {
        case .heartRateVariability: return "HRV"
        case .restingHeartRate: return "İstirahat nabzı"
        case .wristTemperature: return "Bilek sıcaklığı"
        case .respiratoryRate: return "Solunum hızı"
        }
    }

    var accessibilityName: String {
        switch self {
        case .heartRateVariability: return "Kalp atış hızı değişkenliği"
        case .restingHeartRate: return "İstirahat kalp atış hızı"
        case .wristTemperature: return "Bilek sıcaklığı sapması"
        case .respiratoryRate: return "Solunum hızı"
        }
    }

    var unitSymbol: String {
        switch self {
        case .heartRateVariability: return CanonicalUnit.heartRateVariabilitySymbol
        case .restingHeartRate: return CanonicalUnit.heartRateSymbol
        case .wristTemperature: return CanonicalUnit.temperatureSymbol
        case .respiratoryRate: return CanonicalUnit.respiratoryRateSymbol
        }
    }

    /// Number of fraction digits to render. Kept here so every surface agrees.
    var fractionDigits: Int {
        switch self {
        case .heartRateVariability, .restingHeartRate: return 0
        case .wristTemperature: return 2
        case .respiratoryRate: return 1
        }
    }
}
