//
//  CircadianArcView.swift
//  Zenithium
//
//  The alertness arc. Spec §5.5 for the curve, §10 for the accessibility gate.
//
//  Drawn in `Canvas` rather than Swift Charts: the arc is a continuous curve the engine has
//  already sampled, not a series of data points to plot, and `Canvas` renders 288 samples in
//  one pass. The markers carry the meaning, so each is its own accessibility element and the
//  curve itself is decorative.
//

import SwiftUI

struct CircadianArcView: View {

    let arc: CircadianArc

    /// Marked when the caller wants the compact form — major markers only (§5.5).
    var majorMarkersOnly = false

    private var markers: [CircadianMarker] {
        majorMarkersOnly ? arc.markers.filter { $0.event.isMajor } : arc.markers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            GeometryReader { proxy in
                ZStack {
                    curve(in: proxy.size)
                    markerDots(in: proxy.size)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gün boyunca uyanıklık")
            .accessibilityValue(curveAccessibilityValue)

            markerLegend
        }
    }

    // MARK: - Curve

    private func curve(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard arc.samples.count >= 2,
                  let first = arc.samples.first,
                  let last = arc.samples.last else { return }

            let span = last.date.timeIntervalSince(first.date)
            guard span > 0, canvasSize.width > 0, canvasSize.height > 0 else { return }

            func point(_ sample: CircadianSample) -> CGPoint {
                let x = sample.date.timeIntervalSince(first.date) / span * canvasSize.width
                // The arc is 0…100 by construction (§11), so the axis is fixed rather than
                // fitted — a fitted axis would make a flat low-recovery day look normal.
                let normalized = MathSupport.clamp(sample.alertness / EngineConstants.Circadian.maxAlertness, 0, 1)
                let y = canvasSize.height - normalized * canvasSize.height
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: point(first))
            for sample in arc.samples.dropFirst() {
                line.addLine(to: point(sample))
            }

            var fill = line
            fill.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
            fill.addLine(to: CGPoint(x: 0, y: canvasSize.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        ZenithiumColor.accent.opacity(0.28),
                        ZenithiumColor.accent.opacity(0.02)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )
            context.stroke(
                line,
                with: .color(ZenithiumColor.accent),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private func markerDots(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard let first = arc.samples.first, let last = arc.samples.last else { return }
            let span = last.date.timeIntervalSince(first.date)
            guard span > 0 else { return }

            for marker in markers {
                let progress = marker.date.timeIntervalSince(first.date) / span
                guard progress >= 0, progress <= 1 else { continue }
                let x = progress * canvasSize.width
                let normalized = MathSupport.clamp(
                    marker.alertness / EngineConstants.Circadian.maxAlertness, 0, 1
                )
                let y = canvasSize.height - normalized * canvasSize.height
                let dot = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(ZenithiumColor.background))
                context.stroke(dot, with: .color(ZenithiumColor.accent), lineWidth: 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    // MARK: - Legend

    /// The markers as text. This is what VoiceOver reads and what a user at AX5 sees, so it
    /// carries the same information the curve does rather than labelling it.
    private var markerLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ZenithiumSpacing.m) {
                ForEach(markers) { marker in
                    markerLabel(marker)
                }
            }
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                ForEach(markers) { marker in
                    markerLabel(marker)
                }
            }
        }
    }

    private func markerLabel(_ marker: CircadianMarker) -> some View {
        HStack(spacing: ZenithiumSpacing.xs) {
            Image(systemName: marker.event.symbolName)
                .imageScale(.small)
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ZenithiumSpacing.none) {
                Text(marker.event.shortName)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Text(marker.date, format: .dateTime.hour().minute())
                    .font(ZenithiumFont.caption.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marker.event.displayName)
        .accessibilityValue(
            Text(marker.date, format: .dateTime.hour().minute())
        )
    }

    private var curveAccessibilityValue: String {
        guard let peak = arc.marker(for: .morningPeak),
              let dip = arc.marker(for: .afternoonDip) else {
            return "Bugünün uyanıklık eğrisi"
        }
        let formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        var value = "Zirve yaklaşık \(peak.date.formatted(formatter)), çukur yaklaşık \(dip.date.formatted(formatter))"
        if arc.amplitudeScale < 1 {
            // §5.5 — the curve is flattened on a low-recovery day. Saying so is the difference
            // between a chart that looks wrong and one that explains itself.
            value += ". Bugün toparlanma düşük olduğu için eğri basıklaştırıldı."
        }
        return value
    }
}
