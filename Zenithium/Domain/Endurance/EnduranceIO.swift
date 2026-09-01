//
//  EnduranceIO.swift
//  Zenithium
//
//  Types crossing the endurance boundary. Faz 15.
//
//  The organising idea is the critical-speed model, because everything else on the endurance
//  screen can be derived from it rather than guessed. Two parameters — a speed you can hold
//  more or less indefinitely, and a fixed distance you can spend above it — fit to your own
//  best efforts. From those come pace zones, a race prediction, and an answer to "was that
//  session as good as it felt".
//
//  §12 has little to say here; none of this is health. What it does govern is the honesty
//  requirement that runs through the whole app: every derived number carries how many efforts
//  it was fitted from and over what range, because a two-point fit is a line through two
//  points and should not be presented as knowledge.
//

import Foundation

/// One best effort: a distance covered in a time.
struct BestEffort: Sendable, Equatable, Hashable, Identifiable {

    /// Metres.
    let distance: Double

    /// Seconds.
    let duration: Double

    /// When it was run, for ageing out old efforts.
    let date: Date

    var id: String { "\(Int(distance))-\(Int(duration))-\(date.timeIntervalSince1970)" }

    /// Metres per second.
    var speed: Double { duration > 0 ? distance / duration : 0 }

    /// Seconds per kilometre.
    var pace: Double { distance > 0 ? duration / (distance / 1000) : 0 }
}

/// The fitted critical-speed model.
///
/// `d = CS·t + D′` — distance is a straight line in time, whose slope is the sustainable
/// speed and whose intercept is the finite distance available above it. Fitting in the
/// distance–time form rather than the speed–time form is deliberate: it is linear, so an
/// ordinary least-squares fit is exact and there is no iteration to converge or diverge.
struct CriticalSpeedModel: Sendable, Equatable, Hashable {

    /// Critical speed, metres per second.
    let criticalSpeed: Double

    /// D′ — the distance available above critical speed, metres.
    let anaerobicDistance: Double

    /// How many efforts the fit used.
    let effortCount: Int

    /// The shortest and longest efforts fitted, in seconds. A model fitted only to efforts
    /// between two and four minutes says very little about a marathon, and the screen has to
    /// be able to say so.
    let shortestDuration: Double
    let longestDuration: Double

    /// Coefficient of determination. Below about 0.95 the two-parameter model is not
    /// describing these efforts well and the prediction should be treated as indicative.
    let rSquared: Double

    /// Critical pace, seconds per kilometre.
    var criticalPace: Double { criticalSpeed > 0 ? 1000 / criticalSpeed : 0 }

    /// Whether the fit spans enough of a range to extrapolate from with a straight face.
    ///
    /// The literature fits critical power to efforts between roughly two and fifteen
    /// minutes; predictions much outside the fitted range drift, and the model is known to
    /// over-predict long-distance performance because it has no term for the slow component
    /// of oxygen uptake.
    var isWellConditioned: Bool {
        effortCount >= 3 && rSquared >= 0.95 && longestDuration / max(shortestDuration, 1) >= 3
    }

    /// Predicted time for a distance, seconds. `t = (d − D′) / CS`.
    ///
    /// Returns `nil` for distances inside D′, where the model says the distance is covered
    /// entirely above critical speed and the linear form has nothing sensible to say.
    func predictedTime(forDistance distance: Double) -> Double? {
        guard criticalSpeed > 0, distance > anaerobicDistance else { return nil }
        return (distance - anaerobicDistance) / criticalSpeed
    }

    /// How far outside the fitted range a prediction sits, as a multiple. 1 means inside.
    func extrapolationFactor(forDistance distance: Double) -> Double {
        guard let time = predictedTime(forDistance: distance), longestDuration > 0 else { return 1 }
        return max(1, time / longestDuration)
    }
}

/// A standard race distance.
enum RaceDistance: String, Sendable, Hashable, CaseIterable, Identifiable {
    case oneMile
    case fiveK
    case tenK
    case halfMarathon
    case marathon

    var id: String { rawValue }

    /// Metres.
    var metres: Double {
        switch self {
        case .oneMile: return 1609.34
        case .fiveK: return 5000
        case .tenK: return 10000
        case .halfMarathon: return 21097.5
        case .marathon: return 42195
        }
    }

    var displayName: String {
        switch self {
        case .oneMile: return "1 mil"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Yarı maraton"
        case .marathon: return "Maraton"
        }
    }
}

/// A race prediction and how much to trust it.
struct RacePrediction: Sendable, Equatable, Hashable, Identifiable {

    let distance: RaceDistance

    /// Predicted finishing time, seconds.
    let seconds: Double

    /// Average pace, seconds per kilometre.
    let pace: Double

    /// How far beyond the fitted range this prediction reaches.
    let extrapolationFactor: Double

    var id: String { distance.rawValue }

    /// Whether the prediction is close enough to the fitted efforts to state plainly.
    var isReliable: Bool { extrapolationFactor <= 2.5 }

    /// The caveat to show, when there is one.
    var caveat: String? {
        guard !isReliable else { return nil }
        return "Bu tahmin, model için kullanılan en uzun eforun \(ZenithiumFormat.metric(extrapolationFactor, digits: 1)) katı uzunlukta. Kritik hız modeli uzun mesafeleri iyimser tahmin etme eğilimindedir."
    }
}

/// Pace zones derived from the model rather than from a percentage table.
enum PaceZone: String, Sendable, Hashable, CaseIterable, Identifiable {
    case recovery
    case easy
    case steady
    case threshold
    case interval
    case repetition

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recovery: return "Toparlanma"
        case .easy: return "Kolay"
        case .steady: return "Sürekli"
        case .threshold: return "Eşik"
        case .interval: return "Interval"
        case .repetition: return "Tekrar"
        }
    }

    /// The band as a fraction of critical speed.
    ///
    /// Critical speed sits close to the physiological threshold, so the bands are expressed
    /// against it directly instead of against a maximum heart rate the app would have to
    /// estimate. That is the point of fitting the model: the zones come from measured
    /// efforts rather than from an age formula.
    var speedFraction: ClosedRange<Double> {
        switch self {
        case .recovery: return 0.60...0.72
        case .easy: return 0.72...0.82
        case .steady: return 0.82...0.92
        case .threshold: return 0.92...1.02
        case .interval: return 1.02...1.12
        case .repetition: return 1.12...1.30
        }
    }

    var purpose: String {
        switch self {
        case .recovery: return "Kan akışı, başka hiçbir şey"
        case .easy: return "Aerobik taban — haftalık hacmin çoğu burada olmalı"
        case .steady: return "Rahat ama çalışkan; uzun koşunun temposu"
        case .threshold: return "Bir saat sürdürebileceğin sınır"
        case .interval: return "VO₂max çalışması, 3–5 dakikalık tekrarlar"
        case .repetition: return "Hız ve ekonomi, kısa ve tam dinlenmeli"
        }
    }
}

/// One zone's pace band, in seconds per kilometre.
struct PaceZoneBand: Sendable, Equatable, Hashable, Identifiable {
    let zone: PaceZone

    /// Faster end, seconds per kilometre (the smaller number).
    let fastPace: Double

    /// Slower end, seconds per kilometre.
    let slowPace: Double

    var id: String { zone.rawValue }
}

/// How a single run's second half compared with its first.
///
/// Aerobic decoupling: the ratio of heart rate to pace drifting upward across a steady run
/// is the classic sign that the effort was above what could be sustained. Under about 5% is
/// usually read as the run being genuinely aerobic.
struct AerobicDecoupling: Sendable, Equatable, Hashable {

    /// First half's speed-per-beat.
    let firstHalfEfficiency: Double

    /// Second half's speed-per-beat.
    let secondHalfEfficiency: Double

    /// Fractional drop from first half to second. Positive means it decoupled.
    let drift: Double

    /// Whether the run held together.
    var heldTogether: Bool { drift <= 0.05 }

    var summary: String {
        let percent = ZenithiumFormat.percentTR(abs(drift))
        if drift <= 0.05 {
            return "Ayrışma \(percent) — koşu aerobik kaldı."
        }
        return "Ayrışma \(percent) — ikinci yarıda aynı tempo için nabzın belirgin yükseldi."
    }
}
