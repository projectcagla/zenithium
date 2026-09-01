//
//  CalibrationState.swift
//  Zenithium
//
//  Models individual baseline maturity and calibration tiers.
//  Athletes are never treated with equal certainty on Day 2 vs Day 60.
//

import Foundation

/// The maturity tier of an athlete's physiological baseline.
enum BaselineMaturityTier: Int, Sendable, Codable, Comparable, CaseIterable {
    /// 0–3 days: Initial setup. Engines must disclose population-norm assumptions.
    case coldStart = 0
    /// 4–7 days: Emerging personal baseline. High statistical variance.
    case developing = 1
    /// 8–14 days: Basic individual baseline. Recovery and strain comparisons enabled.
    case established = 2
    /// 15–28 days: Mature individual baseline. Circadian and multi-week trends active.
    case mature = 3
    /// 29+ days: Fully anchored individualized athletic intelligence.
    case robust = 4

    static func < (lhs: BaselineMaturityTier, rhs: BaselineMaturityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .coldStart: return "İlk Kalibrasyon (0-3 Gün)"
        case .developing: return "Gelişen Taban (4-7 Gün)"
        case .established: return "Temel Kalibrasyon (8-14 Gün)"
        case .mature: return "Olgun Taban (15-28 Gün)"
        case .robust: return "Tam Bireysel Kalibrasyon (29+ Gün)"
        }
    }

    var confidenceMultiplier: Double {
        switch self {
        case .coldStart: return 0.30
        case .developing: return 0.60
        case .established: return 0.85
        case .mature: return 0.95
        case .robust: return 1.00
        }
    }
}

/// The calibration state of the platform for a specific day.
struct CalibrationState: Sendable, Equatable, Codable {
    let recordedDaysCount: Int
    let tier: BaselineMaturityTier
    let hasHRVBaseline: Bool
    let hasRHRBaseline: Bool
    let hasWristTemperatureBaseline: Bool
    let hasSleepBaseline: Bool

    init(
        recordedDaysCount: Int,
        hasHRVBaseline: Bool = true,
        hasRHRBaseline: Bool = true,
        hasWristTemperatureBaseline: Bool = false,
        hasSleepBaseline: Bool = true
    ) {
        self.recordedDaysCount = max(0, recordedDaysCount)
        self.hasHRVBaseline = hasHRVBaseline
        self.hasRHRBaseline = hasRHRBaseline
        self.hasWristTemperatureBaseline = hasWristTemperatureBaseline
        self.hasSleepBaseline = hasSleepBaseline

        switch self.recordedDaysCount {
        case 0...3:
            self.tier = .coldStart
        case 4...7:
            self.tier = .developing
        case 8...14:
            self.tier = .established
        case 15...28:
            self.tier = .mature
        default:
            self.tier = .robust
        }
    }

    var summaryDescription: String {
        switch tier {
        case .coldStart:
            return "Taban çizgisi oluşturuluyor (\(recordedDaysCount)/4 gün). Kararlar genel normlara dayanmaktadır."
        case .developing:
            return "Bireysel taban çizgisi şekilleniyor (\(recordedDaysCount)/8 gün)."
        case .established:
            return "Kişisel taban çizgisi devrede (\(recordedDaysCount) gün kayıtlı)."
        case .mature:
            return "Olgun biyometrik profil (\(recordedDaysCount) gün)."
        case .robust:
            return "Yüksek hassasiyetli bireysel kalibrasyon (\(recordedDaysCount) gün)."
        }
    }
}
