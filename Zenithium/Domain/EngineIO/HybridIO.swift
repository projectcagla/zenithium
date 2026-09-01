//
//  HybridIO.swift
//  Zenithium
//
//  Hibrit motorun girdi ve çıktısı.
//

import Foundation

struct HybridSessionInput: Sendable, Equatable {

    let segments: [HybridSegment]

    /// Sporcunun taze tempo referansı, saniye/km.
    ///
    /// Son haftaların kolay koşularından, benzer nabızda. Yoksa motor ilk turun temposunu
    /// referans alır — ama o da bir miktar yorgunluk içerir, ve motor bunu söyler.
    let freshPaceSecondsPerKilometre: Double?

    let restingHeartRate: Double
    let maxHeartRate: Double
    let performedAt: Date
}

/// Bir koşu turunun sonucu.
struct RunSplit: Sendable, Equatable, Hashable, Identifiable {
    let roundIndex: Int
    let durationSeconds: Double
    let paceSecondsPerKilometre: Double
    let averageHeartRate: Double?

    var id: Int { roundIndex }
}

/// Bir istasyonun sonucu.
struct StationSplit: Sendable, Equatable, Hashable, Identifiable {
    let station: HyroxStation
    let durationSeconds: Double
    let averageHeartRate: Double?
    let peakHeartRate: Double?

    /// Bu istasyonun toplam istasyon süresindeki payı.
    let shareOfStationTime: Double

    /// Payın referans dağılıma göre sapması. Pozitif = beklenenden uzun sürmüş.
    let deviationFromReference: Double

    var id: HyroxStation { station }
}

/// Kompanse koşu okuması — hibrit merceğin ana sayısı.
struct CompromisedRunning: Sendable, Equatable {

    /// Taze tempoya göre yavaşlama oranı. 0.08 = %8 yavaş.
    let penalty: Double

    /// Karşılaştırmada kullanılan taze tempo.
    let referencePaceSecondsPerKilometre: Double

    /// İstasyon sonrası koşuların ortalama temposu.
    let compromisedPaceSecondsPerKilometre: Double

    /// Referans dışarıdan mı geldi, yoksa ilk turdan mı türetildi.
    ///
    /// İlk turdan türetildiyse gerçek ceza bundan büyüktür — ilk tur da tamamen taze
    /// değildir. Arayüz bunu söylemek zorunda.
    let referenceWasDerivedFromFirstRound: Bool

    /// Tur başına tempo bozulması, saniye/km. Doğrusal eğim.
    let degradationPerRound: Double
}

struct HybridSessionOutput: Sendable, Equatable {

    let totalDurationSeconds: Double
    let runSplits: [RunSplit]
    let stationSplits: [StationSplit]

    /// Toplam geçiş süresi. Elit ile amatörü ayıran en büyük tek kalem.
    let roxzoneSeconds: Double

    /// Roxzone'un toplam süredeki payı.
    let roxzoneShare: Double

    let compromisedRunning: CompromisedRunning?

    /// Referans dağılıma göre en çok sapan istasyon.
    let weakestStation: HyroxStation?

    /// Kas ağırlıklı istasyonlarda geçen sürenin, kardiyo ağırlıklılara oranı.
    ///
    /// 1.0'ın belirgin üstü, kas dayanıklılığının aerobik tabanın gerisinde kaldığını
    /// gösterir — antrenmanın nereye gitmesi gerektiğini söyleyen sayı budur.
    let muscularToCardiovascularRatio: Double?

    var totalRunSeconds: Double {
        runSplits.reduce(into: 0) { $0 += $1.durationSeconds }
    }

    var totalStationSeconds: Double {
        stationSplits.reduce(into: 0) { $0 += $1.durationSeconds }
    }
}
