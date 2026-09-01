//
//  RecoveryBand.swift
//  Zenithium
//
//  Recovery colour bands. Spec §5.1 (Red 1–33 · Yellow 34–66 · Green 67–100),
//  §10 accessibility gate and ASSUMPTION UI-2: never colour-only — every band carries a
//  glyph and a text label as well.
//

import Foundation

/// The three recovery bands.
enum RecoveryBand: String, Sendable, Codable, CaseIterable, Hashable {
    case red
    case yellow
    case green

    /// Spec §5.1 — the inclusive upper bound of the red band.
    static let redUpperBound: Double = 33

    /// Spec §5.1 — the inclusive upper bound of the yellow band.
    static let yellowUpperBound: Double = 66

    /// Classifies a recovery score in 1…100.
    static func band(forScore score: Double) -> RecoveryBand {
        if score <= redUpperBound { return .red }
        if score <= yellowUpperBound { return .yellow }
        return .green
    }

    var displayName: String {
        switch self {
        case .red: return "Kırmızı"
        case .yellow: return "Sarı"
        case .green: return "Yeşil"
        }
    }

    /// The non-colour half of the encoding (ASSUMPTION UI-2).
    var glyph: String {
        switch self {
        case .red: return "■"
        case .yellow: return "▲"
        case .green: return "●"
        }
    }

    /// SF Symbol paired with the band, so the encoding survives greyscale and colour blindness.
    var symbolName: String {
        switch self {
        case .red: return "moon.zzz.fill"
        case .yellow: return "figure.walk"
        case .green: return "bolt.fill"
        }
    }

    /// The inclusive score range the band covers.
    var scoreRange: ClosedRange<Double> {
        switch self {
        case .red: return 1...RecoveryBand.redUpperBound
        case .yellow: return (RecoveryBand.redUpperBound + 1)...RecoveryBand.yellowUpperBound
        case .green: return (RecoveryBand.yellowUpperBound + 1)...100
        }
    }
}
