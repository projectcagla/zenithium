//
//  VitalSign.swift
//  Zenithium
//
//  The signals Apple Watch records and nothing collects. Faz 11.
//
//  These are deliberately kept *out* of `MetricKind`. That enum is the four inputs the
//  recovery score is built from, and every one of them carries a spec-defined weight, prior
//  and sigma floor. Adding VO₂max to it would imply VO₂max scores recovery, which it does
//  not. A vital sign is something Zenithium shows and trends; a metric is something it
//  scores with. Keeping the two types apart keeps that distinction enforceable.
//
//  §12 governs the whole file. Several of these — atrial fibrillation burden, walking
//  steadiness — are clinical measures. Zenithium displays them and their trend, names their
//  own published bands where Apple publishes one, and stops. It does not interpret.
//

import Foundation

/// Which direction of change is worth noticing.
///
/// Not "good" and "bad" — §12 forbids the verdict. This exists so the deviation engine can
/// say *which way* a signal moved relative to its own baseline, which the user can read
/// against their own situation.
enum VitalPolarity: String, Sendable, Hashable {

    /// Higher readings usually accompany better aerobic condition (VO₂max, HR recovery).
    case higherIsFitter

    /// Lower readings usually accompany better aerobic condition (resting HR, walking HR).
    case lowerIsFitter

    /// Neither direction carries a general meaning; only the deviation does.
    case neutral
}

/// Which group a vital sign belongs to on the screen.
enum VitalCategory: String, Sendable, Hashable, CaseIterable {
    case cardio
    case respiratory
    case mobility
    case environment

    var displayName: String {
        switch self {
        case .cardio: return "Kalp ve dolaşım"
        case .respiratory: return "Solunum ve uyku"
        case .mobility: return "Hareket kalitesi"
        case .environment: return "Çevre ve maruziyet"
        }
    }

    var order: Int {
        switch self {
        case .cardio: return 0
        case .respiratory: return 1
        case .mobility: return 2
        case .environment: return 3
        }
    }
}

/// One tracked vital sign.
enum VitalSign: String, Sendable, Hashable, CaseIterable, Identifiable {

    // Cardio
    case restingHeartRate
    case walkingHeartRate
    case heartRateRecovery
    case vo2Max
    case heartRateVariability

    // Respiratory and sleep
    case respiratoryRate
    case oxygenSaturation
    case sleepingBreathingDisturbance

    // Mobility
    case walkingSpeed
    case walkingStepLength
    case walkingAsymmetry
    case walkingDoubleSupport
    case walkingSteadiness
    case stairAscentSpeed
    case sixMinuteWalkDistance

    // Environment
    case timeInDaylight
    case environmentalAudioExposure
    case headphoneAudioExposure

    var id: String { rawValue }

    var category: VitalCategory {
        switch self {
        case .restingHeartRate, .walkingHeartRate, .heartRateRecovery, .vo2Max, .heartRateVariability:
            return .cardio
        case .respiratoryRate, .oxygenSaturation, .sleepingBreathingDisturbance:
            return .respiratory
        case .walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport,
             .walkingSteadiness, .stairAscentSpeed, .sixMinuteWalkDistance:
            return .mobility
        case .timeInDaylight, .environmentalAudioExposure, .headphoneAudioExposure:
            return .environment
        }
    }

    var displayName: String {
        switch self {
        case .restingHeartRate: return "İstirahat nabzı"
        case .walkingHeartRate: return "Yürüyüş nabzı"
        case .heartRateRecovery: return "Nabız toparlanması"
        case .vo2Max: return "VO₂max"
        case .heartRateVariability: return "HRV"
        case .respiratoryRate: return "Solunum hızı"
        case .oxygenSaturation: return "Kandaki oksijen"
        case .sleepingBreathingDisturbance: return "Uykuda solunum bozulması"
        case .walkingSpeed: return "Yürüme hızı"
        case .walkingStepLength: return "Adım uzunluğu"
        case .walkingAsymmetry: return "Yürüyüş asimetrisi"
        case .walkingDoubleSupport: return "Çift destek süresi"
        case .walkingSteadiness: return "Yürüme dengesi"
        case .stairAscentSpeed: return "Merdiven çıkış hızı"
        case .sixMinuteWalkDistance: return "6 dakika yürüme mesafesi"
        case .timeInDaylight: return "Gün ışığında geçen süre"
        case .environmentalAudioExposure: return "Ortam ses maruziyeti"
        case .headphoneAudioExposure: return "Kulaklık ses maruziyeti"
        }
    }

    /// What the number is for, in one line. Shown under the value, because half of these
    /// are signals nobody has been told the meaning of.
    var explanation: String {
        switch self {
        case .restingHeartRate:
            return "Dinlenirken kalbinin dakikadaki atış sayısı. Kondisyon ve toparlanmanın en sessiz göstergesi."
        case .walkingHeartRate:
            return "Düz yürürken kalbinin ortalama hızı. Aynı tempoda düşmesi, aerobik kapasitenin arttığı anlamına gelir."
        case .heartRateRecovery:
            return "Antrenman bittikten bir dakika sonra nabzının kaç atım düştüğü. Aerobik kapasitenin tek başına en iyi göstergelerinden."
        case .vo2Max:
            return "Vücudunun dakikada kullanabildiği oksijen miktarı. Uzun vadeli kondisyonun ana ölçüsü."
        case .heartRateVariability:
            return "Atışlar arasındaki sürenin değişkenliği. Otonom sinir sisteminin dinlenik durumunu yansıtır."
        case .respiratoryRate:
            return "Uykuda dakikadaki nefes sayın. Taban çizginden sapması genelde başka sinyallerle birlikte gelir."
        case .oxygenSaturation:
            return "Kanındaki oksijen doygunluğu."
        case .sleepingBreathingDisturbance:
            return "Uykuda solunumunun bölünme sıklığı. Yalnızca gösterilir."
        case .walkingSpeed:
            return "Düz zeminde alışılmış yürüme hızın. Fonksiyonel kapasitenin en erken göstergelerinden."
        case .walkingStepLength:
            return "Ortalama adım uzunluğun."
        case .walkingAsymmetry:
            return "Adımlarının sağ ve sol arasındaki fark oranı."
        case .walkingDoubleSupport:
            return "Yürürken iki ayağının aynı anda yerde olduğu sürenin oranı."
        case .walkingSteadiness:
            return "Apple'ın yürüyüş dengesi ölçüsü. Yalnızca gösterilir."
        case .stairAscentSpeed:
            return "Merdiven çıkarken dikey hızın. Bacak gücü ve kardiyo kapasitesinin birlikte göstergesi."
        case .sixMinuteWalkDistance:
            return "Altı dakikada yürüyebileceğin tahmini mesafe. Klinikte kullanılan bir standart."
        case .timeInDaylight:
            return "Gün ışığında geçirdiğin süre. Işık, sirkadiyen ritmin en güçlü ayarlayıcısı."
        case .environmentalAudioExposure:
            return "Çevrendeki sesin ortalama düzeyi."
        case .headphoneAudioExposure:
            return "Kulaklıktan gelen sesin ortalama düzeyi."
        }
    }

    var unitSymbol: String {
        switch self {
        case .restingHeartRate, .walkingHeartRate, .heartRateRecovery: return "bpm"
        case .vo2Max: return "mL/kg·dk"
        case .heartRateVariability: return "ms"
        case .respiratoryRate: return "sol/dk"
        case .oxygenSaturation, .walkingAsymmetry, .walkingDoubleSupport, .walkingSteadiness: return "%"
        case .sleepingBreathingDisturbance: return ""
        case .walkingSpeed: return "m/sn"
        case .walkingStepLength: return "cm"
        case .stairAscentSpeed: return "m/sn"
        case .sixMinuteWalkDistance: return "m"
        case .timeInDaylight: return "dk"
        case .environmentalAudioExposure, .headphoneAudioExposure: return "dB"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .restingHeartRate, .walkingHeartRate, .heartRateRecovery, .respiratoryRate,
             .sixMinuteWalkDistance, .timeInDaylight, .environmentalAudioExposure,
             .headphoneAudioExposure, .walkingStepLength:
            return 0
        case .vo2Max, .heartRateVariability, .oxygenSaturation, .walkingAsymmetry,
             .walkingDoubleSupport, .walkingSteadiness, .sleepingBreathingDisturbance:
            return 1
        case .walkingSpeed, .stairAscentSpeed:
            return 2
        }
    }

    var polarity: VitalPolarity {
        switch self {
        case .vo2Max, .heartRateRecovery, .heartRateVariability, .walkingSpeed,
             .stairAscentSpeed, .sixMinuteWalkDistance, .walkingSteadiness,
             .walkingStepLength, .oxygenSaturation, .timeInDaylight:
            return .higherIsFitter
        case .restingHeartRate, .walkingHeartRate, .walkingAsymmetry, .walkingDoubleSupport,
             .respiratoryRate, .sleepingBreathingDisturbance, .environmentalAudioExposure,
             .headphoneAudioExposure:
            return .lowerIsFitter
        }
    }

    /// Whether this sign feeds the multivariate deviation score (Faz 28).
    ///
    /// Only the four that move together on a disturbed night. Mobility and environment
    /// signals change over months, so folding them into a same-morning anomaly score would
    /// add noise, not signal.
    var participatesInDeviationScore: Bool {
        switch self {
        case .restingHeartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation:
            return true
        default:
            return false
        }
    }

    /// How many days of history the trend chart shows.
    var trendWindowDays: Int {
        switch category {
        case .cardio, .respiratory: return 90
        case .mobility, .environment: return 180
        }
    }

    /// Signals Zenithium is only permitted to display, never to characterise (§12).
    var isDisplayOnly: Bool {
        switch self {
        case .walkingSteadiness, .sleepingBreathingDisturbance, .oxygenSaturation:
            return true
        default:
            return false
        }
    }
}
