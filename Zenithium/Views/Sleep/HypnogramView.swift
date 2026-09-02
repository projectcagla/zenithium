//
//  HypnogramView.swift
//  Zenithium
//
//  Şartname Uyku Ekranı Kahramanı: Hipnogram.
//  Tam genişlik, kartsız, zaman ekseni altta sessiz.
//  Evre renkleri ayırt edilebilir ama bağırmayan tonlarda.
//  Derin uyku vurgulanır — toparlanmanın kaynağı odur.
//

import SwiftUI

struct HypnogramView: View {

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 130

    let record: BiometricDaySnapshot

    private var totalSeconds: Double {
        let sum = record.deepSeconds + record.remSeconds + record.coreSeconds + record.awakeSeconds
        return sum > 0 ? sum : (record.sleepDurationSeconds > 0 ? record.sleepDurationSeconds : 28800)
    }

    private var segments: [HypnogramSegment] {
        buildUltradianSegments()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            GeometryReader { proxy in
                hypnogramCanvas(size: proxy.size)
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hipnogram grafiği")
            .accessibilityValue(accessibilityDescription)

            timeAxis
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Canvas

    private func hypnogramCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            guard w > 10, h > 10 else { return }

            // 4 seviyenin Y koordinatları (üstten alta: Uyanık, REM, Çekirdek, Derin)
            let yAwake = h * 0.14
            let yREM = h * 0.40
            let yCore = h * 0.66
            let yDeep = h * 0.90

            func yForStage(_ stage: SleepStage) -> CGFloat {
                switch stage {
                case .awake: return yAwake
                case .asleepREM: return yREM
                case .asleepCore, .asleepUnspecified: return yCore
                case .asleepDeep: return yDeep
                case .inBed: return yAwake
                }
            }

            // Kılavuz çizgileri
            let levels: [(CGFloat, String)] = [
                (yAwake, "Uyanık"),
                (yREM, "REM"),
                (yCore, "Hafif"),
                (yDeep, "Derin")
            ]
            for (y, _) in levels {
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: y))
                guide.addLine(to: CGPoint(x: w, y: y))
                context.stroke(
                    guide,
                    with: .color(ZenithiumColor.hairlineSoft.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }

            let segs = segments
            guard !segs.isEmpty else { return }

            // 1. Önce Derin Uyku Bloklarını Vurgula (Toparlanmanın Kaynağı)
            for seg in segs where seg.stage == .asleepDeep {
                let x0 = w * seg.startFraction
                let x1 = w * seg.endFraction
                let rect = CGRect(x: x0, y: yDeep - 12, width: max(x1 - x0, 3), height: h - (yDeep - 12))
                let deepRect = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(
                    deepRect,
                    with: .linearGradient(
                        Gradient(colors: [
                            ZenithiumColor.spectrumTeal.opacity(0.38),
                            ZenithiumColor.spectrumIndigo.opacity(0.12)
                        ]),
                        startPoint: CGPoint(x: x0, y: yDeep - 12),
                        endPoint: CGPoint(x: x0, y: h)
                    )
                )
            }

            // 2. Basamaklı Hipnogram Çizgisi
            var path = Path()
            for (idx, seg) in segs.enumerated() {
                let x0 = w * seg.startFraction
                let x1 = w * seg.endFraction
                let y = yForStage(seg.stage)

                if idx == 0 {
                    path.move(to: CGPoint(x: x0, y: y))
                } else {
                    // Dikey geçiş
                    path.addLine(to: CGPoint(x: x0, y: y))
                }
                // Yatay basamak
                path.addLine(to: CGPoint(x: x1, y: y))
            }

            // Çizgi çizimi: sessiz, pastel renk
            context.stroke(
                path,
                with: .color(ZenithiumColor.textSecondary.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // 3. Derin Uyku ve REM basamaklarının üzerine renkli vurgu vuruşu
            for seg in segs {
                let x0 = w * seg.startFraction
                let x1 = w * seg.endFraction
                let y = yForStage(seg.stage)
                var segPath = Path()
                segPath.move(to: CGPoint(x: x0, y: y))
                segPath.addLine(to: CGPoint(x: x1, y: y))

                if seg.stage == .asleepDeep {
                    context.stroke(
                        segPath,
                        with: .color(ZenithiumColor.spectrumTeal),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                } else if seg.stage == .asleepREM {
                    context.stroke(
                        segPath,
                        with: .color(ZenithiumColor.spectrumViolet),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                }
            }
        }
    }

    // MARK: - Zaman Ekseni

    private var timeAxis: some View {
        HStack(alignment: .firstTextBaseline) {
            if let start = record.sleepStart {
                Text(start.formatted(date: .omitted, time: .shortened))
                    .zenithiumCaption()
                    .monospacedDigit()
            } else {
                Text("23:00")
                    .zenithiumCaption()
                    .monospacedDigit()
            }

            Spacer()

            // Ortada derin uyku vurgusu
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ZenithiumColor.spectrumTeal)
                    .frame(width: 8, height: 8)
                Text("Derin: \(ZenithiumFormat.duration(seconds: record.deepSeconds))")
                    .zenithiumCaption()
                    .foregroundStyle(ZenithiumColor.spectrumTeal)
            }

            Spacer()

            if let wake = record.wakeTime {
                Text(wake.formatted(date: .omitted, time: .shortened))
                    .zenithiumCaption()
                    .monospacedDigit()
            } else {
                Text("07:00")
                    .zenithiumCaption()
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Ultradian Segment Modellemesi

    /// Sağlanan toplam süreleri insan biyolojisindeki 90 dakikalık NREM/REM ultradian döngülerine
    /// dağıtarak gerçek toplamları koruyan basamaklı segment dizisi üretir.
    private func buildUltradianSegments() -> [HypnogramSegment] {
        let total = totalSeconds
        guard total > 600 else { return [] }

        let deep = record.deepSeconds
        let rem = record.remSeconds
        let awake = record.awakeSeconds
        let core = max(0, total - (deep + rem + awake))

        var result: [HypnogramSegment] = []

        // Geceyi 4 döngüye ayır:
        // Döngü 1 & 2: Derin uyku yoğun
        // Döngü 3 & 4: REM yoğun
        // Başta ve aralarda kısa uyanıklık
        let cycle1Deep = deep * 0.55
        let cycle2Deep = deep * 0.35
        let cycle3Deep = deep * 0.10

        let cycle1Rem = rem * 0.10
        let cycle2Rem = rem * 0.25
        let cycle3Rem = rem * 0.35
        let cycle4Rem = rem * 0.30

        let cycle1Core = core * 0.25
        let cycle2Core = core * 0.30
        let cycle3Core = core * 0.25
        let cycle4Core = core * 0.20

        let awakeStart = awake * 0.40
        let awakeMid = awake * 0.30
        let awakeEnd = awake * 0.30

        var currentSec: Double = 0

        func add(_ stage: SleepStage, _ seconds: Double) {
            guard seconds > 30 else { return }
            let startFrac = currentSec / total
            currentSec += seconds
            let endFrac = min(1.0, currentSec / total)
            result.append(HypnogramSegment(stage: stage, startFraction: startFrac, endFraction: endFrac))
        }

        // Başlangıç: Uyanık -> Çekirdek -> Derin -> REM
        add(.awake, awakeStart)
        add(.asleepCore, cycle1Core * 0.6)
        add(.asleepDeep, cycle1Deep)
        add(.asleepCore, cycle1Core * 0.4)
        add(.asleepREM, cycle1Rem)

        // Döngü 2
        add(.asleepCore, cycle2Core * 0.5)
        add(.asleepDeep, cycle2Deep)
        add(.asleepCore, cycle2Core * 0.5)
        add(.awake, awakeMid)
        add(.asleepREM, cycle2Rem)

        // Döngü 3
        add(.asleepCore, cycle3Core * 0.5)
        add(.asleepDeep, cycle3Deep)
        add(.asleepCore, cycle3Core * 0.5)
        add(.asleepREM, cycle3Rem)

        // Döngü 4 (sabah sonu)
        add(.asleepCore, cycle4Core)
        add(.asleepREM, cycle4Rem)
        add(.awake, awakeEnd)

        // Kalan payı tamamla
        if currentSec < total {
            add(.asleepCore, total - currentSec)
        }

        return result
    }

    private var accessibilityDescription: String {
        "Gecelik hipnogram: \(ZenithiumFormat.duration(seconds: record.deepSeconds)) derin uyku, \(ZenithiumFormat.duration(seconds: record.remSeconds)) REM uykusu, \(ZenithiumFormat.duration(seconds: record.coreSeconds)) hafif uyku."
    }
}

struct HypnogramSegment: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let startFraction: Double
    let endFraction: Double
}
