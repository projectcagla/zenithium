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
    var baseline: Double? = nil
    var sigma: Double? = nil
    var referenceLabel: String = "Kişisel taban"
    var transitionNamespace: Namespace.ID? = nil
    var transitionID: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrubbedPoint: TrendPoint?

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 240

    private var tint: Color {
        switch content.metric {
        case .recovery: return ZenithiumColor.green
        case .strain: return ZenithiumColor.accent
        case .sleep: return ZenithiumColor.accent
        case .heartRateVariability: return ZenithiumColor.green
        case .restingHeartRate: return ZenithiumColor.yellow
        }
    }

    private var displayPoints: [TrendPoint] {
        ZenithiumChartDownsampler.downsample(
            content.points.sorted { $0.date < $1.date },
            maxPoints: 400,
            x: { $0.date.timeIntervalSince1970 },
            y: { $0.value }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            scrubReadout

            Chart {
                ForEach(displayPoints) { point in
                    LineMark(
                        x: .value("Gün", point.date),
                        y: .value(content.metric.displayName, point.value)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(ZenithiumChartLine.strokeStyle)
                    .interpolationMethod(.monotone)
                }

                if let last = displayPoints.last, scrubbedPoint == nil {
                    PointMark(
                        x: .value("Gün", last.date),
                        y: .value(content.metric.displayName, last.value)
                    )
                    .foregroundStyle(tint)
                    .symbolSize(ZenithiumChartLastPoint.symbolSize)

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
            .chartYScale(domain: chartRange)
            .chartPlotStyle { plot in
                plot.background {
                    BaselineBand(values: [], baseline: baseline, sigma: sigma, unit: content.metric.unitSymbol, style: .full, tint: tint, valueRange: chartRange, showsAxisLabels: false, showsSeries: false, referenceLabel: referenceLabel)
                        .accessibilityHidden(true)
                }
            }
            .zenithiumChart(yValues: 3...4, showBaseline: true)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))
                }
            }
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
            .modifier(ChartContinuity(namespace: transitionNamespace, id: transitionID))
            .accessibilityChartDescriptor(descriptor)
            .accessibilityAdjustableAction { direction in
                let points = displayPoints
                guard !points.isEmpty else { return }
                let current = points.firstIndex { $0.id == scrubbedPoint?.id } ?? (points.count - 1)
                switch direction {
                case .increment: scrubbedPoint = points[min(current + 1, points.count - 1)]
                case .decrement: scrubbedPoint = points[max(current - 1, 0)]
                @unknown default: break
                }
            }
        }
        .onChange(of: content) { _, _ in scrubbedPoint = nil }
    }

    private var chartRange: ClosedRange<Double> {
        if let fixed = content.metric.fixedRange { return fixed }
        var values = content.points.map(\.value).filter(\.isFinite)
        if let baseline, let sigma { values += [baseline - sigma, baseline + sigma] }
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let padding = max((upper - lower) * 0.15, max(abs(upper) * 0.03, 0.1))
        return (lower - padding)...(upper + padding)
    }

    /// The readout above the chart, which is also what the scrub updates. Keeping it outside
    /// the plot means it never overlaps the line or clips at AX5.
    private var scrubReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            let point = scrubbedPoint ?? content.points.last
            if let point {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if content.metric.unitSymbol == "%" { Text("%").heroUnit() }
                    Text(ZenithiumFormat.metric(point.value, digits: content.metric.fractionDigits))
                        .heroNumeral().lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: point.value)
                    if !content.metric.unitSymbol.isEmpty && content.metric.unitSymbol != "%" {
                        Text(content.metric.unitSymbol).heroUnit()
                    }
                }
                Text(point.date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR"))))
                    .zenithiumCaption()
            }
        }
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

private struct ChartContinuity: ViewModifier {
    let namespace: Namespace.ID?
    let id: String?
    func body(content: Content) -> some View {
        if let namespace, let id {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
