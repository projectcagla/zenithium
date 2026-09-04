//
//  BaselineBand.swift
//  Zenithium
//
//  Zenithium İmza Görseli: Taban Bandı.
//  Kullanıcının ±1σ koridoru ve kronolojik seyri Canvas ile saf çizim olarak oluşturulur.
//

import SwiftUI

struct BaselineBand: View {

    enum Style: Sendable, Equatable {
        case full    // 200–260pt, eksen etiketleri çizim alanının DIŞINDA
        case inline  // 44pt, eksen yok
        case micro   // 20pt, koridor + son nokta
    }

    let values: [Double]      // kronolojik, en yeni sonda
    let baseline: Double
    let sigma: Double
    let unit: String
    var style: Style = .inline

    var body: some View {
        Group {
            switch style {
            case .full:
                fullLayout
            case .inline:
                canvasView
                    .frame(height: 44)
            case .micro:
                canvasView
                    .frame(height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Layouts

    private var fullLayout: some View {
        HStack(alignment: .center, spacing: ZenithiumSpacing.s) {
            canvasView
                .frame(height: 220)

            // Eksen etiketleri çizim alanının DIŞINDA
            VStack(alignment: .leading, spacing: 0) {
                Text(ZenithiumFormat.metric(baseline + sigma, digits: 1))
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                Spacer()
                Text(ZenithiumFormat.metric(baseline, digits: 1))
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                Spacer()
                Text(ZenithiumFormat.metric(baseline - sigma, digits: 1))
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
            .frame(width: 44)
            .padding(.vertical, ZenithiumSpacing.xs)
        }
    }

    // MARK: - Canvas Çizimi

    private var canvasView: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let effectiveSigma = max(abs(sigma), 0.001)
            let lastValue = values.last ?? baseline

            // Dikey koordinat ölçeği hesaplama
            var allVals = values
            allVals.append(baseline - 1.5 * effectiveSigma)
            allVals.append(baseline + 1.5 * effectiveSigma)
            allVals.append(lastValue)

            let minVal = allVals.min() ?? (baseline - 2 * effectiveSigma)
            let maxVal = allVals.max() ?? (baseline + 2 * effectiveSigma)
            let rawSpan = max(maxVal - minVal, 0.001)

            // Kenarlara yapışmayı engelleyen dikey pay
            let verticalPadding = rawSpan * 0.12
            let paddedMin = minVal - verticalPadding
            let paddedMax = maxVal + verticalPadding
            let span = max(paddedMax - paddedMin, 0.001)

            func yFor(_ val: Double) -> CGFloat {
                let normalized = (val - paddedMin) / span
                return size.height * (1.0 - CGFloat(normalized))
            }

            // 1. KORİDOR: accent %11 dolgu; baseline'da kesikli 1px accent %35 çizgi
            let yTop = yFor(baseline + effectiveSigma)
            let yBottom = yFor(baseline - effectiveSigma)
            let yBaseline = yFor(baseline)

            let corridorRect = CGRect(
                x: 0,
                y: min(yTop, yBottom),
                width: size.width,
                height: max(abs(yBottom - yTop), 2)
            )
            context.fill(Path(corridorRect), with: .color(ZenithiumColor.accent.opacity(0.11)))

            var baselinePath = Path()
            baselinePath.move(to: CGPoint(x: 0, y: yBaseline))
            baselinePath.addLine(to: CGPoint(x: size.width, y: yBaseline))
            context.stroke(
                baselinePath,
                with: .color(ZenithiumColor.accent.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
            )

            // 2. SERİ VE GEÇMİŞ NOKTALAR (.full ve .inline için)
            let count = values.count
            var points: [CGPoint] = []

            if style != .micro && count > 0 {
                points = values.enumerated().map { index, val in
                    let x = count > 1
                        ? size.width * CGFloat(index) / CGFloat(count - 1)
                        : size.width - 6
                    let y = yFor(val)
                    return CGPoint(x: x, y: y)
                }

                if points.count > 1 {
                    var seriesPath = Path()
                    seriesPath.move(to: points[0])
                    for pt in points.dropFirst() {
                        seriesPath.addLine(to: pt)
                    }

                    // Seri: dim, 1,6pt, yumuşak köşe
                    context.stroke(
                        seriesPath,
                        with: .color(ZenithiumColor.textSecondary.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                }

                // Geçmiş noktalar: 2,2pt yarıçap, dim
                for pt in points.dropLast() {
                    let r: CGFloat = 2.2
                    context.fill(
                        Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                        with: .color(ZenithiumColor.textSecondary.opacity(0.6))
                    )
                }
            }

            // 3. SON NOKTA: 4,5pt yarıçap (bandın içindeyse ready, 1–2σ moderate, dışındaysa recovering)
            let diff = abs(lastValue - baseline)
            let zScore = diff / effectiveSigma

            let dotColor: Color
            if zScore <= 1.0 {
                dotColor = ZenithiumColor.green      // ready #3FCF8E
            } else if zScore <= 2.0 {
                dotColor = ZenithiumColor.yellow     // moderate #F0B23F
            } else {
                dotColor = ZenithiumColor.red        // recovering #EF5560
            }

            let lastPt: CGPoint
            if style == .micro || points.isEmpty {
                lastPt = CGPoint(x: size.width - 6, y: yFor(lastValue))
            } else {
                lastPt = points.last ?? CGPoint(x: size.width - 6, y: yFor(lastValue))
            }

            let dotRadius: CGFloat = 4.5
            context.fill(
                Path(ellipseIn: CGRect(x: lastPt.x - dotRadius, y: lastPt.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)),
                with: .color(dotColor)
            )

            // 4. SON NOKTA BANDIN DIŞINDAYSA: noktadan koridora dik ince çizgi + ucunda değer ve birim
            if zScore > 1.0 && style != .micro {
                var guideLine = Path()
                let targetY = lastValue > baseline ? min(yTop, yBottom) : max(yTop, yBottom)
                let startY = lastValue > baseline ? lastPt.y + dotRadius : lastPt.y - dotRadius

                guideLine.move(to: CGPoint(x: lastPt.x, y: startY))
                guideLine.addLine(to: CGPoint(x: lastPt.x, y: targetY))

                context.stroke(
                    guideLine,
                    with: .color(dotColor.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1.0)
                )

                let readout = "\(ZenithiumFormat.metric(lastValue, digits: 1)) \(unit)"
                let textY = lastValue > baseline ? max(lastPt.y - 12, 10) : min(lastPt.y + 12, size.height - 10)
                let textPoint = CGPoint(x: max(min(lastPt.x - 20, size.width - 45), 25), y: textY)

                context.draw(
                    Text(readout)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(dotColor),
                    at: textPoint
                )
            }
        }
    }

    private var accessibilityDescription: String {
        let last = values.last ?? baseline
        return "\(unit) taban bandı, taban \(ZenithiumFormat.metric(baseline, digits: 1)), son değer \(ZenithiumFormat.metric(last, digits: 1))"
    }
}

// MARK: - Önizlemeler

#Preview("BaselineBand · full") {
    BaselineBand(
        values: [52, 54, 53, 56, 58, 62, 59, 64, 61, 68],
        baseline: 55.0,
        sigma: 4.0,
        unit: "ms",
        style: .full
    )
    .padding()
    .background(ZenithiumColor.background)
}

#Preview("BaselineBand · inline") {
    BaselineBand(
        values: [7.2, 7.5, 6.8, 7.9, 8.1, 7.4, 6.2],
        baseline: 7.5,
        sigma: 0.6,
        unit: "sa",
        style: .inline
    )
    .padding()
    .background(ZenithiumColor.background)
}

#Preview("BaselineBand · micro") {
    BaselineBand(
        values: [52, 54, 58],
        baseline: 54.0,
        sigma: 3.5,
        unit: "bpm",
        style: .micro
    )
    .frame(width: 80)
    .padding()
    .background(ZenithiumColor.background)
}
