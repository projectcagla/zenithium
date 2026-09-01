//
//  TrainingLens.swift
//  Zenithium
//
//  Mercek — kullanıcının hangi tür antrenman yaptığı.
//
//  ASSUMPTION LENS-1: mercek *motoru* değiştirmez, yalnızca hangi ekranın öne çıktığını ve
//  uygulamanın hangi dili konuştuğunu değiştirir. Recovery, Strain ve Sleep dört mercekte de
//  aynı sayıyı üretir — zorlanma kalp atışından geliyor, o yüzden stresli bir toplantı da
//  sled push da aynı ölçeğe düşer. Merceği motora karıştırmak bu evrenselliği bozardı.
//

import Foundation

enum TrainingLens: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// Koşu, bisiklet, yüzme, triatlon.
    case endurance

    /// Hyrox, CrossFit, fonksiyonel fitness — karma modal.
    case hybrid

    /// Hipertrofi, powerlifting, genel kuvvet.
    case strength

    /// Antrenman yapmayan, sağlığını takip eden.
    case health

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .endurance: return "Dayanıklılık"
        case .hybrid: return "Hibrit"
        case .strength: return "Kuvvet"
        case .health: return "Sağlık"
        }
    }

    var subtitle: String {
        switch self {
        case .endurance: return "Koşu, bisiklet, yüzme"
        case .hybrid: return "Hyrox, CrossFit, fonksiyonel"
        case .strength: return "Hipertrofi, powerlifting"
        case .health: return "Antrenman değil, sağlık takibi"
        }
    }

    var accessibilityName: String {
        switch self {
        case .endurance: return "Dayanıklılık antrenmanı"
        case .hybrid: return "Hibrit antrenman"
        case .strength: return "Kuvvet antrenmanı"
        case .health: return "Sağlık takibi"
        }
    }

    /// The SF Symbol used where a template image is required — the tab bar, and anywhere
    /// the system renders the icon rather than the app.
    ///
    /// The lens picker draws `LensMark` instead. That is the one screen where the choice of
    /// lens is the subject rather than a label, and it is worth the app's own marks there;
    /// everywhere else a stock symbol is the right neighbour for the stock symbols beside it.
    /// Yol haritası v4, B9.
    var symbolName: String {
        switch self {
        case .endurance: return "figure.run"
        case .hybrid: return "figure.mixed.cardio"
        case .strength: return "figure.strengthtraining.traditional"
        case .health: return "heart.text.square"
        }
    }

    /// Bu merceğin zorlanma tavanını öne çıkarıp çıkarmadığı.
    ///
    /// Sağlık merceği için "bugün ne kadar zorlanmalısın" sorusu anlamsız; o kullanıcı
    /// antrenman yapmıyor. Tavanı göstermek, cevaplamadığı bir soruyu sormak olurdu.
    var showsStrainCeiling: Bool {
        self != .health
    }

    /// Bu merceğin bir antrenman reçetesi bekleyip beklemediği.
    var expectsPrescription: Bool {
        self != .health
    }

    /// Sekme çubuğundaki ikinci sekme.
    ///
    /// Kullanıcının seanslar arasında açtığı ekran disipline göre değişir: dayanıklılıkta
    /// biriken yük, kuvvette hangi kasların geri geldiği, sağlık merceğinde ise hiçbiri —
    /// orada asıl soru vücudun genel gidişatı.
    var secondaryTab: SecondaryTab {
        switch self {
        case .endurance, .hybrid: return .load
        case .strength: return .muscles
        case .health: return .vitals
        }
    }

    /// Ana ekranın altındaki veri satırlarında hangi metrikler öne çıkar.
    var featuredMetrics: [FeaturedMetric] {
        switch self {
        case .endurance:
            return [.heartRateVariability, .restingHeartRate, .acuteChronicRatio, .bestTrainingHour]
        case .hybrid:
            return [.heartRateVariability, .compromisedRunning, .posteriorChain, .grip]
        case .strength:
            return [.heartRateVariability, .weeklyVolume, .pushPullBalance, .restingHeartRate]
        case .health:
            return [.sleepConsistency, .daylight, .walkingSpeed, .vo2Max]
        }
    }
}

/// Ana ekranın veri satırlarında görünebilecek metrikler.
///
/// Mercek hangi dördünü seçeceğine karar verir; her biri kendi ekranını nasıl dolduracağını
/// bilir. Böylece yeni bir mercek eklemek yeni bir ekran yazmak değil, bir liste seçmek olur.
enum FeaturedMetric: String, Sendable, CaseIterable, Hashable {
    case heartRateVariability
    case restingHeartRate
    case acuteChronicRatio
    case bestTrainingHour
    case compromisedRunning
    case posteriorChain
    case grip
    case weeklyVolume
    case pushPullBalance
    case sleepConsistency
    case daylight
    case walkingSpeed
    case vo2Max

    var displayName: String {
        switch self {
        case .heartRateVariability: return "HRV"
        case .restingHeartRate: return "Dinlenme nabzı"
        case .acuteChronicRatio: return "Akut : kronik"
        case .bestTrainingHour: return "En iyi saat"
        case .compromisedRunning: return "Kompanse koşu"
        case .posteriorChain: return "Posterior zincir"
        case .grip: return "Kavrama"
        case .weeklyVolume: return "Haftalık hacim"
        case .pushPullBalance: return "İtme : çekme"
        case .sleepConsistency: return "Uyku tutarlılığı"
        case .daylight: return "Gün ışığı"
        case .walkingSpeed: return "Yürüme hızı"
        case .vo2Max: return "VO₂max"
        }
    }

    /// The name VoiceOver reads, spelled out where the visible label is an abbreviation.
    ///
    /// Turkish, like every other string the app says. This table shipped in English through
    /// v0.1's release scan: a Turkish app whose visible labels read "HRV" and whose spoken
    /// labels read "Heart rate variability" is not localized, it is half-translated, and the
    /// half nobody sees is the half a screen-reader user gets.
    var accessibilityName: String {
        switch self {
        case .heartRateVariability: return "Kalp atış hızı değişkenliği"
        case .restingHeartRate: return "Dinlenme nabzı"
        case .acuteChronicRatio: return "Akut kronik yük oranı"
        case .bestTrainingHour: return "En iyi antrenman saati"
        case .compromisedRunning: return "Yorgun koşu puanı"
        case .posteriorChain: return "Arka zincir hazırlığı"
        case .grip: return "Kavrama hazırlığı"
        case .weeklyVolume: return "Haftalık antrenman hacmi"
        case .pushPullBalance: return "İtme çekme dengesi"
        case .sleepConsistency: return "Uyku düzeni"
        case .daylight: return "Gün ışığında geçen süre"
        case .walkingSpeed: return "Yürüme hızı"
        case .vo2Max: return "Maksimal oksijen kullanımı"
        }
    }
}


/// Merceğin seçtiği ikinci sekme.
enum SecondaryTab: String, Sendable, Hashable, CaseIterable {
    case load
    case muscles
    case vitals
}
