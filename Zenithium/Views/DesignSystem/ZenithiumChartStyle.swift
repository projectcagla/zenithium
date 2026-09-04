//
//  ZenithiumChartStyle.swift
//  Zenithium
//
//  Şartname Faz 3: Dilin İkinci Sözcüğü — ZenithiumChartStyle.
//  Swift Charts kullanan her görünüm için standart stil değiştirici.
//

import Charts
import SwiftUI

// MARK: - Standart Gradyan ve Çizgi Tanımları

public enum ZenithiumChartGradient {
    /// Çizginin altındaki alan serinin renginde dikey gradyan: %18 opaklıktan %0 opaklığa.
    /// Düz tek renk dolgu yasaktır.
    public static func area(for tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.18), tint.opacity(0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

public enum ZenithiumChartLine {
    /// Çizgi: 1.8pt, .round eklemler ve uçlar.
    public static let strokeStyle = StrokeStyle(
        lineWidth: 1.8,
        lineCap: .round,
        lineJoin: .round
    )
}

public enum ZenithiumChartLastPoint {
    /// Son nokta: 4pt çapında belirgin nokta.
    public static let diameter: CGFloat = 4.0
    public static let symbolSize: CGFloat = (diameter * diameter * .pi) / 4.0
}

// MARK: - LTTB Performans Downsampler

public enum ZenithiumChartDownsampler {
    /// Veri noktası sayısını 400'ü geçmeyecek şekilde downsample eder (Largest-Triangle-Three-Buckets).
    public static func downsample<T>(
        _ items: [T],
        maxPoints: Int = 400,
        x: (T) -> Double,
        y: (T) -> Double
    ) -> [T] {
        guard items.count > maxPoints, maxPoints >= 3 else { return items }

        var sampled: [T] = []
        sampled.reserveCapacity(maxPoints)

        // İlk nokta her zaman korunur
        sampled.append(items[0])

        let bucketSize = Double(items.count - 2) / Double(maxPoints - 2)
        var aIndex = 0

        for i in 0..<(maxPoints - 2) {
            let nextBucketStart = Int(floor(Double(i + 1) * bucketSize)) + 1
            let nextBucketEnd = min(Int(floor(Double(i + 2) * bucketSize)) + 1, items.count)

            var avgX: Double = 0
            var avgY: Double = 0
            let nextCount = Double(max(nextBucketEnd - nextBucketStart, 1))

            for j in nextBucketStart..<nextBucketEnd {
                avgX += x(items[j])
                avgY += y(items[j])
            }
            avgX /= nextCount
            avgY /= nextCount

            let currentBucketStart = Int(floor(Double(i) * bucketSize)) + 1
            let currentBucketEnd = min(Int(floor(Double(i + 1) * bucketSize)) + 1, items.count)

            let pointAX = x(items[aIndex])
            let pointAY = y(items[aIndex])

            var maxArea: Double = -1.0
            var maxAreaIndex = currentBucketStart

            for j in currentBucketStart..<currentBucketEnd {
                let currentX = x(items[j])
                let currentY = y(items[j])
                let area = abs((pointAX - avgX) * (currentY - pointAY) - (pointAX - currentX) * (avgY - pointAY)) * 0.5
                if area > maxArea {
                    maxArea = area
                    maxAreaIndex = j
                }
            }

            sampled.append(items[maxAreaIndex])
            aIndex = maxAreaIndex
        }

        // Son nokta her zaman korunur
        sampled.append(items[items.count - 1])
        return sampled
    }
}

// MARK: - View Modifier

public extension View {

    /// Swift Charts için kurumsal Zenithium stili.
    ///
    /// - Parameters:
    ///   - yValues: Y ekseninde en fazla 3–4 değer aralığı.
    ///   - showBaseline: Taban çizgisi / kılavuz çizgilerin gösterimi.
    ///   - xDesiredCount: X ekseninde 2–4 etiket sayısı.
    func zenithiumChart(
        yValues: ClosedRange<Int> = 3...4,
        showBaseline: Bool = true,
        xDesiredCount: Int = 3
    ) -> some View {
        self
            // Swift Charts varsayılan lejantı: HER ZAMAN GİZLİ
            .chartLegend(.hidden)
            // Y ekseni: En fazla 3–4 değer. İnce çizgi (hairlineSoft), kesikli değil düz 1px.
            // Eksen çizgisi yok, sadece kılavuz çizgiler. Değerler sağda, ZenithiumFont.label, faint, tabular rakam.
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: yValues.upperBound)) { _ in
                    if showBaseline {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1.0))
                            .foregroundStyle(ZenithiumColor.hairlineSoft)
                    }
                    AxisValueLabel(anchor: .leading)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .font(ZenithiumFont.label.monospacedDigit())
                }
            }
            // X ekseni: En fazla 2–4 etiket (örn. "Pzt", "Çar", "Cum", "Paz" veya saatler).
            // Grafik alanının DIŞINDA, en az 8pt boşlukla.
            .chartXAxis {
                let count = min(max(xDesiredCount, 2), 4)
                AxisMarks(values: .automatic(desiredCount: count)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1.0))
                        .foregroundStyle(ZenithiumColor.hairlineSoft.opacity(0.5))
                    AxisValueLabel(anchor: .top, collisionResolution: .greedy)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .font(ZenithiumFont.caption)
                }
            }
            .padding(.bottom, 8)
    }
}
