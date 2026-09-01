//
//  CircadianEngine.swift
//  Zenithium
//
//  The circadian alertness arc. Spec §5.5 in full.
//
//  Anchors are placed relative to the sleep midpoint (or wake time, ASSUMPTION CIRC-1) and
//  interpolated with monotone cubic Hermite in circular 24-hour space. The anchor set is
//  duplicated at ±24 h before fitting, which makes the wrap seam C¹-continuous instead of a
//  visible kink at the arbitrary point the day happens to start.
//
//  Worked example (§5.5): sleepStart 23:30, duration 7.5 h → Mid 03:15
//  → peak 07:45 · dip 11:15 · secondary 14:45 · melatonin 18:15.
//

import Foundation

enum CircadianEngine {

    static func arc(_ input: CircadianInput) -> CircadianArc {
        let midpoint = input.sleepStart.addingTimeInterval(input.sleepDuration / 2)
        let reference: Date
        switch input.anchors.reference {
        case .sleepMidpoint: reference = midpoint
        case .wakeTime: reference = input.wakeTime
        }

        let scale = amplitudeScale(forRecovery: input.recoveryScore)
        let anchors = input.anchors.anchors.sorted { $0.offsetHours < $1.offsetHours }

        guard let interpolator = makeInterpolator(for: anchors) else {
            // A degenerate anchor set produces no curve rather than a wrong one.
            return CircadianArc(
                midpoint: midpoint,
                referenceDate: reference,
                samples: [],
                markers: [],
                amplitudeScale: scale,
                peakAlertness: 0
            )
        }

        let step = input.sampleInterval ?? EngineConstants.Circadian.sampleIntervalSeconds
        let samples = sample(
            interpolator: interpolator,
            anchors: anchors,
            reference: reference,
            window: input.renderWindow,
            step: max(step, 60),
            scale: scale
        )

        let markers = self.markers(
            for: anchors,
            reference: reference,
            window: input.renderWindow,
            scale: scale
        )

        return CircadianArc(
            midpoint: midpoint,
            referenceDate: reference,
            samples: samples,
            markers: markers,
            amplitudeScale: scale,
            peakAlertness: samples.map(\.alertness).max() ?? 0
        )
    }

    /// §5.5 — `amplitude = 0.7 + 0.3 · (Recovery/100)`.
    ///
    /// ASSUMPTION CIRC-3: the scale multiplies alertness rather than compressing it toward a
    /// midline. A low-recovery day therefore dulls the whole curve, peaks and troughs alike,
    /// and the curve can never exceed 100 for any recovery value — which is the property §11
    /// asserts. With no recovery score the curve is unscaled.
    static func amplitudeScale(forRecovery recovery: Double?) -> Double {
        guard let recovery else { return 1.0 }
        let fraction = MathSupport.clamp(recovery / 100, 0, 1)
        return EngineConstants.Circadian.amplitudeBase
            + EngineConstants.Circadian.amplitudeRecoveryCoefficient * fraction
    }

    /// Fits the spline over the anchor set duplicated at −24 h and +24 h.
    ///
    /// The duplication is what makes the curve circular: evaluating anywhere inside the
    /// middle period sees real neighbours on both sides, so the tangent at the seam is the
    /// same approaching from either direction.
    private static func makeInterpolator(
        for anchors: [CircadianAnchor]
    ) -> MonotoneCubicInterpolator? {
        guard anchors.count >= 2 else { return nil }
        let period = EngineConstants.Circadian.periodHours
        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(anchors.count * 3)
        for shift in [-period, 0, period] {
            for anchor in anchors {
                points.append((x: anchor.offsetHours + shift, y: anchor.alertness))
            }
        }
        return MonotoneCubicInterpolator(points: points)
    }

    /// Samples the curve across the render window.
    private static func sample(
        interpolator: MonotoneCubicInterpolator,
        anchors: [CircadianAnchor],
        reference: Date,
        window: DateInterval,
        step: TimeInterval,
        scale: Double
    ) -> [CircadianSample] {
        guard window.duration > 0, let firstOffset = anchors.first?.offsetHours else { return [] }
        let period = EngineConstants.Circadian.periodHours

        var samples: [CircadianSample] = []
        samples.reserveCapacity(Int(window.duration / step) + 1)

        var cursor = window.start
        while cursor <= window.end {
            let rawOffset = TimeConversion.hours(fromSeconds: cursor.timeIntervalSince(reference))
            // Fold the query into the period the anchors actually cover, so the evaluation
            // always lands in the interpolated middle copy rather than being clamped at an end.
            let folded = firstOffset + MathSupport.wrap(rawOffset - firstOffset, period: period)
            let value = interpolator.value(at: folded) * scale
            samples.append(
                CircadianSample(
                    date: cursor,
                    alertness: MathSupport.clamp(value, 0, EngineConstants.Circadian.maxAlertness)
                )
            )
            cursor = cursor.addingTimeInterval(step)
        }
        return samples
    }

    /// Places each anchor at its absolute instant inside the render window.
    ///
    /// An anchor whose natural instant falls outside the window is shifted by whole days
    /// until it lands inside, so the arc always carries all six markers.
    private static func markers(
        for anchors: [CircadianAnchor],
        reference: Date,
        window: DateInterval,
        scale: Double
    ) -> [CircadianMarker] {
        let day = TimeConversion.secondsPerDay
        var markers: [CircadianMarker] = []

        for event in CircadianEvent.chartOrder {
            guard let anchor = anchors.first(where: { $0.event == event }) else { continue }
            var date = reference.addingTimeInterval(
                TimeConversion.seconds(fromHours: anchor.offsetHours)
            )
            var guardCounter = 0
            while date < window.start, guardCounter < 3 {
                date = date.addingTimeInterval(day)
                guardCounter += 1
            }
            while date > window.end, guardCounter < 6 {
                date = date.addingTimeInterval(-day)
                guardCounter += 1
            }
            markers.append(
                CircadianMarker(
                    event: event,
                    date: date,
                    alertness: MathSupport.clamp(
                        anchor.alertness * scale,
                        0,
                        EngineConstants.Circadian.maxAlertness
                    )
                )
            )
        }
        return markers.sorted { $0.date < $1.date }
    }
}
