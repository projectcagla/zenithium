//
//  ECGRecord.swift
//  Zenithium
//
//  Domain model representing an Apple Watch ECG recording.
//  Preserves exact Apple HealthKit classification and metrics without re-interpretation. Spec §12.
//

import Foundation

/// Mirrors Apple's `HKElectrocardiogram.Classification` with exact official Turkish terminology.
enum ECGClassification: String, Sendable, Codable, CaseIterable {
    case notSet = "notSet"
    case sinusRhythm = "sinusRhythm"
    case atrialFibrillation = "atrialFibrillation"
    case inconclusiveLowHeartRate = "inconclusiveLowHeartRate"
    case inconclusiveHighHeartRate = "inconclusiveHighHeartRate"
    case inconclusivePoorReading = "inconclusivePoorReading"
    case inconclusiveOther = "inconclusiveOther"
    case unrecognized = "unrecognized"

    var displayName: String {
        switch self {
        case .notSet: return "Belirlenmedi"
        case .sinusRhythm: return "Sinüs Ritmi"
        case .atrialFibrillation: return "Atriyal Fibrilasyon"
        case .inconclusiveLowHeartRate: return "Belirsiz: Düşük Kalp Atış Hızı"
        case .inconclusiveHighHeartRate: return "Belirsiz: Yüksek Kalp Atış Hızı"
        case .inconclusivePoorReading: return "Belirsiz: Zayıf Kayıt"
        case .inconclusiveOther: return "Belirsiz: Diğer"
        case .unrecognized: return "Tanınmayan Ritim"
        }
    }
}

/// A single ECG recording imported from Apple Health.
struct ECGRecord: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    let recordedAt: Date
    let classification: ECGClassification
    let averageHeartRate: Double?
    let symptomsStatus: String?
    let sourceName: String

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        classification: ECGClassification,
        averageHeartRate: Double? = nil,
        symptomsStatus: String? = nil,
        sourceName: String = "Apple Watch"
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.classification = classification
        self.averageHeartRate = averageHeartRate
        self.symptomsStatus = symptomsStatus
        self.sourceName = sourceName
    }
}
