//
//  CorrelationEngine.swift
//  Zenithium
//
//  Davranış–ölçüm karşılaştırması. Saf, Foundation-only, deterministik.
//
//  Yaklaşım kasıtlı olarak basit ve savunulabilir: iki grup ortalaması, Welch standart
//  hatasıyla bir güven aralığı, ve Cohen'in d'si. Regresyon ya da çok değişkenli model
//  kurmuyoruz — çünkü elimizdeki n bunu taşımaz ve taşıyormuş gibi yapmak, kullanıcıya
//  hak etmediği bir kesinlik satmak olur.
//
//  ASSUMPTION CORR-1: güven aralığı normal yaklaşımı (z = 1.96) kullanıyor, t dağılımı
//  değil. Gruplar 5'in altındaysa sonuç hiç üretilmiyor; 5–10 aralığında normal yaklaşımı
//  aralığı bir miktar dar tahmin eder. Bunu telafi etmek için minimum örneklem 5 yerine 6
//  tutuluyor ve arayüz gözlem sayısını her zaman gösteriyor, böylece kullanıcı ne kadar
//  veriye baktığını görebiliyor.
//

import Foundation

enum CorrelationEngine {

    /// Bir grubun sonuç üretmesi için gereken en az gece sayısı.
    ///
    /// Altı, "istatistiksel olarak yeterli" olduğu için değil, altının altında *hiçbir*
    /// yorumun dürüst olmadığı için seçildi.
    static let minimumSamplesPerGroup = 6

    /// %95 için normal yaklaşımı katsayısı (ASSUMPTION CORR-1).
    static let confidenceZ = 1.96

    /// Tek bir davranış–ölçüm çiftini değerlendirir.
    ///
    /// Herhangi bir grup eşiğin altındaysa `nil` döner — "etki bulunamadı" değil,
    /// "henüz konuşacak kadar veri yok". Arayüz ikisini farklı gösterir.
    static func analyse(
        behavior: JournalBehavior,
        outcome: CorrelationOutcome,
        observations: [CorrelationObservation]
    ) -> CorrelationResult? {
        analyse(subject: .behavior(behavior), outcome: outcome, observations: observations)
    }

    /// The same comparison for any subject — a journal behaviour or a supplement course.
    static func analyse(
        subject: CorrelationSubject,
        outcome: CorrelationOutcome,
        observations: [CorrelationObservation]
    ) -> CorrelationResult? {

        let withBehavior = observations.filter(\.behaviorLogged).map(\.value)
        let withoutBehavior = observations.filter { !$0.behaviorLogged }.map(\.value)

        guard withBehavior.count >= minimumSamplesPerGroup,
              withoutBehavior.count >= minimumSamplesPerGroup else {
            return nil
        }

        guard let meanWith = MathSupport.mean(withBehavior),
              let meanWithout = MathSupport.mean(withoutBehavior),
              let varianceWith = MathSupport.sampleVariance(withBehavior),
              let varianceWithout = MathSupport.sampleVariance(withoutBehavior) else {
            return nil
        }

        let n1 = Double(withBehavior.count)
        let n2 = Double(withoutBehavior.count)
        let difference = meanWith - meanWithout

        // Welch standart hatası — grupların varyansları eşit varsayılmıyor, ki gerçekte
        // eşit olmaları için bir sebep yok.
        let standardError = (varianceWith / n1 + varianceWithout / n2).squareRoot()
        let margin = confidenceZ * standardError

        // Cohen'in d'si, havuzlanmış standart sapmaya göre.
        let pooledVariance = ((n1 - 1) * varianceWith + (n2 - 1) * varianceWithout) / (n1 + n2 - 2)
        let pooledDeviation = pooledVariance > 0 ? pooledVariance.squareRoot() : 0
        let cohensD = pooledDeviation > 0 ? difference / pooledDeviation : 0

        guard difference.isFinite, standardError.isFinite, cohensD.isFinite else { return nil }

        return CorrelationResult(
            subject: subject,
            outcome: outcome,
            meanWithBehavior: meanWith,
            meanWithoutBehavior: meanWithout,
            difference: difference,
            confidenceLower: difference - margin,
            confidenceUpper: difference + margin,
            cohensD: cohensD,
            sampleWithBehavior: withBehavior.count,
            sampleWithoutBehavior: withoutBehavior.count
        )
    }

    /// Bir ölçüm için tüm davranışları değerlendirir ve etkiye göre sıralar.
    ///
    /// Sıralama |Cohen d|'ye göre, tutarlı olanlar önce. Kullanıcı önce "gerçekten bir şey
    /// var" diyebileceğimiz satırları görür.
    static func rank(
        outcome: CorrelationOutcome,
        observationsByBehavior: [JournalBehavior: [CorrelationObservation]]
    ) -> [CorrelationResult] {
        rank(
            outcome: outcome,
            observationsBySubject: Dictionary(
                uniqueKeysWithValues: observationsByBehavior.map { (CorrelationSubject.behavior($0.key), $0.value) }
            )
        )
    }

    /// Rank every subject by how consistent and how large its effect is.
    static func rank(
        outcome: CorrelationOutcome,
        observationsBySubject: [CorrelationSubject: [CorrelationObservation]]
    ) -> [CorrelationResult] {
        let results = observationsBySubject.compactMap { subject, observations in
            analyse(subject: subject, outcome: outcome, observations: observations)
        }
        return results.sorted { lhs, rhs in
            if lhs.isConsistent != rhs.isConsistent { return lhs.isConsistent }
            return abs(lhs.cohensD) > abs(rhs.cohensD)
        }
    }

    /// Bir davranışın hangi ölçümde en güçlü izi bıraktığını bulur.
    static func strongestOutcome(
        for behavior: JournalBehavior,
        observationsByOutcome: [CorrelationOutcome: [CorrelationObservation]]
    ) -> CorrelationResult? {
        observationsByOutcome
            .compactMap { outcome, observations in
                analyse(behavior: behavior, outcome: outcome, observations: observations)
            }
            .filter(\.isConsistent)
            .max { abs($0.cohensD) < abs($1.cohensD) }
    }

    /// Sonucun tek cümlelik özeti.
    ///
    /// Dil kuralı: gözlem bildirilir, sebep iddia edilmez. Cümlede her zaman gözlem sayısı
    /// geçer, çünkü kullanıcının bunun ne kadar veriye dayandığını görmesi gerekir.
    static func summary(for result: CorrelationResult) -> String {
        let digits = result.outcome.fractionDigits
        let magnitude = abs(result.difference)
        let formatted = MathSupport.rounded(magnitude, places: digits)
        let direction = result.difference < 0 ? "düşük" : "yüksek"
        let unit = result.outcome.unitSymbol

        let head = "\(result.subject.displayName) kaydettiğin \(result.sampleWithBehavior) gecede "
            + "\(result.outcome.displayName.lowercased()) ortalama "
            + "\(formattedNumber(formatted, digits: digits)) \(unit) \(direction) çıktı"

        if result.isConsistent {
            return head + " (\(result.totalSample) gözlem)."
        }
        return head + ", ama fark henüz net değil (\(result.totalSample) gözlem)."
    }

    /// A decimal number in the sentence this engine builds, written the Turkish way.
    ///
    /// The same comma `ZenithiumFormat.decimal` writes. Duplicated rather than shared because
    /// `ZenithiumFormat` lives in the design system and §2.1's dependency runs the other way:
    /// an engine cannot reach a view. Two lines is the cost of that rule holding.
    private static func formattedNumber(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(max(0, digits))f", value)
            .replacingOccurrences(of: ".", with: ",")
    }
}
