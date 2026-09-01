//
//  ReferenceNorms.swift
//  Zenithium
//
//  Published normative bands, for context only. Yol haritası v4, C11.
//
//  ## What this is
//
//  Every percentile elsewhere in Zenithium is computed against the person's own history —
//  `LongevityEngine` scores today against the last year of the same measurement, which is the
//  right comparison for a training app and a useless one for the first question people ask,
//  which is "is this normal for someone like me".
//
//  So: one optional overlay, from one published source, on one measurement.
//
//  ## Why only VO₂max
//
//  Because it is the only measurement here with a normative reference good enough to show.
//  The FRIEND registry tabulates cardiorespiratory fitness percentiles by age band and sex
//  from tens of thousands of maximal treadmill tests, and it is what ACSM's guidelines use.
//
//  Resting heart rate is deliberately absent. Population distributions for it exist, but they
//  are dominated by measurement conditions — time of day, posture, whether somebody just
//  climbed stairs — in a way a wrist-measured overnight minimum does not match. A band that
//  looks authoritative and compares two different things is worse than no band.
//
//  ## §12
//
//  A percentile is not a diagnosis and this file does not produce one. It answers "where does
//  this sit among people of the same age and sex who took a treadmill test", and every string
//  it vends says so. Nothing here flags, warns, or recommends.
//
//  ## ASSUMPTION NORM-1 — checked, failed, and the table removed
//
//  Until v0.1 this file carried a table transcribed "as commonly tabulated" and flagged as
//  unverified. It was checked against the primary source and the flag was right to be there:
//
//      cell                     table carried    published (Kaminsky 2015)
//      men   20–29, 50th             48.0             48.0     ✓
//      women 20–29, 50th             37.6             37.6     ✓
//      men   70–79, 50th             28.1             24.4     ✗
//      women 70–79, 50th             21.5             18.3     ✗
//
//  Two of the four cells that could be checked were wrong, and not by rounding. The
//  remaining thirty-two could not be checked at all — the publisher's tables are not
//  reachable from the machine this was verified on. There are also three FRIEND publications
//  in circulation that disagree with each other on the same cells (2015: men 20–29 50th =
//  48.0; the global FRIEND-I report: 49.5; the 2022 update puts men 70–79 at 30.8 where 2015
//  says 24.4), so "the FRIEND numbers" is not one thing.
//
//  For a health app going to the App Store, shipping numbers in that state is the failure
//  this assumption existed to prevent. So the numbers are gone rather than guessed, the table
//  below is empty, and the screen shows no comparison. Everything else — the arithmetic, the
//  interpolation, the copy, the tests — is intact and waiting.
//
//  ## How to turn it back on
//
//  One edit, in one place. See `docs/NORM-1-CHECKLIST.md` for the exact steps; the short
//  version is: fill `maleTreadmill` and `femaleTreadmill` from one publication, set
//  `source`, flip `isPublicationVerified`, and run the tests. `ReferenceNormsTests` checks
//  the values against the anchors the primary abstracts state outright, so a transcription
//  slip fails rather than ships.
//

import Foundation

/// Five percentiles of one measurement, for one age band and sex.
///
/// Five rather than three because the tails are where a person's question actually lives.
/// With only the quartiles, everything below the 25th had to be guessed by scaling linearly
/// to zero — which put a genuinely low reading and a slightly low one at nearly the same
/// place. The 10th and 90th give the curve real ends.
struct VO2MaxPercentiles: Sendable, Equatable, Hashable {

    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double

    init(p10: Double, p25: Double, p50: Double, p75: Double, p90: Double) {
        self.p10 = p10
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
        self.p90 = p90
    }

    /// Whether the five values increase, which any real percentile row does.
    ///
    /// A transcription that swaps two columns produces a row that does not, and this is how
    /// the suite notices without knowing the numbers.
    var isMonotonic: Bool {
        p10 < p25 && p25 < p50 && p50 < p75 && p75 < p90
    }

    /// The percentile positions these five values sit at.
    static let positions: [Double] = [0.10, 0.25, 0.50, 0.75, 0.90]

    /// The five values in ascending order, paired with their positions.
    var points: [(value: Double, percentile: Double)] {
        zip([p10, p25, p50, p75, p90], Self.positions).map { ($0, $1) }
    }
}

/// Where a measurement sits against a published reference.
struct NormPosition: Sendable, Equatable, Hashable {

    /// The value being placed.
    let value: Double

    /// The reference row it is placed against.
    let percentiles: VO2MaxPercentiles

    /// The age band the row came from, as its lower bound.
    let ageBand: Int

    /// How wide that band is, in years. Ten for every FRIEND band.
    let ageBandWidth: Int

    let biologicalSex: BiologicalSexValue

    // Kept as computed properties: callers and tests written against the quartile-only
    // version keep working, and there is one definition of what "the median" means.
    var lowerQuartile: Double { percentiles.p25 }
    var median: Double { percentiles.p50 }
    var upperQuartile: Double { percentiles.p75 }

    /// Roughly where the value sits, 0…1, interpolated between the published percentiles.
    ///
    /// Deliberately coarse, and the coarseness is the honest part: five points do not define
    /// a distribution, and reporting a percentile to the unit from them would be inventing
    /// resolution the source does not have. Outside the published ends the result is clamped
    /// rather than extrapolated — the table says nothing about the 3rd percentile, so this
    /// does not either.
    var approximatePercentile: Double {
        let points = percentiles.points

        if let first = points.first, value <= first.value {
            guard first.value > 0 else { return first.percentile }
            // Below the lowest published point, fall towards zero proportionally rather than
            // reporting the 10th percentile for everything down there.
            return MathSupport.clamp(
                first.percentile * value / first.value,
                0.02,
                first.percentile
            )
        }
        if let last = points.last, value >= last.value {
            guard last.value > 0 else { return last.percentile }
            let excess = value / last.value - 1
            return MathSupport.clamp(last.percentile + excess * 0.4, last.percentile, 0.98)
        }

        for (lower, upper) in zip(points, points.dropFirst()) where value <= upper.value {
            let span = upper.value - lower.value
            guard span > 0 else { return upper.percentile }
            let fraction = (value - lower.value) / span
            return lower.percentile + fraction * (upper.percentile - lower.percentile)
        }
        return 0.50
    }

    /// One sentence. A position among a reference group, and nothing more (§12).
    var summary: String {
        let percent = Int((approximatePercentile * 100).rounded())
        let band = "\(ageBand)–\(ageBand + ageBandWidth - 1)"
        return "Aynı yaş aralığındaki (\(band)) referans grubunda kabaca %\(percent) diliminde. Bu bir tanı değil, bir konum."
    }
}

/// Published reference bands.
enum ReferenceNorms {

    // MARK: - Verification

    /// Whether the table below has been checked against the published source.
    ///
    /// `false`, and the table is empty to match — see the file comment. This is a single
    /// switch rather than deleted code, because nothing but thirty-six numbers is missing.
    ///
    /// It is deliberately *not* possible for this to be `true` while the table is empty:
    /// `ReferenceNormsTests` asserts the two agree, so flipping the flag without filling the
    /// table fails the suite instead of shipping a feature that silently does nothing.
    static let isPublicationVerified = false

    /// Which publication the table was transcribed from, once it has been.
    ///
    /// Recorded because "the FRIEND numbers" is not one thing: three publications give
    /// different values for the same cells, and a table without its source cannot be
    /// re-checked by the next person.
    static let source: String? = nil

    // MARK: - Age bands

    /// How wide each published band is, in years.
    static let ageBandWidth = 10

    /// The bands the table covers, ascending. Derived from the table, so adding an 80–89 row
    /// extends the covered range without another constant needing to agree.
    static var coveredBands: [Int] {
        maleTreadmill.keys.sorted()
    }

    /// The band an age falls in, or `nil` when the table does not cover it.
    ///
    /// `nil` rather than the nearest band: the registry stops where it stops, and guessing a
    /// band for an eighty-five-year-old from the slope of the last two would be making one
    /// up. That refusal is the same one `LongevityEngine` makes about thin history.
    static func band(for age: Int) -> Int? {
        let lower = (age / ageBandWidth) * ageBandWidth
        return coveredBands.contains(lower) ? lower : nil
    }

    /// The band an age falls in, clamped to the table's range.
    ///
    /// Kept for callers that only need the label. Returns the youngest band when the table is
    /// empty, which nothing renders because every lookup refuses first.
    static func decade(for age: Int) -> Int {
        let bands = coveredBands
        guard let youngest = bands.first, let oldest = bands.last else { return youngestDecade }
        return min(max((age / ageBandWidth) * ageBandWidth, youngest), oldest)
    }

    /// The youngest band any FRIEND treadmill publication reports.
    static let youngestDecade = 20

    // MARK: - Lookup

    /// Where a VO₂max reading sits, or `nil` when age or sex is unknown or out of range.
    static func vo2MaxPosition(
        value: Double,
        age: Int?,
        biologicalSex: BiologicalSexValue
    ) -> NormPosition? {
        guard value > 0, let age else { return nil }
        guard let row = vo2MaxPercentiles(age: age, biologicalSex: biologicalSex) else { return nil }
        guard let band = band(for: age) else { return nil }
        return NormPosition(
            value: value,
            percentiles: row,
            ageBand: band,
            ageBandWidth: ageBandWidth,
            biologicalSex: biologicalSex
        )
    }

    /// The full percentile row for an age and sex, or `nil` outside the table.
    static func vo2MaxPercentiles(
        age: Int,
        biologicalSex: BiologicalSexValue
    ) -> VO2MaxPercentiles? {
        let table: [Int: VO2MaxPercentiles]
        switch biologicalSex {
        case .male: table = maleTreadmill
        case .female: table = femaleTreadmill
        // Without a recorded sex there is no band to compare against, and picking one would
        // put somebody against a reference group they are not in.
        case .other, .notSet: return nil
        }
        guard let band = band(for: age) else { return nil }
        return table[band]
    }

    /// The quartiles for an age and sex, or `nil` outside the table.
    ///
    /// The narrower shape the rest of the app was written against, kept so a richer table
    /// does not ripple into call sites that only ever wanted three numbers.
    static func vo2MaxBand(
        age: Int,
        biologicalSex: BiologicalSexValue
    ) -> (lower: Double, median: Double, upper: Double)? {
        guard let row = vo2MaxPercentiles(age: age, biologicalSex: biologicalSex) else { return nil }
        return (row.p25, row.p50, row.p75)
    }

    // MARK: - The table
    //
    // ASSUMPTION NORM-1. Empty until transcribed from a published source — see the file
    // comment for what was found wrong with the previous contents and
    // `docs/NORM-1-CHECKLIST.md` for how to fill it.
    //
    // Shape, once filled: `[ageBandLowerBound: VO2MaxPercentiles]`, VO₂max in
    // mL·kg⁻¹·min⁻¹, one entry per published band. Both tables must cover the same bands.

    static let maleTreadmill: [Int: VO2MaxPercentiles] = [:]

    static let femaleTreadmill: [Int: VO2MaxPercentiles] = [:]

    // MARK: - Anchors the table must reproduce
    //
    // The four cells the primary abstracts state outright, so a transcription is checked
    // rather than trusted. `ReferenceNormsTests` asserts these the moment the table is
    // non-empty, and only for the publication `source` names.

    /// 50th-percentile values quoted in each publication's own abstract.
    ///
    /// Kaminsky et al. (2015), *Mayo Clin Proc* 90(11):1515–1523 — ages 20–79.
    /// Kaminsky et al. (2022), *Mayo Clin Proc* 97(2):285–293 — ages 20–89.
    static let publishedMedians: [String: [Int: (male: Double, female: Double)]] = [
        "Kaminsky 2015": [
            20: (48.0, 37.6),
            70: (24.4, 18.3)
        ],
        "Kaminsky 2022": [
            70: (30.8, 25.0)
        ]
    ]
}
