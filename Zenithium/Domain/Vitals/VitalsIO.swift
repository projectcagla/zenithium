//
//  VitalsIO.swift
//  Zenithium
//
//  Types crossing the vitals boundary. Faz 11 and Faz 28.
//

import Foundation

/// One daily value of one vital sign.
struct VitalSample: Sendable, Equatable, Hashable, Identifiable {

    let sign: VitalSign
    let dayStart: Date
    let value: Double

    var id: String { "\(sign.rawValue)-\(dayStart.timeIntervalSince1970)" }
}

/// One vital sign's history and where today sits in it.
struct VitalReading: Sendable, Equatable, Hashable, Identifiable {

    let sign: VitalSign

    /// The most recent value, and when it was recorded.
    let latest: VitalSample?

    /// The baseline mean over the sign's own window.
    let baselineMean: Double?

    /// The baseline standard deviation. Floored, so a flat history cannot produce an
    /// infinite z-score.
    let baselineDeviation: Double?

    /// `(latest − mean) / deviation`, when both exist.
    let zScore: Double?

    /// The history, oldest first, for the sparkline.
    let history: [VitalSample]

    var id: String { sign.rawValue }

    /// Whether there is anything at all to show.
    var hasData: Bool { latest != nil }

    /// How far from baseline, in plain words. Never a verdict (§12).
    var deviationLabel: String? {
        guard let zScore else { return nil }
        let magnitude = abs(zScore)
        guard magnitude >= 1 else { return "taban çizginde" }
        let direction = zScore > 0 ? "üstünde" : "altında"
        if magnitude >= 2 { return "taban çizginin belirgin \(direction)" }
        return "taban çizginin biraz \(direction)"
    }
}

/// How unusual this morning looks across several signals at once.
///
/// Faz 28. The idea is old and well-supported: a single metric moving is noise, several
/// moving the same way at once is a signal. What Zenithium is allowed to do with that is
/// narrow — it reports that the morning is outside the recent range and how, and it never
/// names a cause.
struct DeviationScore: Sendable, Equatable, Hashable {

    /// The signals that contributed, with their z-scores, strongest first.
    let contributors: [Contributor]

    /// Root-mean-square of the contributing z-scores, sign-corrected so that every
    /// contributor points the same way: positive means "away from your fit direction".
    let magnitude: Double

    /// How many signals had enough history to take part.
    let availableSignals: Int

    struct Contributor: Sendable, Equatable, Hashable, Identifiable {
        let sign: VitalSign

        /// The raw z-score, in the sign's own direction.
        let zScore: Double

        /// The z-score turned so that positive always means "moved away from the fitter
        /// direction". This is what makes summing across signals meaningful — an HRV drop
        /// and a resting-heart-rate rise are the same story told with opposite signs.
        let orientedZ: Double

        var id: String { sign.rawValue }
    }

    /// Bands for the magnitude. Descriptive only.
    enum Level: String, Sendable, Hashable {
        case typical
        case notable
        case marked

        var displayName: String {
            switch self {
            case .typical: return "Olağan"
            case .notable: return "Dikkat çekici"
            case .marked: return "Belirgin"
            }
        }
    }

    var level: Level {
        switch magnitude {
        case ..<1.0: return .typical
        case ..<1.8: return .notable
        default: return .marked
        }
    }

    /// Whether the score is worth surfacing at all.
    ///
    /// Two conditions, and both matter. One signal moving two deviations is a bad sensor
    /// night as often as anything else, so at least two must agree; and they must agree in
    /// *direction*, which is what `orientedZ` makes checkable.
    var isWorthReporting: Bool {
        let agreeing = contributors.filter { $0.orientedZ >= 1.0 }
        return agreeing.count >= 2 && magnitude >= 1.0
    }

    static let none = DeviationScore(contributors: [], magnitude: 0, availableSignals: 0)
}
