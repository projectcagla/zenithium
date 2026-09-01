//
//  DataQualityEngine.swift
//  Zenithium
//
//  Epistemic data quality assessor. Evaluates sensor coverage, signal noise,
//  and baseline sufficiency before allowing physiological engines to score.
//

import Foundation

struct DataQualityAssessment: Sendable, Equatable, Codable {
    enum Grade: String, Sendable, Codable, Comparable {
        case unusable = "F"
        case degraded = "C"
        case good = "B"
        case excellent = "A"

        private var rank: Int {
            switch self {
            case .unusable: return 0
            case .degraded: return 1
            case .good: return 2
            case .excellent: return 3
            }
        }

        static func < (lhs: Grade, rhs: Grade) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    let grade: Grade
    let wearHours: Double
    let nocturnalWearHours: Double
    let hasNocturnalHRV: Bool
    let hasNocturnalRHR: Bool
    let hasWristTemperature: Bool
    let hasSleepStages: Bool
    let confidenceFactor: Double
    let missingSensors: [String]
    let qualityIssues: [String]

    var isUsableForRecovery: Bool {
        hasNocturnalHRV && hasNocturnalRHR && nocturnalWearHours >= 2.0
    }
}

enum DataQualityEngine {

    /// Minimum nocturnal wear hours needed for a trustworthy recovery score.
    static let minimumNocturnalHours: Double = 2.0
    /// Ideal nocturnal wear hours.
    static let targetNocturnalHours: Double = 7.0

    /// Assesses data quality for a single day.
    static func assess(
        overnight: OvernightData?,
        sleepSegments: [SleepSegment],
        daySamples: [HeartRateSample],
        calibration: CalibrationState
    ) -> DataQualityAssessment {
        var missing: [String] = []
        var issues: [String] = []

        let sleepSeconds = sleepSegments.asleepSeconds
        let nocturnalHours = TimeConversion.hours(fromSeconds: sleepSeconds)

        let hasHRV = (overnight?.heartRateVariability != nil)
        let hasRHR = (overnight?.restingHeartRate != nil)
        let hasTemp = (overnight?.wristTemperature != nil)
        let hasStages = sleepSegments.contains { $0.stage == .asleepDeep || $0.stage == .asleepREM }

        if !hasHRV {
            missing.append("Gece HRV (Kalp Hızı Değişkenliği)")
            issues.append("Otonom sinir sistemi dengesi için gece HRV ölçümü eksik.")
        }
        if !hasRHR {
            missing.append("Dinlenik Kalp Hızı (RHR)")
            issues.append("Kardiyovasküler toparlanma tabanı için dinlenik nabız eksik.")
        }
        if !hasTemp {
            missing.append("Bilek Sıcaklığı")
        }
        if !hasStages {
            missing.append("Uyku Evreleri (Derin/REM)")
        }

        if nocturnalHours < minimumNocturnalHours {
            issues.append("Yetersiz gece saati takma süresi (\(formatDecimal(nocturnalHours)) sa < 2,0 sa).")
        }

        // Compute wear time during the day
        let daySampleCount = daySamples.count
        let estimatedDayWearHours = min(16.0, Double(daySampleCount) * 0.1) // approximation from sample density
        let totalWearHours = min(24.0, nocturnalHours + estimatedDayWearHours)

        // Confidence calculation
        var confidence = calibration.tier.confidenceMultiplier
        if !hasHRV || !hasRHR {
            confidence *= 0.20
        }
        if nocturnalHours < 4.0 {
            confidence *= 0.60
        }
        if !hasTemp {
            confidence *= 0.90 // Slight penalty for missing temp
        }
        if !hasStages {
            confidence *= 0.90 // Slight penalty for unstaged sleep
        }

        let grade: DataQualityAssessment.Grade
        switch confidence {
        case ..<0.30:
            grade = .unusable
        case 0.30..<0.60:
            grade = .degraded
        case 0.60..<0.85:
            grade = .good
        default:
            grade = .excellent
        }

        return DataQualityAssessment(
            grade: grade,
            wearHours: totalWearHours,
            nocturnalWearHours: nocturnalHours,
            hasNocturnalHRV: hasHRV,
            hasNocturnalRHR: hasRHR,
            hasWristTemperature: hasTemp,
            hasSleepStages: hasStages,
            confidenceFactor: MathSupport.clamp(confidence, 0.0, 1.0),
            missingSensors: missing,
            qualityIssues: issues
        )
    }

    private static func formatDecimal(_ value: Double, places: Int = 1) -> String {
        let str = String(format: "%.\(places)f", value)
        return str.replacingOccurrences(of: ".", with: ",")
    }
}
