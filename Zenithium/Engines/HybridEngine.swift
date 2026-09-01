//
//  HybridEngine.swift
//  Zenithium
//
//  Hibrit seans analizi. Saf, Foundation-only, deterministik.
//
//  Motorun tek bir tezi var: **Hyrox'ta yarışı kaybettiren sayı, yorgunken koşarken ne kadar
//  yavaşladığındır.** İstasyon süreleri ölçülebilir ve herkes ölçüyor; kompanse koşu cezasını
//  ölçen neredeyse yok.
//

import Foundation

enum HybridEngine {

    /// ASSUMPTION HYROX-1: istasyonların toplam istasyon süresindeki referans payları.
    ///
    /// Bunlar tipik açık kategori bölünmelerinden türetildi ve **bir hedef değil, bir
    /// karşılaştırma tabanıdır** — "sled push'un beklenenden uzun sürdü" diyebilmek için bir
    /// beklentiye ihtiyaç var. Sporcunun kendi geçmişi biriktiğinde bu taban onunla
    /// değiştirilmeli; şu an ilk seansta da bir cevap verebilmek için burada duruyor.
    static let referenceStationShare: [HyroxStation: Double] = [
        .skiErg: 0.115,
        .sledPush: 0.115,
        .sledPull: 0.135,
        .burpeeBroadJump: 0.150,
        .rowing: 0.115,
        .farmersCarry: 0.085,
        .sandbagLunges: 0.135,
        .wallBalls: 0.150
    ]

    /// Bir seansı çözümler.
    static func analyse(_ input: HybridSessionInput) -> HybridSessionOutput {
        let segments = input.segments.sorted { $0.interval.start < $1.interval.start }

        let runSplits = makeRunSplits(from: segments)
        let stationSplits = makeStationSplits(from: segments)

        let roxzone = segments
            .filter { if case .transition = $0.kind { return true } else { return false } }
            .reduce(into: 0.0) { $0 += $1.duration }

        let total = segments.reduce(into: 0.0) { $0 += $1.duration }

        return HybridSessionOutput(
            totalDurationSeconds: total,
            runSplits: runSplits,
            stationSplits: stationSplits,
            roxzoneSeconds: roxzone,
            roxzoneShare: MathSupport.safeDivide(roxzone, by: total),
            compromisedRunning: compromisedRunning(
                runSplits: runSplits,
                freshPace: input.freshPaceSecondsPerKilometre
            ),
            weakestStation: weakestStation(in: stationSplits),
            muscularToCardiovascularRatio: systemRatio(in: stationSplits)
        )
    }

    // MARK: - Koşu turları

    private static func makeRunSplits(from segments: [HybridSegment]) -> [RunSplit] {
        segments.compactMap { segment in
            guard let round = segment.runRound,
                  let pace = segment.paceSecondsPerKilometre,
                  segment.duration > 0 else { return nil }
            return RunSplit(
                roundIndex: round,
                durationSeconds: segment.duration,
                paceSecondsPerKilometre: pace,
                averageHeartRate: segment.averageHeartRate
            )
        }
        .sorted { $0.roundIndex < $1.roundIndex }
    }

    /// Kompanse koşu cezası.
    ///
    /// Referans dışarıdan gelirse (son haftaların kolay koşularından, benzer nabızda) bütün
    /// turlar kompanse sayılır. Gelmezse ilk tur referans alınır ve 2. turdan itibarası
    /// karşılaştırılır — bu durumda gerçek ceza hesaplanandan büyüktür, çünkü ilk tur da
    /// tamamen taze değildir. Çıktı bunu `referenceWasDerivedFromFirstRound` ile söyler.
    static func compromisedRunning(
        runSplits: [RunSplit],
        freshPace: Double?
    ) -> CompromisedRunning? {

        guard runSplits.count >= 2 else { return nil }

        let reference: Double
        let compromisedSplits: [RunSplit]
        let derived: Bool

        if let freshPace, freshPace > 0 {
            reference = freshPace
            compromisedSplits = runSplits
            derived = false
        } else {
            guard let first = runSplits.first, first.paceSecondsPerKilometre > 0 else { return nil }
            reference = first.paceSecondsPerKilometre
            compromisedSplits = Array(runSplits.dropFirst())
            derived = true
        }

        guard !compromisedSplits.isEmpty,
              let compromisedPace = MathSupport.mean(compromisedSplits.map(\.paceSecondsPerKilometre)),
              reference > 0 else { return nil }

        return CompromisedRunning(
            penalty: (compromisedPace - reference) / reference,
            referencePaceSecondsPerKilometre: reference,
            compromisedPaceSecondsPerKilometre: compromisedPace,
            referenceWasDerivedFromFirstRound: derived,
            degradationPerRound: degradationSlope(of: runSplits)
        )
    }

    /// Tur indeksine karşı temponun doğrusal eğimi, saniye/km/tur.
    ///
    /// En küçük kareler. Pozitif eğim, turlar ilerledikçe yavaşladığını gösterir.
    static func degradationSlope(of runSplits: [RunSplit]) -> Double {
        guard runSplits.count >= 2 else { return 0 }
        let xs = runSplits.map { Double($0.roundIndex) }
        let ys = runSplits.map(\.paceSecondsPerKilometre)
        guard let meanX = MathSupport.mean(xs), let meanY = MathSupport.mean(ys) else { return 0 }

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            let dx = x - meanX
            numerator += dx * (y - meanY)
            denominator += dx * dx
        }
        return MathSupport.safeDivide(numerator, by: denominator)
    }

    // MARK: - İstasyonlar

    private static func makeStationSplits(from segments: [HybridSegment]) -> [StationSplit] {
        let stationSegments = segments.compactMap { segment -> (HyroxStation, HybridSegment)? in
            guard let station = segment.station, segment.duration > 0 else { return nil }
            return (station, segment)
        }
        let total = stationSegments.reduce(into: 0.0) { $0 += $1.1.duration }

        return stationSegments.map { station, segment in
            let share = MathSupport.safeDivide(segment.duration, by: total)
            let reference = referenceStationShare[station] ?? 0
            return StationSplit(
                station: station,
                durationSeconds: segment.duration,
                averageHeartRate: segment.averageHeartRate,
                peakHeartRate: segment.peakHeartRate,
                shareOfStationTime: share,
                deviationFromReference: reference > 0 ? share - reference : 0
            )
        }
        .sorted { $0.station.order < $1.station.order }
    }

    /// Referans payından en çok sapan istasyon.
    ///
    /// En *uzun süren* istasyon değil — burpee her zaman uzundur, bu bir zayıflık değil.
    /// Aranan, kendi beklentisine göre orantısız uzun süren istasyon.
    static func weakestStation(in splits: [StationSplit]) -> HyroxStation? {
        splits
            .filter { $0.deviationFromReference > 0 }
            .max { $0.deviationFromReference < $1.deviationFromReference }?
            .station
    }

    /// Kas ağırlıklı istasyonların kardiyo ağırlıklılara süre oranı.
    static func systemRatio(in splits: [StationSplit]) -> Double? {
        let muscular = splits
            .filter { $0.station.dominantSystem == .muscular }
            .reduce(into: 0.0) { $0 += $1.durationSeconds }
        let cardio = splits
            .filter { $0.station.dominantSystem == .cardiovascular }
            .reduce(into: 0.0) { $0 += $1.durationSeconds }
        guard muscular > 0, cardio > 0 else { return nil }
        return muscular / cardio
    }

    // MARK: - Kas yükü

    /// Bir hibrit seansın kas etkileri.
    ///
    /// Her istasyon kendi süresine orantılı bir yük üretir ve mevcut yorgunluk motoruna
    /// normal bir seans gibi girer — hibrit için ayrı bir yorgunluk modeli yok, olmasına
    /// da gerek yok.
    static func muscleImpacts(
        for output: HybridSessionOutput,
        sessionIdentifier: UUID,
        performedAt: Date,
        sessionLoad: Double
    ) -> [MuscleSessionImpact] {
        output.stationSplits.compactMap { split in
            let involvement = MuscleInvolvementMatrix.involvement(for: split.station)
            guard !involvement.isEmpty else { return nil }
            // İstasyonun payı kadar yük: yirmi dakikalık sled push, iki dakikalıktan fazla
            // yorar ve model bunu görmeli.
            let share = max(split.shareOfStationTime, 0)
            return MuscleSessionImpact(
                timestamp: performedAt,
                source: .hybridStation(id: sessionIdentifier, station: split.station),
                sessionLoad: MathSupport.clamp(
                    sessionLoad * share * Double(HyroxStation.allCases.count),
                    to: EngineConstants.Fatigue.sessionLoadRange
                ),
                involvement: involvement
            )
        }
    }

    /// Bir sonraki seans için tek cümlelik yön.
    ///
    /// §12 dili: antrenman yönlendirmesi, sağlık iddiası değil.
    static func guidance(for output: HybridSessionOutput) -> String {
        if let compromised = output.compromisedRunning, compromised.penalty > 0.10 {
            return "İstasyon sonrası temponuz taze temponuzdan %\(Int((compromised.penalty * 100).rounded())) yavaş. "
                + "Zayıf halkanız kompanse koşu — istasyon bloklarının hemen ardına kısa koşular ekleyin."
        }
        if output.roxzoneShare > 0.08 {
            return "Geçişler toplam sürenizin %\(Int((output.roxzoneShare * 100).rounded()))'ini alıyor. "
                + "İstasyona giriş ve çıkış provası, kondisyondan bağımsız kazanılabilecek en hızlı süre."
        }
        if let ratio = output.muscularToCardiovascularRatio, ratio > 1.35 {
            return "Kas ağırlıklı istasyonlarda kardiyo istasyonlarından belirgin daha fazla vakit geçiriyorsunuz. "
                + "Aerobik tabanınız kas dayanıklılığınızın önünde — sled ve carry hacmini artırın."
        }
        if let station = output.weakestStation {
            return "\(station.displayName) beklenenden orantısız uzun sürdü. Bu hafta ona ayrı bir blok ayırın."
        }
        return "Bölünmeler dengeli. Bir sonraki seansta toplam süreyi hedefleyin."
    }
}
