//
//  CircadianIO.swift
//  Zenithium
//
//  Circadian engine input and output. Spec §5.5 in full.
//  ASSUMPTION CIRC-1: the anchor set is injectable, because §5.5 flags the midpoint-relative
//  afternoon dip as a spec risk. ASSUMPTION CIRC-2: 5-minute sampling, circular wrap.
//

import Foundation

/// A named point on the alertness curve (§5.5).
enum CircadianEvent: String, Sendable, Codable, CaseIterable, Hashable {
    case wakeInertiaEnd
    case morningPeak
    case afternoonDip
    case secondaryPeak
    case melatoninOnset
    case sleepTrough

    var displayName: String {
        switch self {
        case .wakeInertiaEnd: return "Uyanma ataleti biter"
        case .morningPeak: return "Sabah zirvesi"
        case .afternoonDip: return "Öğleden sonra çukuru"
        case .secondaryPeak: return "İkinci zirve"
        case .melatoninOnset: return "Melatonin başlangıcı"
        case .sleepTrough: return "Uyku dibi"
        }
    }

    var shortName: String {
        switch self {
        case .wakeInertiaEnd: return "Uyanış"
        case .morningPeak: return "Zirve"
        case .afternoonDip: return "Çukur"
        case .secondaryPeak: return "2. zirve"
        case .melatoninOnset: return "Melatonin"
        case .sleepTrough: return "Dip"
        }
    }

    var symbolName: String {
        switch self {
        case .wakeInertiaEnd: return "sunrise"
        case .morningPeak: return "sun.max.fill"
        case .afternoonDip: return "cloud.sun"
        case .secondaryPeak: return "sun.min.fill"
        case .melatoninOnset: return "moon.stars"
        case .sleepTrough: return "moon.zzz.fill"
        }
    }

    /// Whether the marker is drawn on the arc by default. All six are; the flag exists so a
    /// compact widget can drop the minor ones without a second table.
    var isMajor: Bool {
        switch self {
        case .morningPeak, .afternoonDip, .melatoninOnset: return true
        case .wakeInertiaEnd, .secondaryPeak, .sleepTrough: return false
        }
    }

    /// Which markers appear on a scrubbable label, in chart order.
    static let chartOrder: [CircadianEvent] = [
        .wakeInertiaEnd, .morningPeak, .afternoonDip, .secondaryPeak, .melatoninOnset, .sleepTrough
    ]
}

/// One anchor: an offset from a reference instant, and the normalized alertness there.
struct CircadianAnchor: Sendable, Equatable, Hashable {

    let event: CircadianEvent

    /// Hours after the reference instant (§5.5).
    let offsetHours: Double

    /// Normalized alertness at the anchor, 0…100 (§5.5).
    let alertness: Double

    init(event: CircadianEvent, offsetHours: Double, alertness: Double) {
        self.event = event
        self.offsetHours = offsetHours
        self.alertness = alertness
    }
}

/// What the anchor offsets are measured from (ASSUMPTION CIRC-1).
enum CircadianReference: String, Sendable, Codable, CaseIterable, Hashable {

    /// Offsets are measured from the sleep midpoint. The specification's default (§5.5).
    case sleepMidpoint

    /// Offsets are measured from wake time. Provided so the flagged spec risk can be
    /// re-anchored without touching the engine.
    case wakeTime

    var displayName: String {
        switch self {
        case .sleepMidpoint: return "Uyku orta noktası"
        case .wakeTime: return "Uyanma saati"
        }
    }
}

/// An injectable anchor set (ASSUMPTION CIRC-1).
///
/// The concrete presets live in `Engines/EngineConstants.swift` so every number stays in the
/// engine layer; this type only carries them.
struct CircadianAnchors: Sendable, Equatable, Hashable {

    /// The anchors, which the engine sorts by offset before fitting.
    let anchors: [CircadianAnchor]

    /// What `offsetHours` is measured from.
    let reference: CircadianReference

    init(anchors: [CircadianAnchor], reference: CircadianReference) {
        self.anchors = anchors
        self.reference = reference
    }

    /// The anchor for one event, when the set contains it.
    func anchor(for event: CircadianEvent) -> CircadianAnchor? {
        anchors.first { $0.event == event }
    }
}

/// Everything the circadian engine needs.
struct CircadianInput: Sendable, Equatable {

    /// Start of the longest contiguous asleep block, naps excluded (§5.5).
    let sleepStart: Date

    /// Duration of that block.
    let sleepDuration: TimeInterval

    /// Wake time — the end of the same block. Used when `anchors.reference == .wakeTime`.
    let wakeTime: Date

    /// Today's recovery score, scaling the whole curve's amplitude by
    /// `0.7 + 0.3·(Recovery/100)` (§5.5). `nil` uses the unscaled curve.
    let recoveryScore: Double?

    /// The anchor set to fit (ASSUMPTION CIRC-1).
    let anchors: CircadianAnchors

    /// The window to render, normally the physiological day.
    let renderWindow: DateInterval

    /// Spacing between generated samples. `nil` uses the engine default of 5 minutes
    /// (ASSUMPTION CIRC-2).
    let sampleInterval: TimeInterval?

    init(
        sleepStart: Date,
        sleepDuration: TimeInterval,
        wakeTime: Date,
        recoveryScore: Double?,
        anchors: CircadianAnchors,
        renderWindow: DateInterval,
        sampleInterval: TimeInterval?
    ) {
        self.sleepStart = sleepStart
        self.sleepDuration = sleepDuration
        self.wakeTime = wakeTime
        self.recoveryScore = recoveryScore
        self.anchors = anchors
        self.renderWindow = renderWindow
        self.sampleInterval = sampleInterval
    }
}

/// One point on the rendered arc.
struct CircadianSample: Sendable, Equatable, Hashable {

    let date: Date

    /// Alertness, 0…100 after amplitude scaling.
    let alertness: Double

    init(date: Date, alertness: Double) {
        self.date = date
        self.alertness = alertness
    }
}

/// A named marker placed on the arc.
struct CircadianMarker: Sendable, Equatable, Hashable, Identifiable {

    let event: CircadianEvent

    /// The absolute instant the event falls at.
    let date: Date

    /// Alertness at the marker, after amplitude scaling.
    let alertness: Double

    init(event: CircadianEvent, date: Date, alertness: Double) {
        self.event = event
        self.date = date
        self.alertness = alertness
    }

    var id: CircadianEvent { event }
}

/// The circadian engine's result.
struct CircadianArc: Sendable, Equatable {

    /// `Mid = sleepStart + duration/2` (§5.5).
    let midpoint: Date

    /// The instant offsets were measured from, which is `midpoint` or wake time depending on
    /// the anchor set's reference (ASSUMPTION CIRC-1).
    let referenceDate: Date

    /// The sampled curve across the render window, ascending by date.
    let samples: [CircadianSample]

    /// The six markers, in chart order.
    let markers: [CircadianMarker]

    /// `0.7 + 0.3·(Recovery/100)` (§5.5).
    let amplitudeScale: Double

    /// The highest alertness in `samples`. Must never exceed 100 (§11, PCHIP no-overshoot).
    let peakAlertness: Double

    init(
        midpoint: Date,
        referenceDate: Date,
        samples: [CircadianSample],
        markers: [CircadianMarker],
        amplitudeScale: Double,
        peakAlertness: Double
    ) {
        self.midpoint = midpoint
        self.referenceDate = referenceDate
        self.samples = samples
        self.markers = markers
        self.amplitudeScale = amplitudeScale
        self.peakAlertness = peakAlertness
    }

    /// The marker for one event, when the arc carries it.
    func marker(for event: CircadianEvent) -> CircadianMarker? {
        markers.first { $0.event == event }
    }

    /// Alertness at an instant, by nearest sample. `nil` when the arc is empty or the
    /// instant is outside the rendered window.
    func alertness(at date: Date) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        guard date >= first.date, date <= last.date else { return nil }
        var nearest = first
        var nearestDistance = abs(first.date.timeIntervalSince(date))
        for sample in samples.dropFirst() {
            let distance = abs(sample.date.timeIntervalSince(date))
            if distance < nearestDistance {
                nearest = sample
                nearestDistance = distance
            }
        }
        return nearest.alertness
    }
}
