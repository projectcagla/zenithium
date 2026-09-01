//
//  StressIO.swift
//  Zenithium
//
//  Types crossing the intraday-stress boundary. Faz 13.
//
//  The point of this layer is one sentence: "Strain 8.2" means nothing to somebody who did
//  not train. Splitting the day's load into the part that came from a session and the part
//  that came from the rest of life is what makes the number legible to them — and it is
//  useful to an athlete too, because a stressful Tuesday and an easy run are not the same
//  8.2 even though the engine scores them alike.
//
//  §12: elevated heart rate outside a workout is called *load*, never stress in the clinical
//  sense and never a health finding. Zenithium describes the pattern of the day and stops.
//

import Foundation

/// One bucket of the day.
struct StressInterval: Sendable, Equatable, Hashable, Identifiable {

    let start: Date
    let end: Date

    /// Mean heart rate over the bucket.
    let heartRate: Double

    /// How far above resting, as a fraction of heart-rate reserve, 0…1.
    let reserveFraction: Double

    /// Whether a logged workout overlapped this bucket.
    let isWorkout: Bool

    var id: Date { start }

    /// The band this bucket sits in.
    var band: StressBand {
        isWorkout ? .training : StressBand.band(forReserveFraction: reserveFraction)
    }
}

/// How a bucket reads.
enum StressBand: String, Sendable, Hashable, CaseIterable {

    /// At or near resting.
    case restful

    /// Ordinary waking activity.
    case ordinary

    /// Sustained elevation with no session behind it.
    case elevated

    /// A logged workout.
    case training

    static func band(forReserveFraction fraction: Double) -> StressBand {
        switch fraction {
        case ..<0.10: return .restful
        case ..<0.25: return .ordinary
        default: return .elevated
        }
    }

    var displayName: String {
        switch self {
        case .restful: return "Dinlenik"
        case .ordinary: return "Olağan"
        case .elevated: return "Yükselmiş"
        case .training: return "Antrenman"
        }
    }
}

/// A stretch of the day spent at or near resting.
struct RecoveryWindow: Sendable, Equatable, Hashable, Identifiable {

    let start: Date
    let end: Date

    /// Mean heart rate across the window.
    let heartRate: Double

    var id: Date { start }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// The whole day, split.
struct StressDay: Sendable, Equatable {

    /// Buckets across the day, in order.
    let intervals: [StressInterval]

    /// Load accumulated inside logged workouts, on the TRIMP scale.
    let trainingLoad: Double

    /// Load accumulated outside them.
    let nonTrainingLoad: Double

    /// The calmest stretches of the day, longest first.
    let recoveryWindows: [RecoveryWindow]

    /// Seconds spent in each band.
    let secondsByBand: [StressBand: Double]

    /// Training's share of the day's total load. `nil` when there was no load at all.
    var trainingShare: Double? {
        let total = trainingLoad + nonTrainingLoad
        return total > 0 ? trainingLoad / total : nil
    }

    /// The sentence that makes the day's number legible.
    var summary: String {
        guard let share = trainingShare else {
            return "Bugün ölçülebilir bir yük birikmedi."
        }
        if trainingLoad <= 0 {
            return "Bugünkü yükün tamamı antrenman dışından geldi — hareket, iş, gün."
        }
        if share >= 0.85 {
            return "Bugünkü yükün neredeyse tamamı antrenmandan (\(ZenithiumFormat.percentTR(share)))."
        }
        return "Bugünkü yükün \(ZenithiumFormat.percentTR(share))'i antrenmandan, kalanı günün geri kalanından."
    }

    static let empty = StressDay(
        intervals: [],
        trainingLoad: 0,
        nonTrainingLoad: 0,
        recoveryWindows: [],
        secondsByBand: [:]
    )
}
