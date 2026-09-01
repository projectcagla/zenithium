//
//  CorrelationIO.swift
//  Zenithium
//
//  Korelasyon motorunun girdi ve çıktısı.
//
//  Kural (yol haritası, değişmeyecek kural 5): **korelasyon nedensellik değildir.** Bu
//  tiplerin hiçbiri "sebep" kelimesini taşımaz ve arayüz de taşımayacak. Motor "şunu
//  kaydettiğin gecelerde ölçüm şu kadar farklıydı" der; "şu, şuna sebep oluyor" demez.
//

import Foundation

/// Bir davranışın karşılaştırıldığı ölçüm.
enum CorrelationOutcome: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case recovery
    case sleepScore
    case sleepDuration
    case restingHeartRate
    case heartRateVariability

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recovery: return "Toparlanma"
        case .sleepScore: return "Uyku puanı"
        case .sleepDuration: return "Uyku süresi"
        case .restingHeartRate: return "Dinlenme nabzı"
        case .heartRateVariability: return "HRV"
        }
    }

    var unitSymbol: String {
        switch self {
        case .recovery, .sleepScore: return "puan"
        case .sleepDuration: return "sa"
        case .restingHeartRate: return "bpm"
        case .heartRateVariability: return "ms"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .recovery, .sleepScore, .restingHeartRate, .heartRateVariability: return 0
        case .sleepDuration: return 1
        }
    }

    /// Bu ölçümde artışın iyi olup olmadığı.
    ///
    /// Yalnızca okun yönünü çizmek için — metinde "iyi" ya da "kötü" kelimesi geçmez.
    var higherIsBetter: Bool {
        self != .restingHeartRate
    }
}

/// Tek bir gözlem: davranış kaydedildi mi, ve o geceye ait ölçüm ne çıktı.
struct CorrelationObservation: Sendable, Equatable {
    let behaviorLogged: Bool
    let value: Double
}

/// Etki büyüklüğünün sözel karşılığı (Cohen).
enum EffectMagnitude: String, Sendable, Equatable, Hashable {
    case negligible
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .negligible: return "çok küçük"
        case .small: return "küçük"
        case .medium: return "orta"
        case .large: return "büyük"
        }
    }

    /// |d| eşikleri — Cohen'in klasik sınırları.
    static func magnitude(forCohensD d: Double) -> EffectMagnitude {
        let magnitude = abs(d)
        if magnitude < 0.2 { return .negligible }
        if magnitude < 0.5 { return .small }
        if magnitude < 0.8 { return .medium }
        return .large
    }
}

/// Bir davranış–ölçüm çiftinin sonucu.
/// What a correlation is about.
///
/// Journal behaviours are yes-or-no on a given night — you drank or you did not. A
/// supplement is a course: it starts, it runs, it may stop. Both reduce to the same
/// question the engine already answers — how did the nights with it differ from the nights
/// without — so both live behind one type rather than in two parallel engines.
/// Yol haritası v4, C5.
enum CorrelationSubject: Sendable, Equatable, Hashable, Identifiable {

    case behavior(JournalBehavior)

    /// A supplement or medication the person is taking, by their own name for it.
    case supplement(String)

    var id: String { key }

    /// A stable identifier, used for `CorrelationResult.id`.
    var key: String {
        switch self {
        case .behavior(let behavior): return "behavior.\(behavior.rawValue)"
        case .supplement(let name): return "supplement.\(name.lowercased())"
        }
    }

    var displayName: String {
        switch self {
        case .behavior(let behavior): return behavior.displayName
        case .supplement(let name): return name
        }
    }

    var accessibilityName: String {
        switch self {
        case .behavior(let behavior): return behavior.accessibilityName
        case .supplement(let name): return name
        }
    }

    var symbolName: String {
        switch self {
        case .behavior(let behavior): return behavior.symbolName
        case .supplement: return "pills"
        }
    }

    /// The behaviour this is about, when it is one.
    var behavior: JournalBehavior? {
        if case .behavior(let behavior) = self { return behavior }
        return nil
    }
}

struct CorrelationResult: Sendable, Equatable, Hashable, Identifiable {

    let subject: CorrelationSubject
    let outcome: CorrelationOutcome

    /// Davranışın kaydedildiği gecelerin ortalaması.
    let meanWithBehavior: Double

    /// Kaydedilmediği gecelerin ortalaması.
    let meanWithoutBehavior: Double

    /// Fark = kaydedildi − kaydedilmedi. İşaret anlamlı: negatif, ölçümün daha düşük olduğu.
    let difference: Double

    /// Farkın %95 güven aralığı (Welch standart hatası, normal yaklaşımı).
    let confidenceLower: Double
    let confidenceUpper: Double

    /// Cohen'in d'si — havuzlanmış standart sapmaya göre etki büyüklüğü.
    let cohensD: Double

    let sampleWithBehavior: Int
    let sampleWithoutBehavior: Int

    var id: String { "\(subject.key)-\(outcome.rawValue)" }

    /// The behaviour this result is about, when it is a behaviour rather than a supplement.
    var behavior: JournalBehavior? { subject.behavior }

    var totalSample: Int { sampleWithBehavior + sampleWithoutBehavior }

    var magnitude: EffectMagnitude { EffectMagnitude.magnitude(forCohensD: cohensD) }

    /// Güven aralığı sıfırı dışlıyor mu.
    ///
    /// Dışlıyorsa fark tutarlı; dışlamıyorsa "henüz net değil" denir — "etki yok" değil.
    /// İkisi farklı şeyler ve karıştırmak yanlış olur.
    var isConsistent: Bool {
        (confidenceLower > 0 && confidenceUpper > 0) || (confidenceLower < 0 && confidenceUpper < 0)
    }

    /// Ölçüm bu davranışla birlikte kullanıcının lehine mi hareket etmiş.
    ///
    /// Yalnızca ok yönü içindir. Metin bunu "iyi"ye çevirmez.
    var movesUpward: Bool {
        outcome.higherIsBetter ? difference > 0 : difference < 0
    }
}
