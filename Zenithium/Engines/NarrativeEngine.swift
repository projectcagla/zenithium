//
//  NarrativeEngine.swift
//  Zenithium
//
//  The deterministic narrator. Faz 24.
//
//  This is the layer people mean when they ask for "AI" in a health app, and it is worth
//  being precise about what it does. It does not generate text from a model. It decides
//  *which fact matters most today* and says that one, in a sentence a person would say.
//  Every engine already computes contribution shares; the narrator's whole job is to look at
//  them and pick the one that explains the day.
//
//  It runs on every device, needs no model, costs no battery and produces the same sentence
//  from the same numbers every time — which means it can be tested. The language model layer
//  in `AdaptiveNarrator` sits *on top* of this, rephrasing what this engine decided. It
//  never replaces the decision, and when it is unavailable — which is most devices — nothing
//  is missing.
//
//  §12 applies to every string in this file: training-directive language only, no health
//  status, no diagnosis, no treatment.
//

import Foundation

enum NarrativeEngine {

    /// A driver has to carry this share of the total before it is named as *the* reason.
    /// Below it the day has no single cause and the narrator says so instead of inventing one.
    static let dominantDriverShare = 0.34

    /// How far today must sit from the recent mean before the trend is worth a sentence.
    static let notableTrendPoints = 5.0

    // MARK: - Entry point

    static func briefing(for context: BriefingContext) -> Briefing {
        guard context.recovery.availability.isScored, let score = context.recovery.score else {
            return unavailableBriefing(for: context)
        }

        let points = supportingPoints(for: context)
        return Briefing(
            headline: headline(score: score, context: context),
            body: body(score: score, context: context),
            points: points.map(\.text),
            requiresClinicianPrompt: points.contains { $0.requiresClinician },
            source: .deterministic
        )
    }

    // MARK: - Headline

    /// One sentence: the score, and the single most useful thing to compare it against.
    static func headline(score: Double, context: BriefingContext) -> String {
        let rounded = ZenithiumFormat.score(score)
        guard let mean = recentMean(context.recentRecoveryScores) else {
            return "Toparlanma \(rounded)."
        }
        let delta = score - mean
        guard abs(delta) >= notableTrendPoints else {
            return "Toparlanma \(rounded) — son günlerin seyrinde."
        }
        let direction = delta > 0 ? "üstünde" : "altında"
        return "Toparlanma \(rounded) — son \(context.recentRecoveryScores.count) günün ortalamasının \(ZenithiumFormat.score(abs(delta))) puan \(direction)."
    }

    // MARK: - Body

    /// Two or three sentences answering "why".
    ///
    /// The first sentence is always the cause, because that is the question the number
    /// raises. The second is what it means for today, in training terms.
    static func body(score: Double, context: BriefingContext) -> String {
        var sentences: [String] = []

        if let dominant = dominantDriver(in: context.recovery) {
            sentences.append("Toparlanmayı en çok etkileyen faktör: \(phrase(for: dominant)) (Toplam değişimin \(ZenithiumFormat.percentTR(dominant.share))'i).")
        } else if context.recovery.drivers.isEmpty {
            sentences.append("Biyometrik değerler bireysel taban çizginizle tam uyumlu seyrediyor.")
        } else {
            sentences.append("Belirgin tek bir sapma yok; parametreler hafif ve dengeli varyasyonlar sergiliyor.")
        }

        if let sleep = context.sleep, let sleepScore = sleep.score {
            let hours = ZenithiumFormat.metric(sleep.asleepHours, digits: 1)
            let need = ZenithiumFormat.metric(sleep.needHours, digits: 1)
            sentences.append("Uyku Skoru \(ZenithiumFormat.score(sleepScore)): \(hours) saat uyku süresi (Hedef ihtiyaç: \(need) saat).")
        }

        if context.lens.showsStrainCeiling, let ceiling = context.recovery.targetStrainCeiling {
            sentences.append(ceilingSentence(ceiling: ceiling, context: context))
        }

        return sentences.joined(separator: " ")
    }

    /// What today's ceiling means next to what was actually done.
    private static func ceilingSentence(ceiling: Double, context: BriefingContext) -> String {
        let ceilingText = ZenithiumFormat.strain(ceiling)
        guard let current = context.currentStrain, current > 0.5 else {
            return "Önerilen günlük zorlanma hedefi: \(ceilingText)."
        }
        let remaining = ceiling - current
        if remaining <= 0 {
            return "Günlük hedef \(ceilingText); şu anki zorlanma \(ZenithiumFormat.strain(current)) — hedef seviyeye ulaşıldı."
        }
        return "Günlük hedef \(ceilingText); şu anki zorlanma \(ZenithiumFormat.strain(current))."
    }

    // MARK: - Points

    struct SupportingPoint: Sendable, Equatable {
        let text: String
        let requiresClinician: Bool
        let priority: Int
    }

    /// Up to three supporting points, chosen by how much they change what the user does.
    ///
    /// Ordering is the whole design here. A lab value outside its reference band outranks
    /// everything because it is the only item that sends the user somewhere else; muscle
    /// readiness outranks a correlation because it changes today rather than next month.
    static func supportingPoints(for context: BriefingContext) -> [SupportingPoint] {
        var candidates: [SupportingPoint] = []

        if let lab = context.labObservations.first(where: { $0.requiresClinician }) {
            candidates.append(SupportingPoint(text: lab.message, requiresClinician: true, priority: 100))
        }

        // The cycle point outranks muscles and correlations because it changes how today's
        // *score* should be read, not just what to do about it. A luteal morning scored
        // against a whole-cycle baseline reads low every month, and saying so is the whole
        // reason Faz 12 exists.
        if let cycle = context.cyclePhase {
            candidates.append(
                SupportingPoint(
                    text: CycleEngine.context(
                        for: cycle,
                        metric: .heartRateVariability,
                        phaseMean: context.cyclePhaseHRVMean
                    ),
                    requiresClinician: false,
                    priority: 90
                )
            )
        }

        if context.lens != .health, let weakest = context.muscles.min(by: { $0.readiness < $1.readiness }), weakest.readiness < 70 {
            candidates.append(
                SupportingPoint(
                    text: "\(weakest.muscle.displayName) %\(Int(weakest.readiness)) hazır — en yüksek yorgunluk seviyesindeki kas grubu.",
                    requiresClinician: false,
                    priority: 80
                )
            )
        }

        if let correlation = context.correlations.first(where: { $0.isConsistent }) {
            candidates.append(
                SupportingPoint(text: CorrelationEngine.summary(for: correlation), requiresClinician: false, priority: 70)
            )
        }

        if let sleep = context.sleep, sleep.appliedDebtHours >= 1 {
            candidates.append(
                SupportingPoint(
                    text: "Biriken uyku borcu: \(ZenithiumFormat.metric(sleep.appliedDebtHours, digits: 1)) saat (Bu gecenin ihtiyacına eklendi).",
                    requiresClinician: false,
                    priority: 60
                )
            )
        }

        if let previous = context.previousStrain, previous > 0 {
            candidates.append(
                SupportingPoint(
                    text: "Dünkü toplam antrenman zorlanması: \(ZenithiumFormat.strain(previous)).",
                    requiresClinician: false,
                    priority: 40
                )
            )
        }

        if let lab = context.labObservations.first(where: { !$0.requiresClinician }) {
            candidates.append(SupportingPoint(text: lab.message, requiresClinician: false, priority: 30))
        }

        return Array(candidates.sorted { $0.priority > $1.priority }.prefix(3))
    }

    // MARK: - Unavailable

    /// What to say when there is no score. Never nothing — an empty screen reads as a bug.
    private static func unavailableBriefing(for context: BriefingContext) -> Briefing {
        switch context.recovery.availability {
        case .scored:
            return Briefing.empty
        case .calibrating(let collected, let required):
            return Briefing(
                headline: "Taban çizgin kuruluyor — \(collected)/\(required) gün.",
                body: "Zenithium senin normalini öğreniyor. Bu tamamlanana kadar toparlanma puanı üretmiyorum, çünkü karşılaştıracak bir şey yok.",
                points: [],
                requiresClinicianPrompt: false,
                source: .deterministic
            )
        case .unavailable(let reason):
            return Briefing(
                headline: reason.displayName,
                body: reason.explanation,
                points: [],
                requiresClinicianPrompt: false,
                source: .deterministic
            )
        }
    }

    // MARK: - Helpers

    /// The driver that explains the day, when one does.
    static func dominantDriver(in recovery: RecoveryOutput) -> DriverContribution? {
        guard let top = recovery.drivers.max(by: { abs($0.share) < abs($1.share) }) else { return nil }
        return abs(top.share) >= dominantDriverShare ? top : nil
    }

    /// Turkish phrasing for a driver's direction.
    ///
    /// Deliberately not `DriverContribution.phrase`: that property is the §5.1 wording used
    /// on the Today card, and it reads as a clause in a different sentence shape than the
    /// one the narrator builds.
    static func phrase(for contribution: DriverContribution) -> String {
        let up = contribution.isPositive
        switch contribution.driver {
        case .heartRateVariability:
            return up ? "taban çizginin üstündeki HRV" : "taban çizginin altındaki HRV"
        case .restingHeartRate:
            return up ? "düşük istirahat nabzın" : "yükselmiş istirahat nabzın"
        case .sleep:
            return up ? "iyi geçen uykun" : "ihtiyacının altında kalan uykun"
        case .temperature:
            return up ? "taban çizgine yakın bilek sıcaklığın" : "taban çizginden sapan bilek sıcaklığın"
        case .respiratory:
            return up ? "düşük solunum hızın" : "yükselmiş solunum hızın"
        }
    }

    /// The mean of the recent scores, excluding today's, when there are enough of them.
    static func recentMean(_ scores: [Double]) -> Double? {
        guard scores.count >= 3 else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
