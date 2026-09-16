import SwiftUI
import Charts

/// A floating reference corridor. Missing measurements never become a synthetic last point.
struct BaselineBand: View {
    enum Style: Sendable, Equatable { case full, inline, micro }

    let values: [Double]
    let baseline: Double?
    let sigma: Double?
    let unit: String
    var style: Style = .inline
    var dates: [Date] = []
    var tint: Color = ZenithiumColor.accent
    var valueRange: ClosedRange<Double>? = nil
    var showsAxisLabels: Bool = true
    var showsSeries: Bool = true
    var highlightsDeviation: Bool = true
    var referenceLabel: String = "Kişisel taban"
    var horizontalRange: Bool = false
    var secondaryRange: ClosedRange<Double>? = nil

    private var finiteValues: [Double] { values.filter(\.isFinite) }
    private var validBaseline: Double? { baseline.flatMap { $0.isFinite ? $0 : nil } }
    private var spread: Double? { sigma.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }

    private var timeRange: ClosedRange<Double> {
        let coordinates = dates.count == values.count
            ? dates.map(\.timeIntervalSince1970) : values.indices.map(Double.init)
        let lower = coordinates.min() ?? 0
        let upper = coordinates.max() ?? 1
        let padding = max((upper - lower) * 0.025, dates.isEmpty ? 0.5 : 3600)
        return (lower - padding)...(upper + padding)
    }

    private var range: ClosedRange<Double> {
        if let valueRange, valueRange.upperBound > valueRange.lowerBound { return valueRange }
        var bounds = finiteValues
        if let baseline = validBaseline, let spread {
            bounds += [baseline - spread, baseline + spread]
        }
        let lower = bounds.min() ?? 0
        let upper = bounds.max() ?? 1
        let padding = max((upper - lower) * 0.18, max(abs(upper) * 0.02, 0.01))
        return (lower - padding)...(upper + padding)
    }

    var body: some View {
        Group {
            if horizontalRange {
                clinicalDrawing.frame(height: 44)
            } else if style == .full && showsAxisLabels {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    HStack(spacing: ZenithiumSpacing.s) {
                        drawing.frame(height: 220)
                        VStack(alignment: .trailing) {
                            Text(ZenithiumFormat.metric(range.upperBound, digits: 1))
                            Spacer()
                            Text(ZenithiumFormat.metric((range.lowerBound + range.upperBound) / 2, digits: 1))
                            Spacer()
                            Text(ZenithiumFormat.metric(range.lowerBound, digits: 1))
                        }
                        .font(ZenithiumFont.caption.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .frame(height: 220)
                    }
                    if let baseline = validBaseline, let spread {
                        Text("\(referenceLabel) · \(ZenithiumFormat.metric(baseline, digits: 1)) ± \(ZenithiumFormat.metric(spread, digits: 1)) \(unit)")
                            .zenithiumCaption()
                    } else {
                        Text("Kişisel koridor için yeterli geçmiş yok")
                            .zenithiumCaption()
                    }
                }
            } else if style == .full {
                drawing
            } else {
                drawing.frame(height: style == .micro ? 20 : 44)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var drawing: some View {
        Chart {
            if let baseline = validBaseline, let spread {
                RectangleMark(yStart: .value("Alt", baseline - spread), yEnd: .value("Üst", baseline + spread))
                    .foregroundStyle(tint.opacity(0.10))
                RuleMark(y: .value("Taban", baseline))
                    .foregroundStyle(tint.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if showsSeries {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if value.isFinite {
                        PointMark(x: .value("Kayıt", dates.count == values.count ? dates[index].timeIntervalSince1970 : Double(index)),
                                  y: .value(unit, value))
                            .foregroundStyle(tint.opacity(index == values.count - 1 ? 1 : 0.55))
                            .symbolSize(style == .micro ? 8 : 20)
                    }
                }
            }
        }
        .chartYScale(domain: range)
        .chartXScale(domain: timeRange)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    private var clinicalDrawing: some View {
        Canvas { context, size in
            guard let baseline = validBaseline, let spread, let value = finiteValues.last else { return }
            let lower = baseline - spread
            let upper = baseline + spread
            let pad = max(spread * 0.4, 0.01)
            let minimum = min(lower, value, secondaryRange?.lowerBound ?? lower) - pad
            let maximum = max(upper, value, secondaryRange?.upperBound ?? upper) + pad
            func x(_ value: Double) -> CGFloat { 4 + CGFloat((value - minimum) / (maximum - minimum)) * max(0, size.width - 8) }
            let y = size.height / 2
            let track = CGRect(x: 0, y: y - 2, width: size.width, height: 4)
            context.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(ZenithiumColor.hairline))
            context.fill(Path(roundedRect: CGRect(x: x(lower), y: y - 5, width: x(upper) - x(lower), height: 10), cornerRadius: 3), with: .color(tint.opacity(0.16)))
            if let secondaryRange {
                context.fill(Path(roundedRect: CGRect(x: x(secondaryRange.lowerBound), y: y - 5, width: x(secondaryRange.upperBound) - x(secondaryRange.lowerBound), height: 10), cornerRadius: 3), with: .color(tint.opacity(0.22)))
            }
            let pointColor = tint
            var marker = Path()
            marker.move(to: CGPoint(x: x(value), y: y - 10))
            marker.addLine(to: CGPoint(x: x(value), y: y + 10))
            context.stroke(marker, with: .color(pointColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private var accessibilityDescription: String {
        let current = finiteValues.last.map { "Son değer \(ZenithiumFormat.metric($0, digits: 1)) \(unit)." } ?? "Ölçüm yok."
        guard let baseline = validBaseline, let spread else { return current + " Kişisel taban henüz oluşmadı." }
        if horizontalRange { return "\(current) \(referenceLabel): \(ZenithiumFormat.metric(baseline - spread, digits: 1))–\(ZenithiumFormat.metric(baseline + spread, digits: 1)) \(unit)." }
        return "\(current) \(referenceLabel): \(ZenithiumFormat.metric(baseline, digits: 1)), koridor ±\(ZenithiumFormat.metric(spread, digits: 1)) \(unit)."
    }
}
