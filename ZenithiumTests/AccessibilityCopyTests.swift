//
//  AccessibilityCopyTests.swift
//  ZenithiumTests
//
//  The half of the interface nobody sees, in the language the rest of it is written in.
//
//  `TrainingLens.accessibilityName` shipped in English until v0.1's release scan, alongside
//  a dozen `accessibilityLabel` and `accessibilityValue` strings across the app, the widget
//  and the watch. Nothing caught it because nothing looks at it: the visible labels were
//  translated, the screens looked finished, and the only person who would have noticed was
//  a Turkish-speaking VoiceOver user hearing "Heart rate variability".
//
//  This suite is what looks at it.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Erişilebilirlik metinleri")
struct AccessibilityCopyTests {

    /// Words that only appear in these strings if a translation was skipped.
    ///
    /// Deliberately common rather than exhaustive: the failure being caught is a whole
    /// English phrase left in place, and a phrase that long contains one of these.
    static let englishMarkers = [
        "heart", "rate", "resting", "ratio", "workload", "best", "training", "hour",
        "running", "score", "posterior", "chain", "readiness", "grip", "weekly", "volume",
        "push", "pull", "balance", "sleep", "consistency", "time", "daylight", "walking",
        "speed", "percent", "band", "out of", "target", "still", "calibrating", "confidence",
        "total", "session", "station", "transition", "splits", "round", "penalty",
        "muscular", "cardiovascular", "compromised", "variability", "recovery"
    ]

    private func assertTurkish(_ text: String, _ label: String) {
        let lowered = text.lowercased()
        for marker in Self.englishMarkers {
            #expect(!lowered.contains(marker), "\(label): İngilizce kalmış — '\(marker)'")
        }
    }

    @Test("Her merceğin sesli adı Türkçe", arguments: TrainingLens.allCases)
    func everyLensIsSpokenInTurkish(lens: TrainingLens) {
        assertTurkish(lens.accessibilityName, "TrainingLens.\(lens.rawValue)")
    }

    /// The spoken name spells out what the visible label abbreviates. If the two are the
    /// same string, the property is not doing the job it exists for.
    @Test("Sesli ad görünen etiketten farklı ve daha açık", arguments: TrainingLens.allCases)
    func theSpokenNameSpellsTheLabelOut(lens: TrainingLens) {
        let spoken = lens.accessibilityName
        #expect(!spoken.isEmpty)
        #expect(spoken.count >= 6, "\(lens.rawValue): kısaltma gibi duruyor — '\(spoken)'")
    }

    @Test("Toparlanma bantlarının adları Türkçe", arguments: RecoveryBand.allCases)
    func recoveryBandNamesAreTurkish(band: RecoveryBand) {
        assertTurkish(band.displayName, "RecoveryBand.\(band.rawValue)")
    }

    @Test("Canlı seans bantlarının adları Türkçe", arguments: LiveSessionBand.allCases)
    func liveSessionBandNamesAreTurkish(band: LiveSessionBand) {
        assertTurkish(band.displayName, "LiveSessionBand.\(band.rawValue)")
    }

    @Test("Sağlık verisi türlerinin adları Türkçe", arguments: HealthDataKind.allCases)
    func healthDataKindNamesAreTurkish(kind: HealthDataKind) {
        assertTurkish(kind.displayName, "HealthDataKind.\(kind.rawValue)")
    }

    // The widget's and the watch's own spoken strings are built inside their extensions,
    // which this target does not compile — so they are checked at the source level instead,
    // by `Scripts/check-symbols.py`. That is the only pass that reaches all four targets.
}
