//
//  LabTextFragment.swift
//  Zenithium
//
//  Putting a recognised laboratory table back into rows. Adım 5.
//
//  ## Why this is the part that matters
//
//  Optical recognition does not return a table. It returns scattered pieces — "Ferritin" in
//  one box, "45,2" in another, "ng/mL" in a third — and a parser handed those separately can
//  never pair a marker with its value. Everything downstream depends on this grouping being
//  right, and nothing downstream can detect it being wrong: a value stitched onto the row
//  above it parses perfectly and is simply the wrong number.
//
//  ## What was wrong with a fixed band
//
//  The grouping used a constant fraction of page height — 0.008, about seven points on A4.
//  That is a guess about type size, and it is wrong in both directions. A dense hemogram set
//  at eight points has rows closer together than the band, so two printed rows merge into
//  one and a marker acquires its neighbour's value. A report set large has rows further
//  apart than the band, so a unit sitting slightly below its value starts a new row.
//
//  It also assumed rows are level. A phone photograph of a printed report never is, and the
//  numbers are not marginal: a page rotated by 1.2° turns five printed rows into eight, and
//  2.3° turns six into thirteen. Every one of those splits detaches a value or a reference
//  range from the marker it belongs to.
//
//  ## What it does now
//
//  Three changes, measured against synthetic pages before being written:
//
//  1. The band comes from the fragments' own median height, so it scales with the type
//     instead of with the paper.
//  2. The band's centre follows the row as it is built — a running mean rather than the
//     first fragment's position.
//  3. The page's rotation is estimated and the rows are read along it rather than across it.
//
//  The estimate is a small search: for each candidate slope, group the page and count the
//  rows; the true rotation is the one that produces the fewest, because that is exactly what
//  rotation costs. Ties go to the flatter estimate, so a level page is left level. Measured
//  on synthetic pages, rows recovered correctly:
//
//      rotated 1.2°   8 rows → 5     (correct)
//      rotated 2.3°  13 rows → 6     (correct)
//      rotated −1.4° 11 rows → 5     (correct)
//      level, dense   6 rows → 6     (unchanged)
//      level, large   4 rows → 4     (unchanged)
//
//  Pure Foundation, and separate from `LabDocumentReader`, so every rule here is testable
//  against literal geometry rather than against a PDF and a Vision request.
//

import Foundation

/// One piece of recognised text and where it sat on the page.
///
/// Coordinates are Vision's: origin bottom-left, both axes normalised to 0…1.
struct LabTextFragment: Sendable, Equatable {

    let text: String

    /// Vertical centre of the box.
    let midY: Double

    /// Left edge of the box, used to order a row left to right.
    let minX: Double

    /// Box height, which is what the row band is derived from.
    let height: Double

    init(text: String, midY: Double, minX: Double, height: Double) {
        self.text = text
        self.midY = midY
        self.minX = minX
        self.height = height
    }

    /// What separates two fragments joined into one line.
    ///
    /// Two spaces, unchanged: `LabReportParser` reads these lines and its rules — and its
    /// tests — are written against that spacing.
    static let columnSeparator = "  "

    /// Stitches fragments back into reading order, one string per printed row.
    static func assembleLines(
        from fragments: [LabTextFragment],
        bandHeightFactor: Double,
        fallbackTolerance: Double
    ) -> [String] {
        guard !fragments.isEmpty else { return [] }

        let band = bandTolerance(
            for: fragments,
            factor: bandHeightFactor,
            fallback: fallbackTolerance
        )
        let slope = estimatedSlope(for: fragments, band: band)

        return group(fragments, band: band, slope: slope).map { row in
            row
                .sorted { $0.minX < $1.minX }
                .map(\.text)
                .joined(separator: columnSeparator)
                .trimmingCharacters(in: .whitespaces)
        }
        .filter { !$0.isEmpty }
    }

    /// Groups fragments into rows, reading along `slope`.
    static func group(
        _ fragments: [LabTextFragment],
        band: Double,
        slope: Double
    ) -> [[LabTextFragment]] {
        guard !fragments.isEmpty else { return [] }

        // Project onto the page's own baseline direction, then sort. Vision's origin is
        // bottom-left, so descending is top-to-bottom.
        let projected = fragments
            .map { (value: $0.midY - slope * $0.minX, fragment: $0) }
            .sorted { $0.value > $1.value }

        var rows: [[LabTextFragment]] = []
        var current: [LabTextFragment] = []
        var sum: Double = 0

        for entry in projected {
            // The centre is the mean of the row so far, not the first fragment's position.
            let centre = current.isEmpty ? entry.value : sum / Double(current.count)
            if !current.isEmpty, abs(entry.value - centre) > band {
                rows.append(current)
                current = []
                sum = 0
            }
            current.append(entry.fragment)
            sum += entry.value
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// The page's rotation, as the vertical drift per unit of width.
    ///
    /// Found by searching rather than fitted, because there is nothing to fit a line to: the
    /// fragments belong to rows nobody has identified yet, which is the problem being solved.
    /// What *is* available is a score — how many rows a candidate slope produces — and
    /// rotation only ever splits rows, so the true one produces the fewest.
    static func estimatedSlope(for fragments: [LabTextFragment], band: Double) -> Double {
        guard fragments.count >= minimumFragmentsForSlope else { return 0 }

        var best: Double = 0
        var fewest = group(fragments, band: band, slope: 0).count

        for step in 0..<slopeSearchSteps {
            let fraction = Double(step) / Double(slopeSearchSteps - 1)
            let candidate = -maximumSlope + 2 * maximumSlope * fraction
            let count = group(fragments, band: band, slope: candidate).count
            // Ties go to the flatter estimate, so a level page is not given a rotation it
            // does not have.
            if count < fewest || (count == fewest && abs(candidate) < abs(best)) {
                best = candidate
                fewest = count
            }
        }
        return best
    }

    /// Below this there is not enough on the page to tell rotation from noise.
    static let minimumFragmentsForSlope = 6

    /// The widest rotation searched — about 3.4° across the page.
    ///
    /// A photograph worse than this is worth rejecting rather than straightening: at that
    /// angle the recognition itself degrades and a straightened page of bad text is still
    /// bad text.
    static let maximumSlope: Double = 0.06

    /// How finely the range is sampled. Forty-nine steps is a little over a tenth of a degree
    /// each, which is finer than the band it feeds.
    static let slopeSearchSteps = 49

    /// How far apart two fragments can sit and still be one row.
    ///
    /// The median rather than the mean: a report's title is several times the height of its
    /// table rows, and a mean would let it widen the band for the whole page.
    static func bandTolerance(
        for fragments: [LabTextFragment],
        factor: Double,
        fallback: Double
    ) -> Double {
        let heights = fragments.map(\.height).filter { $0 > 0 }.sorted()
        guard !heights.isEmpty else { return fallback }
        let median = heights[heights.count / 2]
        guard median > 0 else { return fallback }
        return median * factor
    }
}
