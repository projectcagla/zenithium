//
//  TrainingLoadIO.swift
//  Zenithium
//
//  Types crossing the training-load boundary. Faz 14.
//
//  This is the shared mathematics under every lens. A runner, a Hyrox athlete and a
//  powerlifter all want to know the same four things — how much have I done lately, how
//  much have I done for a while, is the gap between those two growing, and is my week
//  varied or grinding. Only the words on top differ.
//
//  §12 governs the vocabulary here as everywhere: a high ratio is described as a *load
//  pattern*, never as an injury prediction. The literature reports association, not
//  causation, and Zenithium is not entitled to the stronger claim.
//

import Foundation

/// One day's total training load.
struct DailyLoad: Sendable, Equatable, Hashable, Identifiable {

    /// Local day start.
    let dayStart: Date

    /// Total load for the day, on the TRIMP scale the strain engine already produces.
    let load: Double

    var id: Date { dayStart }

    init(dayStart: Date, load: Double) {
        self.dayStart = dayStart
        self.load = max(0, load)
    }
}

/// Where a load ratio sits.
///
/// The bands are the ones reported in the workload literature. They are descriptive: the
/// app says which band you are in and what that band means about *load*, and stops there.
enum LoadBand: String, Sendable, Equatable, Hashable, CaseIterable {

    /// Doing markedly less than the recent norm.
    case detraining

    /// Load close to, or a little above, the recent norm.
    case maintaining

    /// The range most often described as productive progression.
    case productive

    /// Load rising faster than the body has recently been prepared for.
    case rising

    /// A sharp step up relative to the recent norm.
    case spike

    static func band(forRatio ratio: Double) -> LoadBand {
        switch ratio {
        case ..<0.80: return .detraining
        case ..<1.00: return .maintaining
        case ..<1.30: return .productive
        case ..<1.50: return .rising
        default: return .spike
        }
    }

    var displayName: String {
        switch self {
        case .detraining: return "Azalan"
        case .maintaining: return "Koruyan"
        case .productive: return "Verimli"
        case .rising: return "Yükselen"
        case .spike: return "Sıçrama"
        }
    }

    /// What the band says about load. Never about injury, and never an instruction.
    var explanation: String {
        switch self {
        case .detraining:
            return "Son haftan, son ayının belirgin altında. Kondisyon bu bantta korunmaz."
        case .maintaining:
            return "Son haftan son ayına yakın. Bu bant mevcut durumu korur, ilerletmez."
        case .productive:
            return "Son haftan son ayının biraz üstünde — literatürde ilerlemenin en sık anıldığı bant."
        case .rising:
            return "Yük, vücudunun son bir ayda alıştığından hızlı artıyor."
        case .spike:
            return "Son haftan son ayının çok üstünde. Bu, hazırlanmadığın bir sıçrama."
        }
    }
}

/// The fitness–fatigue reading, in the vocabulary the endurance world uses.
struct FitnessFatigue: Sendable, Equatable, Hashable {

    /// Long-horizon load. Rises slowly, falls slowly.
    let fitness: Double

    /// Short-horizon load. Rises fast, falls fast.
    let fatigue: Double

    /// `fitness − fatigue`. Positive means fresher than fit, negative the reverse.
    let form: Double

    /// How `form` reads in one word.
    var formLabel: String {
        switch form {
        case ..<(-20): return "Derin yorgunluk"
        case ..<(-8): return "Yüklü"
        case ..<8: return "Dengede"
        case ..<20: return "Taze"
        default: return "Çok taze"
        }
    }
}

/// What the engine is given.
struct TrainingLoadInput: Sendable, Equatable {

    /// Daily loads, any order, any gaps. Missing days count as zero — a rest day is a real
    /// data point, not an absence.
    let days: [DailyLoad]

    /// The day the reading is for.
    let referenceDay: Date

    let calendar: Calendar

    init(days: [DailyLoad], referenceDay: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.days = days
        self.referenceDay = referenceDay
        self.calendar = calendar
    }
}

/// What the engine produces.
struct TrainingLoadOutput: Sendable, Equatable {

    /// Short-horizon exponentially weighted load.
    let acuteLoad: Double

    /// Long-horizon exponentially weighted load.
    let chronicLoad: Double

    /// The headline ratio: the mean of the last seven days' ratios, or `nil` before there
    /// is enough history to divide by.
    ///
    /// Smoothed rather than instantaneous on purpose. A single day's exponentially weighted
    /// ratio swings by nearly half over one unchanged training week — it reads 1.13 on a
    /// Friday and 0.89 on the Sunday of the *same* week — because the acute term has a
    /// two-and-a-half-day half-life and reacts to whether today happened to be a rest day.
    /// Averaging over the week removes that artefact without touching the formulation.
    let ratio: Double?

    /// Today's own ratio, unsmoothed. Kept because the projection maths steps from it, and
    /// because a user who wants the raw number should be able to see it.
    let instantRatio: Double?

    /// The daily ratios behind `ratio`, oldest first. The projection needs them to report a
    /// figure comparable with the headline rather than with the instantaneous one.
    let recentRatios: [Double]

    let band: LoadBand?

    /// This calendar week's total, and last week's, for the ramp figure.
    let weekLoad: Double
    let previousWeekLoad: Double

    /// Fractional change from last week to this. `nil` when last week was empty.
    let rampRate: Double?

    /// `mean / standard deviation` of the last seven days. High means every day looked the
    /// same, which is the pattern Foster associated with poorer adaptation.
    let monotony: Double?

    /// `weekLoad × monotony` — Foster's training strain.
    let fosterStrain: Double?

    let fitnessFatigue: FitnessFatigue

    /// How many of the last 28 days carried any load at all.
    let activeDaysInChronicWindow: Int

    /// Whether there is enough history for the ratio to mean anything.
    var hasEnoughHistory: Bool { ratio != nil }
}
