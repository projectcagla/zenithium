//
//  PainEntry.swift
//  Zenithium
//
//  Logged discomfort, and what it is allowed to be used for. Faz 32.
//
//  §12 sits very close to this file. A pain log is the most medically-suggestive thing in
//  the app, so the boundary is drawn tightly and stated here rather than left to the views:
//
//  * Zenithium records **what the user said**, on their own scale, on a body region.
//  * It may correlate that record with training load, because both are its own data.
//  * It may not name a cause, suggest a treatment, or characterise the pain in any way. It
//    does not know the difference between a tight calf and a stress fracture, and the honest
//    response to that is to say so and route to a clinician.
//

import Foundation

/// How the discomfort feels, in the user's own words.
///
/// A closed list rather than free text, so the log is analysable — but the options are
/// descriptive sensations, never anything that reads as a diagnosis.
enum PainQuality: String, Sendable, Hashable, CaseIterable, Codable, Identifiable {
    case ache
    case sharp
    case tight
    case burning
    case stiff
    case unstable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ache: return "Sızı"
        case .sharp: return "Keskin"
        case .tight: return "Gergin"
        case .burning: return "Yanma"
        case .stiff: return "Tutukluk"
        case .unstable: return "Boşluk hissi"
        }
    }
}

/// Which side of the body.
enum BodyLaterality: String, Sendable, Hashable, CaseIterable, Codable, Identifiable {
    case left
    case right
    case both
    case central

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Sol"
        case .right: return "Sağ"
        case .both: return "İki taraf"
        case .central: return "Orta"
        }
    }
}

/// One logged entry.
struct PainEntry: Sendable, Equatable, Hashable, Identifiable, Codable {

    let id: UUID
    let muscle: MuscleGroup
    let laterality: BodyLaterality

    /// The user's own 0–10 rating.
    let severity: Int

    let quality: PainQuality
    let loggedAt: Date
    let note: String

    init(
        id: UUID = UUID(),
        muscle: MuscleGroup,
        laterality: BodyLaterality,
        severity: Int,
        quality: PainQuality,
        loggedAt: Date,
        note: String = ""
    ) {
        self.id = id
        self.muscle = muscle
        self.laterality = laterality
        self.severity = min(max(severity, 0), 10)
        self.quality = quality
        self.loggedAt = loggedAt
        self.note = note
    }

    /// The severity scale the logger offers.
    static let severityRange = 0...10

    /// Above this, the app stops offering training context and routes to a clinician.
    ///
    /// Seven is chosen because it is where the app's usefulness genuinely ends: correlating
    /// a 2/10 tight calf with Tuesday's tempo run is informative, and doing the same for a
    /// 8/10 sharp pain would be a distraction from the only sentence that should appear.
    static let clinicianThreshold = 7
}

/// What a pain log has to say about load — and what it does not.
struct PainInsight: Sendable, Equatable, Hashable, Identifiable {

    let muscle: MuscleGroup

    /// How many entries this is built on.
    let entryCount: Int

    /// Mean severity across them.
    let meanSeverity: Double

    /// Mean training load in the 48 hours before an entry.
    let loadBefore: Double

    /// Mean training load in the 48 hours before a day *without* an entry.
    let loadOtherwise: Double

    /// Whether the entries clustered after heavier days.
    let followsLoad: Bool

    /// Whether any entry crossed the clinician threshold.
    let hasSevereEntry: Bool

    var id: MuscleGroup { muscle }

    /// The sentence. Load context when it is useful, and a clinician prompt when it is not.
    var summary: String {
        if hasSevereEntry {
            return "\(muscle.displayName) için 7 ve üzeri şiddet kaydettin. Zenithium bunun ne olduğunu söyleyemez — bir hekime göster."
        }
        guard followsLoad else {
            return "\(muscle.displayName): \(entryCount) kayıt, ortalama şiddet \(ZenithiumFormat.metric(meanSeverity, digits: 1)). Kayıtların yük ile belirgin bir örüntü göstermiyor."
        }
        let difference = loadBefore - loadOtherwise
        return "\(muscle.displayName): kayıt tuttuğun günlerin öncesindeki 48 saatte ortalama yükün \(ZenithiumFormat.metric(difference, digits: 1)) daha yüksekti."
    }
}
