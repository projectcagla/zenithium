import SwiftUI

/// A floating reference corridor. Missing measurements never become a synthetic last point.
struct BaselineBand: View {
    enum Style: Sendable, Equatable { case full, inline, micro }

    let values: [Double]
    let baseline: Double?
    let sigma: Double?
    let unit: String
    var style: Style = .inline
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
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let domain = range
            let span = domain.upperBound - domain.lowerBound
            let inset: CGFloat = showsSeries ? 5 : 0
            func y(_ value: Double) -> CGFloat {
                CGFloat((domain.upperBound - value) / span) * (size.height - inset * 2) + inset
            }
            if let baseline = validBaseline, let spread {
                let upper = y(baseline + spread)
                let lower = y(baseline - spread)
                let corridor = CGRect(x: 0, y: upper, width: size.width, height: max(lower - upper, 1))
                context.fill(Path(corridor), with: .color(tint.opacity(0.10)))
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: y(baseline)))
                guide.addLine(to: CGPoint(x: size.width, y: y(baseline)))
                context.stroke(guide, with: .color(tint.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            guard showsSeries else { return }
            let samples = finiteValues
            guard !samples.isEmpty else {
                for index in 0..<9 {
                    let x = (size.width - 4) * CGFloat(index) / 8 + 2
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: size.height / 2 - 1, width: 2, height: 2)), with: .color(ZenithiumColor.textPrimary.opacity(0.06)))
                }
                return
            }
            let points = samples.enumerated().map { index, value in
                CGPoint(x: samples.count == 1 ? size.width - inset : inset + (size.width - inset * 2) * CGFloat(index) / CGFloat(samples.count - 1), y: y(value))
            }
            if let first = points.first {
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(tint.opacity(0.75)), style: StrokeStyle(lineWidth: style == .micro ? 1.2 : 1.8, lineCap: .round, lineJoin: .round))
            }
            guard let point = points.last, let last = samples.last else { return }
            let outside = validBaseline.map { abs(last - $0) > (spread ?? .infinity) } ?? false
            let pointColor = outside && highlightsDeviation ? ZenithiumColor.yellow : tint
            if outside, let baseline = validBaseline, let spread {
                var guide = Path()
                guide.move(to: point)
                guide.addLine(to: CGPoint(x: point.x, y: y(baseline + (last > baseline ? spread : -spread))))
                context.stroke(guide, with: .color(pointColor.opacity(0.65)), lineWidth: 1)
            }
            let radius: CGFloat = style == .micro ? 2.5 : 3.5
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(pointColor))
        }
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
            let pointColor = value < lower || value > upper ? ZenithiumColor.yellow : ZenithiumColor.textPrimary
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
