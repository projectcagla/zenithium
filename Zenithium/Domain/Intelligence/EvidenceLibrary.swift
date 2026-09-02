//
//  EvidenceLibrary.swift
//  Zenithium
//
//  Every scientific source the app rests on, in one place. Faz 34.
//
//  ## Why a single table
//
//  Before this file, citations lived as sentences inside engine headers, which meant no
//  two of them agreed on a format, none could be checked, and nothing prevented a source
//  from being cited for a claim it never made. A table can be audited: `Scripts/
//  check-citations.py` reads it, and `docs/EVIDENCE.md` is generated from it.
//
//  ## On the flagged entries
//
//  Four sources below carry `needsVerification: true`. That is not laziness — it is the
//  mechanism working. Each one is a source whose finding is well established but whose
//  exact bibliographic details (a print year that differs from the online-first year, a
//  book chapter's edition, a paper whose title is remembered imprecisely) could not be
//  confirmed without a network. A flagged source still informs the app; it just cannot
//  license the imperative mood. `docs/EVIDENCE.md` lists them separately so they can be
//  checked by hand and cleared.
//
//  ## The contradiction pair
//
//  `GABBETT-2016` and `LOLLI-2019` are linked as contradicting each other, and this is
//  deliberate rather than decorative. The acute-to-chronic workload ratio is genuinely
//  disputed: the ratio is widely used, and the objection that its numerator sits inside
//  its denominator — producing correlation from arithmetic alone — is a real one. An app
//  that quietly picked a side would be claiming a consensus that does not exist.
//

import Foundation

enum EvidenceLibrary {

    // MARK: - The table

    /// Built with a last-wins merge rather than `uniqueKeysWithValues:`.
    ///
    /// That initialiser traps on a duplicate key, and a trap inside a `static let` fires
    /// the first time anything touches the table — including `integrityFailures()`, the
    /// very check whose job is to report the duplicate. A duplicated id should fail a
    /// test with its name in the message, not crash the app on launch.
    static let references: [String: Reference] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { _, latest in latest }
    )

    static let all: [Reference] = [

        // MARK: Autonomic monitoring

        Reference(
            id: "PLEWS-2013",
            authors: "Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M",
            year: 2013,
            title: "Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring",
            venue: "Sports Medicine",
            doi: "10.1007/s40279-013-0071-8",
            pmid: "23852425",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .elite),
            doesNotShow: "Tek bir günün HRV değerinden o günün antrenman kapasitesini çıkarmayı desteklemez; savunduğu şey haftalık ortalamaların takibidir. Bir gecelik düşüşün nedenini de söylemez."
        ),

        Reference(
            id: "BUCHHEIT-2014",
            authors: "Buchheit M",
            year: 2014,
            title: "Monitoring training status with HR measures: do all roads lead to Rome?",
            venue: "Frontiers in Physiology",
            doi: "10.3389/fphys.2014.00073",
            pmid: "24578692",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .trained),
            doesNotShow: "Nabız türevli hiçbir ölçütün tek başına yeterli olduğunu göstermez; tersine, her birinin farklı bir şeyi ölçtüğünü ve bağlam olmadan yorumlanamayacağını savunur."
        ),

        // MARK: Training load

        Reference(
            id: "BANISTER-1991",
            authors: "Banister EW",
            year: 1991,
            title: "Modeling elite athletic performance",
            venue: "Physiological Testing of Elite Athletes (Human Kinetics)",
            grade: .mechanistic,
            population: StudiedPopulation(sex: .male, trainingStatus: .elite),
            doesNotShow: "Model, bir sporcunun performansını ileriye dönük tahmin etmek için doğrulanmış değildir; antrenman yükünü tek bir sayıya indirgeyen bir muhasebe aracıdır.",
            needsVerification: true
        ),

        Reference(
            id: "MORTON-1997",
            authors: "Morton RH",
            year: 1997,
            title: "Modelling training and overtraining",
            venue: "Journal of Sports Sciences",
            doi: "10.1080/026404197367344",
            pmid: "9232558",
            grade: .mechanistic,
            population: StudiedPopulation(sex: .unreported, trainingStatus: .mixed),
            doesNotShow: "Aşırı antrenmanı teşhis etmez ve bir eşik vermez; yorgunluk ile uyumun farklı hızlarda söndüğü bir matematiksel çerçeve sunar.",
            needsVerification: true
        ),

        Reference(
            id: "FOSTER-1998",
            authors: "Foster C",
            year: 1998,
            title: "Monitoring training in athletes with reference to overtraining syndrome",
            venue: "Medicine & Science in Sports & Exercise",
            doi: "10.1097/00005768-199807000-00023",
            pmid: "9662690",
            grade: .cohort,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .trained),
            doesNotShow: "Yük artışının hastalık veya sakatlığa yol açtığını kanıtlamaz; yüksek yük ve ani artışların bunlarla birlikte görüldüğünü bildirir."
        ),

        Reference(
            id: "IMPELLIZZERI-2019",
            authors: "Impellizzeri FM, Marcora SM, Coutts AJ",
            year: 2019,
            title: "Internal and external training load: 15 years on",
            venue: "International Journal of Sports Physiology and Performance",
            doi: "10.1123/ijspp.2018-0935",
            pmid: "30614348",
            grade: .synthesis,
            population: StudiedPopulation(sex: .unreported, trainingStatus: .mixed),
            doesNotShow: "İç yükün dış yükten üstün olduğunu söylemez; ikisinin farklı sorulara cevap verdiğini ve karıştırıldıklarında her ikisinin de anlamsızlaştığını savunur."
        ),

        Reference(
            id: "GABBETT-2016",
            authors: "Gabbett TJ",
            year: 2016,
            title: "The training-injury prevention paradox: should athletes be training smarter and harder?",
            venue: "British Journal of Sports Medicine",
            doi: "10.1136/bjsports-2015-095788",
            pmid: "26758673",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .elite),
            doesNotShow: "Belirli bir akut:kronik oranının güvenli olduğunu göstermez ve rekreasyonel sporcularda doğrulanmamıştır. Bulguların çoğu takım sporu profesyonellerinden gelir.",
            contradicts: ["LOLLI-2019"]
        ),

        Reference(
            id: "HULIN-2016",
            authors: "Hulin BT, Gabbett TJ, Lawson DW, Caputi P, Sampson JA",
            year: 2016,
            title: "The acute:chronic workload ratio predicts injury: high chronic workload may decrease injury risk in elite rugby league players",
            venue: "British Journal of Sports Medicine",
            doi: "10.1136/bjsports-2015-094817",
            pmid: "26511006",
            grade: .cohort,
            population: StudiedPopulation(sex: .male, trainingStatus: .elite, sampleSize: 53),
            doesNotShow: "Elit erkek rugby oyuncularında gözlenen bir ilişkidir; başka sporlara, kadınlara veya rekreasyonel sporculara aktarılabilirliği gösterilmemiştir.",
            contradicts: ["LOLLI-2019"]
        ),

        Reference(
            id: "LOLLI-2019",
            authors: "Lolli L, Batterham AM, Hawkins R, Kelly DM, Strudwick AJ, Thorpe RT, Gregson W, Atkinson G",
            year: 2019,
            title: "Mathematical coupling causes spurious correlation within the conventional acute-to-chronic workload ratio calculations",
            venue: "British Journal of Sports Medicine",
            doi: "10.1136/bjsports-2017-098110",
            pmid: "29065984",
            grade: .synthesis,
            population: StudiedPopulation.unreported,
            doesNotShow: "Yük takibinin işe yaramadığını söylemez; akut değerin kronik değerin içinde yer almasının, gerçek bir ilişki olmasa bile korelasyon üreteceğini gösterir.",
            needsVerification: true,
            contradicts: ["GABBETT-2016", "HULIN-2016"]
        ),

        // MARK: Sleep

        Reference(
            id: "WATSON-2015",
            authors: "Watson NF, Badr MS, Belenky G, et al.",
            year: 2015,
            title: "Recommended amount of sleep for a healthy adult: a joint consensus statement of the American Academy of Sleep Medicine and Sleep Research Society",
            venue: "Sleep",
            doi: "10.5665/sleep.4716",
            pmid: "26039963",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, ageRange: 18...64, trainingStatus: .mixed),
            doesNotShow: "Bir bireyin ihtiyacını vermez. Yetişkin nüfus için bir aralık bildirir; aralığın dışında uyuyan herkesin yetersiz uyuduğu anlamına gelmez."
        ),

        Reference(
            id: "HIRSHKOWITZ-2015",
            authors: "Hirshkowitz M, Whiton K, Albert SM, et al.",
            year: 2015,
            title: "National Sleep Foundation's sleep time duration recommendations: methodology and results summary",
            venue: "Sleep Health",
            doi: "10.1016/j.sleh.2014.12.010",
            pmid: "29073412",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .mixed),
            doesNotShow: "Uyku süresi dışında hiçbir şey hakkında konuşmaz — uyku kalitesi, evre dağılımı veya zamanlaması bu bildirinin kapsamında değildir."
        ),

        Reference(
            id: "ROENNEBERG-2003",
            authors: "Roenneberg T, Wirz-Justice A, Merrow M",
            year: 2003,
            title: "Life between clocks: daily temporal patterns of human chronotypes",
            venue: "Journal of Biological Rhythms",
            doi: "10.1177/0748730402239679",
            pmid: "12568247",
            grade: .observational,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .untrained),
            doesNotShow: "Kronotipe göre uyku saatini kaydırmanın bir fayda ürettiğini göstermez; kronotipin nüfusta nasıl dağıldığını betimler."
        ),

        // MARK: Cardiorespiratory fitness

        Reference(
            id: "ROSS-2016",
            authors: "Ross R, Blair SN, Arena R, et al.",
            year: 2016,
            title: "Importance of assessing cardiorespiratory fitness in clinical practice: a case for fitness as a clinical vital sign",
            venue: "Circulation (American Heart Association scientific statement)",
            doi: "10.1161/CIR.0000000000000461",
            pmid: "27881567",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .mixed),
            doesNotShow: "Bilekten tahmin edilen VO₂max değerinin laboratuvar ölçümünün yerine geçtiğini göstermez; kanıtın tamamı doğrudan ölçüme dayanır."
        ),

        Reference(
            id: "KAMINSKY-2015",
            authors: "Kaminsky LA, Arena R, Myers J",
            year: 2015,
            title: "Reference standards for cardiorespiratory fitness measured with cardiopulmonary exercise testing: data from the Fitness Registry and the Importance of Exercise National Database",
            venue: "Mayo Clinic Proceedings",
            doi: "10.1016/j.mayocp.2015.07.026",
            pmid: "26455884",
            grade: .observational,
            population: StudiedPopulation(sex: .mixed, ageRange: 20...79, trainingStatus: .mixed),
            doesNotShow: "Kayıt defteri ağırlıklı olarak ABD'li katılımcılardan oluşur; yüzdelik konumun başka nüfuslarda aynı anlamı taşıdığı gösterilmemiştir."
        ),

        // MARK: Locomotion cost

        Reference(
            id: "MINETTI-2002",
            authors: "Minetti AE, Moia C, Roi GS, Susta D, Ferretti G",
            year: 2002,
            title: "Energy cost of walking and running at extreme uphill and downhill slopes",
            venue: "Journal of Applied Physiology",
            doi: "10.1152/japplphysiol.01177.2001",
            pmid: "12183501",
            grade: .controlled,
            population: StudiedPopulation(sex: .male, trainingStatus: .trained, sampleSize: 10),
            doesNotShow: "On antrenmanlı erkekte, koşu bandında ve ±%45 eğim aralığında ölçülmüştür. Arazide, farklı zeminlerde veya bu aralığın dışında doğrulanmamıştır."
        ),

        // MARK: Wearable temperature

        Reference(
            id: "SMARR-2020",
            authors: "Smarr BL, Aschbacher K, Fisher SM, et al.",
            year: 2020,
            title: "Feasibility of continuous fever monitoring using wearable devices",
            venue: "Scientific Reports",
            doi: "10.1038/s41598-020-78355-6",
            grade: .observational,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .mixed),
            doesNotShow: "Bilek sıcaklığındaki bir sapmanın nedenini söylemez ve hastalık tespiti için doğrulanmış bir eşik vermez.",
            needsVerification: true
        )
    ]

    // MARK: - Lookup

    /// The source for `id`, if the table has one that may be served.
    ///
    /// A source with an empty `doesNotShow` is withheld rather than returned: the field is
    /// what keeps a citation from becoming a blank cheque, and serving a source without it
    /// would let a claim inherit an authority nobody wrote down.
    static func reference(_ id: String) -> Reference? {
        guard let reference = references[id] else { return nil }
        guard !reference.doesNotShow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return reference
    }

    /// Every resolvable source for `ids`, in the order given. Unknown ids are dropped.
    static func resolve(_ ids: [String]) -> [Reference] {
        ids.compactMap { reference($0) }
    }

    /// The weakest study design among `ids`, which is what `ClaimStrength` reads.
    static func lowestGrade(among ids: [String]) -> EvidenceGrade? {
        resolve(ids).map(\.grade).min()
    }

    /// Whether every source for `ids` has confirmed details.
    ///
    /// An empty list is vacuously verified — a claim with no sources is floored at
    /// `.observation` by grade anyway, and reporting it as "unverified" would put a
    /// verification warning on a sentence that cites nothing.
    static func allVerified(_ ids: [String]) -> Bool {
        resolve(ids).allSatisfy(\.isVerified)
    }

    /// Whether any two sources in `ids` are recorded as disagreeing.
    static func hasContradiction(among ids: [String]) -> Bool {
        let present = Set(resolve(ids).map(\.id))
        return resolve(ids).contains { reference in
            reference.contradicts.contains { present.contains($0) }
        }
    }

    /// The disagreeing pairs in `ids`, each listed once, ordered for stable display.
    static func contradictions(among ids: [String]) -> [(Reference, Reference)] {
        let resolved = resolve(ids)
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        var seen: Set<String> = []
        var pairs: [(Reference, Reference)] = []

        for reference in resolved.sorted(by: { $0.id < $1.id }) {
            for otherID in reference.contradicts.sorted() {
                guard let other = byID[otherID] else { continue }
                let key = [reference.id, other.id].sorted().joined(separator: "|")
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                pairs.append((reference, other))
            }
        }
        return pairs
    }

    // MARK: - Integrity

    /// Everything structurally wrong with the table, as human-readable lines.
    ///
    /// Empty means the table is sound. Checked by a test rather than only by the Python
    /// pass, because a Swift-side failure names the offending entry at the point the code
    /// that trusts it is compiled.
    static func integrityFailures() -> [String] {
        var failures: [String] = []
        var seenIDs: Set<String> = []

        for reference in all {
            if !seenIDs.insert(reference.id).inserted {
                failures.append("\(reference.id): birden fazla kez tanımlanmış.")
            }
            if reference.doesNotShow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                failures.append("\(reference.id): doesNotShow boş.")
            }
            if !reference.isLocatable, !reference.needsVerification {
                failures.append("\(reference.id): DOI, PMID veya ISBN yok ama needsVerification işaretli değil.")
            }
            for otherID in reference.contradicts {
                guard let other = references[otherID] else {
                    failures.append("\(reference.id): var olmayan \(otherID) ile çelişiyor olarak işaretli.")
                    continue
                }
                if !other.contradicts.contains(reference.id) {
                    failures.append("\(reference.id) ↔ \(otherID): çelişki tek yönlü tanımlanmış.")
                }
            }
        }
        return failures
    }
}
