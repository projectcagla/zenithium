//
//  CircadianEngineTests.swift
//  ZenithiumTests
//
//  Spec §11 golden vector 4 and the PCHIP no-overshoot requirement.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Circadian engine")
struct CircadianEngineTests {

    /// §5.5 worked example: sleepStart 23:30, duration 7.5 h → Mid 03:15.
    private let sleepStart = iso("2025-06-01T23:30:00Z")
    private let duration: TimeInterval = 7.5 * 3600

    private var wakeTime: Date { sleepStart.addingTimeInterval(duration) }
    private var midpoint: Date { sleepStart.addingTimeInterval(duration / 2) }

    private func arc(
        recovery: Double? = nil,
        anchors: CircadianAnchors = EngineConstants.Circadian.defaultAnchors
    ) -> CircadianArc {
        CircadianEngine.arc(
            CircadianInput(
                sleepStart: sleepStart,
                sleepDuration: duration,
                wakeTime: wakeTime,
                recoveryScore: recovery,
                anchors: anchors,
                renderWindow: DateInterval(
                    start: midpoint,
                    end: midpoint.addingTimeInterval(TimeConversion.secondsPerDay)
                ),
                sampleInterval: nil
            )
        )
    }

    // MARK: - §11 golden vector 4

    @Test("Golden vector 4 — the midpoint is 03:15")
    func goldenMidpoint() {
        #expect(arc().midpoint == iso("2025-06-02T03:15:00Z"))
    }

    @Test(
        "Golden vector 4 — every marker lands where the specification says",
        arguments: [
            (CircadianEvent.wakeInertiaEnd, "2025-06-02T05:15:00Z"),
            (CircadianEvent.morningPeak, "2025-06-02T07:45:00Z"),
            (CircadianEvent.afternoonDip, "2025-06-02T11:15:00Z"),
            (CircadianEvent.secondaryPeak, "2025-06-02T14:45:00Z"),
            (CircadianEvent.melatoninOnset, "2025-06-02T18:15:00Z"),
            (CircadianEvent.sleepTrough, "2025-06-02T21:45:00Z")
        ]
    )
    func goldenMarkers(event: CircadianEvent, expected: String) {
        let marker = arc().marker(for: event)
        #expect(marker != nil, "\(event.rawValue) marker missing")
        #expect(marker?.date == iso(expected), "\(event.rawValue)")
    }

    @Test("Marker alertness matches the anchor table")
    func markerAlertness() {
        let result = arc()
        expectClose(result.marker(for: .wakeInertiaEnd)?.alertness ?? .nan, 55, tolerance: 1e-9, "wake inertia end")
        expectClose(result.marker(for: .morningPeak)?.alertness ?? .nan, 100, tolerance: 1e-9, "morning peak")
        expectClose(result.marker(for: .afternoonDip)?.alertness ?? .nan, 62, tolerance: 1e-9, "afternoon dip")
        expectClose(result.marker(for: .secondaryPeak)?.alertness ?? .nan, 88, tolerance: 1e-9, "secondary peak")
        expectClose(result.marker(for: .melatoninOnset)?.alertness ?? .nan, 30, tolerance: 1e-9, "melatonin onset")
        expectClose(result.marker(for: .sleepTrough)?.alertness ?? .nan, 8, tolerance: 1e-9, "sleep trough")
    }

    // MARK: - §11 PCHIP no overshoot

    @Test("The arc never exceeds 100 anywhere")
    func arcNeverOvershoots() {
        let result = arc()
        #expect(!result.samples.isEmpty)
        for sample in result.samples {
            #expect(sample.alertness <= EngineConstants.Circadian.maxAlertness)
            #expect(sample.alertness >= 0)
        }
        // The peak is reached exactly, not exceeded — which is the property Catmull-Rom
        // would break and PCHIP guarantees.
        expectClose(result.peakAlertness, 100, tolerance: 0.001, "peak")
    }

    @Test("The arc stays bounded at every recovery level", arguments: [0.0, 1.0, 33.0, 67.0, 90.0, 100.0])
    func boundedAtEveryRecovery(recovery: Double) {
        let result = arc(recovery: recovery)
        for sample in result.samples {
            #expect(sample.alertness <= EngineConstants.Circadian.maxAlertness)
            #expect(sample.alertness >= 0)
        }
    }

    @Test("A raw PCHIP fit does not overshoot its knots either")
    func interpolatorDoesNotOvershoot() {
        let anchors = EngineConstants.Circadian.defaultAnchors.anchors
        var points: [(x: Double, y: Double)] = []
        for shift in [-24.0, 0.0, 24.0] {
            for anchor in anchors {
                points.append((x: anchor.offsetHours + shift, y: anchor.alertness))
            }
        }
        guard let spline = MonotoneCubicInterpolator(points: points) else {
            Issue.record("Interpolator could not be fitted")
            return
        }
        let maximum = spline.maximumKnotValue
        for step in stride(from: -20.0, through: 40.0, by: 0.05) {
            let value = spline.value(at: step)
            #expect(value <= maximum + 1e-9)
            #expect(value >= 8 - 1e-9)
        }
    }

    @Test("The wrap seam is continuous in value")
    func wrapSeamIsContinuous() {
        let anchors = EngineConstants.Circadian.defaultAnchors.anchors
        var points: [(x: Double, y: Double)] = []
        for shift in [-24.0, 0.0, 24.0] {
            for anchor in anchors {
                points.append((x: anchor.offsetHours + shift, y: anchor.alertness))
            }
        }
        guard let spline = MonotoneCubicInterpolator(points: points),
              let first = anchors.map(\.offsetHours).min() else {
            Issue.record("Interpolator could not be fitted")
            return
        }
        // The same instant approached from either side of the seam.
        expectClose(
            spline.value(at: first + 24),
            spline.value(at: first),
            tolerance: 1e-6,
            "seam value"
        )
    }

    // MARK: - §5.5 amplitude

    @Test("Amplitude scales as 0.7 + 0.3·(Recovery/100)")
    func amplitudeScale() {
        expectClose(CircadianEngine.amplitudeScale(forRecovery: 0), 0.7, tolerance: 1e-9, "recovery 0")
        expectClose(CircadianEngine.amplitudeScale(forRecovery: 50), 0.85, tolerance: 1e-9, "recovery 50")
        expectClose(CircadianEngine.amplitudeScale(forRecovery: 100), 1.0, tolerance: 1e-9, "recovery 100")
        // With no recovery score the curve is unscaled rather than suppressed.
        expectClose(CircadianEngine.amplitudeScale(forRecovery: nil), 1.0, tolerance: 1e-9, "no score")
    }

    @Test("A low-recovery day flattens the whole curve")
    func lowRecoveryFlattens() {
        let full = arc(recovery: 100)
        let low = arc(recovery: 20)
        #expect(low.peakAlertness < full.peakAlertness)
        expectClose(low.amplitudeScale, 0.76, tolerance: 1e-9, "scale at recovery 20")
    }

    // MARK: - ASSUMPTION CIRC-1 injectable anchors

    @Test("The wake-anchored preset re-references the same six events")
    func wakeAnchoredPreset() {
        let wakeAnchored = arc(anchors: EngineConstants.Circadian.wakeAnchors)
        #expect(wakeAnchored.referenceDate == wakeTime)
        #expect(wakeAnchored.markers.count == CircadianEvent.allCases.count)

        // The whole point of the flagged spec risk: re-anchoring moves the dip later.
        let defaultDip = arc().marker(for: .afternoonDip)?.date
        let wakeDip = wakeAnchored.marker(for: .afternoonDip)?.date
        #expect(defaultDip != nil && wakeDip != nil)
        if let defaultDip, let wakeDip {
            #expect(wakeDip > defaultDip)
        }
    }

    @Test("A degenerate anchor set produces no curve rather than a wrong one")
    func degenerateAnchors() {
        let single = CircadianAnchors(
            anchors: [CircadianAnchor(event: .morningPeak, offsetHours: 4.5, alertness: 100)],
            reference: .sleepMidpoint
        )
        let result = arc(anchors: single)
        #expect(result.samples.isEmpty)
        #expect(result.peakAlertness == 0)
    }

    @Test("Sampling covers the render window at five-minute resolution")
    func samplingResolution() {
        let result = arc()
        // 24 hours at 300 s, inclusive of both ends.
        #expect(result.samples.count == 289)
        #expect(result.samples.first?.date == midpoint)
    }
}
