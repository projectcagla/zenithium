//
//  LiveSessionIO.swift
//  Zenithium
//
//  What the live session screen reads and writes. Yol haritası v4, C1.
//

import Foundation

/// One heart-rate reading during a session.
struct LiveHeartRateSample: Sendable, Equatable, Hashable, Codable {

    /// Seconds since the session started.
    let elapsedSeconds: Double

    /// Beats per minute.
    let beatsPerMinute: Double
}

/// Everything the live engine needs to say where the session stands.
struct LiveSessionInput: Sendable, Equatable {

    /// How long the session has been running, seconds.
    let elapsedSeconds: Double

    /// Readings so far, oldest first.
    let samples: [LiveHeartRateSample]

    let restingHeartRate: Double
    let maxHeartRate: Double
    let biologicalSex: BiologicalSexValue

    /// Strain already on the clock before this session began — what the phone's snapshot
    /// said when the watch started.
    let strainBeforeSession: Double

    /// Today's prescribed ceiling, when the prescription engine produced one.
    let ceiling: Double?
}

/// Where the session stands right now.
struct LiveSessionOutput: Sendable, Equatable {

    /// The session's own accumulated impulse.
    let sessionTRIMP: Double

    /// What the day's strain would read if the session stopped now.
    let dayStrain: Double

    /// How much of that the session itself put there.
    let strainAddedBySession: Double

    /// The most recent reading's fraction of heart-rate reserve.
    let currentReserveFraction: Double

    /// The session's average fraction of reserve so far.
    let averageReserveFraction: Double

    /// Where the day sits against the ceiling, 0…1 and beyond. `nil` without a ceiling.
    let ceilingProgress: Double?

    /// How long until the ceiling is reached at the current rate, seconds.
    ///
    /// `nil` when there is no ceiling, when it has already been passed, or when the recent
    /// effort is too light to reach it at all — an easy jog does not arrive at a hard day's
    /// ceiling eventually, it never arrives, and saying "4 hours" would be arithmetic
    /// pretending to be advice.
    let secondsToCeiling: Double?

    /// What the screen says about where this sits.
    let band: LiveSessionBand
}

/// How the session reads against the day's ceiling.
enum LiveSessionBand: String, Sendable, Hashable, CaseIterable, Codable {

    /// Well inside the day's room.
    case building

    /// Approaching the ceiling.
    case nearing

    /// At or past it.
    case beyond

    /// No ceiling was prescribed, so there is nothing to be near or beyond.
    case unbounded

    var displayName: String {
        switch self {
        case .building: return "Birikiyor"
        case .nearing: return "Tavana yaklaşıyor"
        case .beyond: return "Tavanın üstünde"
        case .unbounded: return "Kayıtta"
        }
    }

    /// One line, in the app's voice: what this is, not what to do about it.
    ///
    /// §12 and §1 both apply on this screen more than anywhere else, because it is read
    /// mid-effort. It reports where the day stands. It does not tell anyone to stop.
    var summary: String {
        switch self {
        case .building: return "Günün tavanının altındasın."
        case .nearing: return "Günün tavanına yaklaştın."
        case .beyond: return "Bugün için önerilen tavanın üstündesin."
        case .unbounded: return "Bugün için bir tavan hesaplanmadı."
        }
    }
}
