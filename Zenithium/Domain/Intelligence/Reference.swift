//
//  Reference.swift
//  Zenithium
//
//  A scientific source, as a type rather than a sentence. Faz 34.
//
//  Until now `ScientificBoundary.primaryCitation` was free text. Free text cannot be
//  validated, cannot be linked to the claim it supports, and — the reason this file
//  exists — is exactly the shape that invites a citation nobody ever checks. A struct
//  with a required identifier and a required statement of what the study *does not*
//  show is much harder to fill in carelessly.
//
//  Two fields carry most of the honesty here:
//
//  · `doesNotShow` is mandatory and cannot be empty. Writing what a paper does not
//    establish takes more thought than writing what it does, and it cuts overclaiming
//    off at the source rather than at the sentence.
//  · `needsVerification` marks a source whose bibliographic details could not be
//    confirmed. It is not a defect to be hidden — a flagged source is barred from
//    supporting a `.recommendation`, so the uncertainty changes what the app is
//    willing to say rather than being silently absorbed.
//

import Foundation

/// How strong the study design is.
///
/// The ordering matters: `ClaimStrength` reads the *lowest* grade among a claim's
/// supporting sources, so a recommendation is only as strong as its weakest leg.
enum EvidenceGrade: Int, Sendable, Codable, CaseIterable, Comparable {

    /// Mechanism, expert opinion, animal model.
    case mechanistic = 1

    /// Cross-sectional or case series.
    case observational = 2

    /// Prospective cohort.
    case cohort = 3

    /// Randomised controlled trial.
    case controlled = 4

    /// Systematic review, meta-analysis, or a professional body's consensus statement.
    case synthesis = 5

    static func < (lhs: EvidenceGrade, rhs: EvidenceGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .mechanistic: return "Mekanizma"
        case .observational: return "Gözlemsel"
        case .cohort: return "Kohort"
        case .controlled: return "Randomize kontrollü"
        case .synthesis: return "Derleme / konsensüs"
        }
    }

    /// One line the user can read without knowing what a cohort study is.
    var explanation: String {
        switch self {
        case .mechanistic:
            return "Mekanizmaya veya uzman görüşüne dayanıyor; insanda doğrudan ölçülmemiş."
        case .observational:
            return "Tek bir zamanda gözlenmiş bir ilişki; neden-sonuç göstermez."
        case .cohort:
            return "Bir grup insan zaman içinde izlenmiş; ilişki güçlü ama müdahale yok."
        case .controlled:
            return "Katılımcılar rastgele gruplara ayrılmış; neden-sonuç için en güçlü tekil tasarım."
        case .synthesis:
            return "Birden çok çalışmanın birlikte değerlendirilmesi ya da bir uzmanlık kurulunun ortak bildirisi."
        }
    }
}

/// Biological sex as a study reported it.
///
/// Deliberately separate from `BiologicalSexValue`: that type models *this user*, this one
/// models *a paper's sample*, and `.unreported` is a real and common value in the second
/// that has no meaning in the first.
enum PopulationSex: String, Sendable, Codable, CaseIterable, Equatable {
    case male
    case female
    case mixed
    case unreported

    var displayName: String {
        switch self {
        case .male: return "erkek"
        case .female: return "kadın"
        case .mixed: return "karma"
        case .unreported: return "bildirilmemiş"
        }
    }
}

/// How trained the studied sample was.
enum TrainingStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case untrained
    case recreational
    case trained
    case elite
    case clinical
    case mixed

    var displayName: String {
        switch self {
        case .untrained: return "antrenmansız"
        case .recreational: return "rekreasyonel"
        case .trained: return "antrenmanlı"
        case .elite: return "elit"
        case .clinical: return "klinik popülasyon"
        case .mixed: return "karma"
        }
    }

    /// Position on an untrained → elite line, for measuring the distance between the
    /// sample and the user. `.clinical` and `.mixed` have no position: a clinical cohort
    /// is not "more trained" or "less trained" than a recreational one, it is elsewhere.
    var ladderPosition: Int? {
        switch self {
        case .untrained: return 0
        case .recreational: return 1
        case .trained: return 2
        case .elite: return 3
        case .clinical, .mixed: return nil
        }
    }
}

/// Who a finding was actually established in.
struct StudiedPopulation: Sendable, Codable, Equatable, Hashable {

    let sex: PopulationSex

    /// The sample's age range, when the paper reported one.
    let ageRange: ClosedRange<Int>?

    let trainingStatus: TrainingStatus

    /// Number of participants, when reported.
    let sampleSize: Int?

    init(
        sex: PopulationSex,
        ageRange: ClosedRange<Int>? = nil,
        trainingStatus: TrainingStatus,
        sampleSize: Int? = nil
    ) {
        self.sex = sex
        self.ageRange = ageRange
        self.trainingStatus = trainingStatus
        self.sampleSize = sampleSize
    }

    /// A phrase for the "this was shown in…" sentence.
    var summary: String {
        var parts: [String] = []
        if let sampleSize { parts.append("\(sampleSize) kişi") }
        parts.append(sex.displayName)
        parts.append(trainingStatus.displayName)
        var text = parts.joined(separator: " ")
        if let ageRange {
            text += " (\(ageRange.lowerBound)–\(ageRange.upperBound) yaş)"
        }
        return text
    }

    /// The value for a source whose sample was never described.
    static let unreported = StudiedPopulation(
        sex: .unreported,
        ageRange: nil,
        trainingStatus: .mixed,
        sampleSize: nil
    )
}

/// One scientific source.
struct Reference: Sendable, Codable, Equatable, Hashable, Identifiable {

    /// A stable key such as `"PLEWS-2013"`. Never derived from the title, because a
    /// title can be corrected and every claim pointing at this source would break.
    let id: String

    let authors: String
    let year: Int
    let title: String

    /// Journal, or the issuing body for a consensus statement.
    let venue: String

    let doi: String?
    let pmid: String?

    /// For books and chapters, which legitimately have neither a DOI nor a PMID.
    let isbn: String?

    let grade: EvidenceGrade
    let population: StudiedPopulation

    /// What this study does **not** establish, in the context Zenithium uses it.
    /// Mandatory. `EvidenceLibrary` refuses to serve a source with this empty.
    let doesNotShow: String

    /// True when the bibliographic details could not be confirmed.
    ///
    /// A flagged source may still be stored and shown — with the flag visible — but it
    /// can never support a `.recommendation`. Uncertainty here changes what the app is
    /// willing to say out loud.
    let needsVerification: Bool

    /// Sources whose findings disagree with this one. Symmetry is enforced by
    /// `EvidenceLibrary.integrityFailures()`, not by this type.
    let contradicts: [String]

    init(
        id: String,
        authors: String,
        year: Int,
        title: String,
        venue: String,
        doi: String? = nil,
        pmid: String? = nil,
        isbn: String? = nil,
        grade: EvidenceGrade,
        population: StudiedPopulation,
        doesNotShow: String,
        needsVerification: Bool = false,
        contradicts: [String] = []
    ) {
        self.id = id
        self.authors = authors
        self.year = year
        self.title = title
        self.venue = venue
        self.doi = doi
        self.pmid = pmid
        self.isbn = isbn
        self.grade = grade
        self.population = population
        self.doesNotShow = doesNotShow
        self.needsVerification = needsVerification
        self.contradicts = contradicts
    }

    /// Whether the source can be located by a reader.
    ///
    /// A source with no identifier is not forbidden — some genuinely have none — but it
    /// must then be flagged, so that "I could not find an identifier" and "I could not
    /// confirm this source" never come apart.
    var isLocatable: Bool {
        doi != nil || pmid != nil || isbn != nil
    }

    /// Whether this source is allowed to support a `.recommendation`.
    var isVerified: Bool {
        !needsVerification && isLocatable
    }

    /// The citation line, in the form a reader would recognise.
    var citation: String {
        "\(authors) (\(year)). \(title). \(venue)."
    }

    /// The locator shown under the citation, if any.
    var locator: String? {
        if let doi { return "doi:\(doi)" }
        if let pmid { return "PMID:\(pmid)" }
        if let isbn { return "ISBN:\(isbn)" }
        return nil
    }
}
