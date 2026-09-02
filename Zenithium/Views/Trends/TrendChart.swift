//
//  TrendChart.swift
//  Zenithium
//
//  The scrubbable trend chart. Spec §10: Swift Charts, scrubbable, with an
//  `.accessibilityChartDescriptor` so VoiceOver can play and read the series.
//
//  ASSUMPTION UI-7: this file imports `Accessibility` for the `AX…Descriptor` types. It is
//  not on the §2.2 framework list, but §10 mandates the descriptor and those types live
//  nowhere else; it is first-party and adds no capability beyond describing the chart.
//

import SwiftUI
import Charts
import Accessibility

struct TrendChart: View {

    let content: TrendsViewModel.Content

    @State private var scrubbedPoint: TrendPoint?

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 200

    private var tint: Color {
        switch content.metric {
        case .recovery: return ZenithiumColor.green
        case .strain: return ZenithiumColor.accent
        case .sleep: return ZenithiumColor.accent
        case .heartRateVariability: return ZenithiumColor.green
        case .restingHeartRate: return ZenithiumColor.yellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            scrubReadout

            Chart {
                ForEach(content.points) { point in
                    AreaMark(
                        x: .value("Gün", point.date),
                        y: .value(content.metric.displayName, point.value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Gün", point.date),
                        y: .value(content.metric.displayName, point.value)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                if let average = content.average {
                    RuleMark(y: .value("Ortalama", average))
                        .foregroundStyle(ZenithiumColor.textTertiary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(content.bloodEvents) { event in
                    RuleMark(x: .value("Tahlil", event.date))
                        .foregroundStyle(ZenithiumColor.accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }

                if let scrubbedPoint {
                    RuleMark(x: .value("Gün", scrubbedPoint.date))
                        .foregroundStyle(ZenithiumColor.textSecondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("Gün", scrubbedPoint.date),
                        y: .value(content.metric.displayName, scrubbedPoint.value)
                    )
                    .foregroundStyle(tint)
                    .symbolSize(90)
                }
            }
            .chartYScale(domain: content.axisRange)
            .zenithiumChartChrome()
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(proxy: proxy, geometry: geometry))
                }
            }
            // Saf çizim (Swift Charts): sabit 200pt yerine @ScaledMetric ile minHeight kullanılır,
            // Dynamic Type büyüdüğünde eksen etiketleri ve grafik rahat nefes alır.
            .frame(minHeight: chartHeight)
            .accessibilityChartDescriptor(descriptor)
        }
    }

    /// The readout above the chart, which is also what the scrub updates. Keeping it outside
    /// the plot means it never overlaps the line or clips at AX5.
    private var scrubReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
            let point = scrubbedPoint ?? content.points.last
            if let point {
                Text(ZenithiumFormat.metric(point.value, digits: content.metric.fractionDigits))
                    .metricNumeral()
                    .minimumScaleFactor(0.8)
                if !content.metric.unitSymbol.isEmpty {
                    Text(content.metric.unitSymbol)
                        .metricUnit()
                }
                Spacer(minLength: 8)
                Text(point.date.formatted(date: .abbreviated, time: .omitted))
                    .zenithiumCaption()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scrubbedPoint == nil ? "En son değer" : "Seçili değer")
        .accessibilityValue(readoutAccessibilityValue)
    }

    private var readoutAccessibilityValue: String {
        guard let point = scrubbedPoint ?? content.points.last else { return "Değer yok" }
        let value = ZenithiumFormat.metric(point.value, digits: content.metric.fractionDigits)
        return "\(value) \(content.metric.unitSymbol), \(point.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard let plotFrame = proxy.plotFrame else { return }
                let origin = geometry[plotFrame].origin
                let x = drag.location.x - origin.x
                guard let date: Date = proxy.value(atX: x) else { return }
                scrubbedPoint = nearestPoint(to: date)
            }
            .onEnded { _ in
                scrubbedPoint = nil
            }
    }

    private func nearestPoint(to date: Date) -> TrendPoint? {
        content.points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

// MARK: - VoiceOver

extension TrendChart {

    /// The played description of the series (§10).
    ///
    /// Built from `SeriesChartDescriptor`, which is this description generalised so the
    /// training-load and blood-marker charts can be played too. Yol haritası v4, B8.
    var descriptor: SeriesChartDescriptor {
        SeriesChartDescriptor(
            title: "\(content.range.accessibilityName) boyunca \(content.metric.displayName)",
            seriesName: content.metric.displayName,
            points: content.points.map { DescribedPoint(date: $0.date, value: $0.value) },
            formatValue: { [metric = content.metric] value in
                "\(ZenithiumFormat.metric(value, digits: metric.fractionDigits)) \(metric.unitSymbol)"
            },
            summary: descriptorSummary
        )
    }

    private var descriptorSummary: String {
        guard let average = content.average,
              let minimum = content.minimum,
              let maximum = content.maximum else {
            return "\(content.points.count) gün"
        }
        let digits = content.metric.fractionDigits
        return "\(content.points.count) gün. Ortalama \(ZenithiumFormat.metric(average, digits: digits)), en düşük \(ZenithiumFormat.metric(minimum, digits: digits)), en yüksek \(ZenithiumFormat.metric(maximum, digits: digits))."
    }
}
