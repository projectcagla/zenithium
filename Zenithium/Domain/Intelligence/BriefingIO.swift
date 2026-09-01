//
//  BriefingIO.swift
//  Zenithium
//
//  What the narrator is given, and what it hands back. Faz 24.
//
//  `BriefingContext` is deliberately a plain value with no engines inside it. Two things
//  follow from that. The deterministic narrator is a pure function of it, so a briefing can
//  be tested against a literal. And when a language model is available, this struct is the
//  *only* thing that reaches it — a summary of already-computed numbers, never raw health
//  samples, and never anything that leaves the device.
//

import Foundation

/// One number the briefing might lead with.
struct BriefingSignal: Sendable, Equatable, Hashable {

    let label: String
    let value: String

    /// Change since the comparison period, already formatted, when there is one.
    let change: String?
}

/// Everything the narrator knows about today.
struct BriefingContext: Sendable, Equatable {

    let date: Date
    let lens: TrainingLens

    let recovery: RecoveryOutput

    /// Last night's sleep, when it was scored.
    let sleep: SleepOutput?

    /// Yesterday's strain, for the comparison the user actually cares about.
    let previousStrain: Double?

    /// Today's strain so far.
    let currentStrain: Double?

    /// Muscle readiness, worst first. Empty for the health lens, which does not show it.
    let muscles: [MuscleReadiness]

    /// The strongest journal correlations, already ranked.
    let correlations: [CorrelationResult]

    /// Anything the laboratory panel has to say, already ranked.
    let labObservations: [LabObservation]

    /// Recovery scores for the last week, oldest first, for the trend sentence.
    let recentRecoveryScores: [Double]

    /// The cycle phase, when the user tracks it and it could be estimated (Faz 12).
    let cyclePhase: CyclePhaseEstimate?

    /// The user's own HRV mean *in this phase*, when there is enough history for one.
    ///
    /// This is the number that makes the phase useful rather than merely informative:
    /// comparing a luteal morning against a whole-cycle mean is what produces the false
    /// "bad recovery" every month.
    let cyclePhaseHRVMean: Double?

    init(
        date: Date,
        lens: TrainingLens,
        recovery: RecoveryOutput,
        sleep: SleepOutput? = nil,
        previousStrain: Double? = nil,
        currentStrain: Double? = nil,
        muscles: [MuscleReadiness] = [],
        correlations: [CorrelationResult] = [],
        labObservations: [LabObservation] = [],
        recentRecoveryScores: [Double] = [],
        cyclePhase: CyclePhaseEstimate? = nil,
        cyclePhaseHRVMean: Double? = nil
    ) {
        self.date = date
        self.lens = lens
        self.recovery = recovery
        self.sleep = sleep
        self.previousStrain = previousStrain
        self.currentStrain = currentStrain
        self.muscles = muscles
        self.correlations = correlations
        self.labObservations = labObservations
        self.recentRecoveryScores = recentRecoveryScores
        self.cyclePhase = cyclePhase
        self.cyclePhaseHRVMean = cyclePhaseHRVMean
    }
}

/// Which layer produced a briefing.
enum BriefingSource: String, Sendable, Equatable, Hashable {

    /// The rule-based narrator. Always available, identical on every device.
    case deterministic

    /// Apple's on-device language model rephrased the deterministic draft.
    case onDeviceModel

    var displayName: String {
        switch self {
        case .deterministic: return "Zenithium"
        case .onDeviceModel: return "Zenithium · cihaz içi model"
        }
    }
}

/// A finished briefing.
struct Briefing: Sendable, Equatable, Hashable {

    /// One sentence. The thing the user reads if they read nothing else.
    let headline: String

    /// Two or three sentences explaining the headline.
    let body: String

    /// Up to three supporting points, each already a complete sentence.
    let points: [String]

    /// Whether any point came from a lab value outside its reference band, which the view
    /// must render with the clinician prompt attached.
    let requiresClinicianPrompt: Bool

    let source: BriefingSource

    static let empty = Briefing(
        headline: "Henüz yeterli veri yok.",
        body: "Birkaç gece daha veri toplandığında burada ne olduğunu anlatmaya başlayacağım.",
        points: [],
        requiresClinicianPrompt: false,
        source: .deterministic
    )
}
