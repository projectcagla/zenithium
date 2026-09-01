//
//  LabReportParser.swift
//  Zenithium
//
//  Turns the text of a laboratory report into candidate rows. Faz 23.
//
//  Pure Foundation on purpose: no PDFKit, no Vision, no SwiftData. Extraction is somebody
//  else's job, which makes every rule in here testable against a string literal.
//
//  The shape of a Turkish laboratory line is remarkably stable across labs:
//
//      Ferritin                    45,2      ng/mL      (30 - 400)
//      HDL Kolesterol              58        mg/dL      > 40
//      hs-CRP                      <0,3      mg/L
//      B12 Vitamini                350       pg/mL      200 - 900
//
//  Marker name, then the result, then the unit, then the laboratory's own reference band.
//  Every rule below follows from that, and every rule can be wrong — which is why nothing
//  here writes to the store. The parser's real output is a *proposal* plus an honest
//  confidence, and a person decides.
//

import Foundation

enum LabReportParser {

    // MARK: - Entry point

    /// Parse a whole extracted document into a reviewable draft.
    static func parse(_ document: LabDocumentText, referenceDate: Date = Date()) -> LabReportDraft {
        var byMarker: [String: ParsedLabValue] = [:]
        var unreadable = 0

        for page in document.pages {
            let lines = page.lines
            for (offset, line) in lines.enumerated() {
                // A few reports print the marker on one line and the number on the next, so
                // the following line is offered as a continuation when the current one has
                // a name but no usable number.
                let continuation = offset + 1 < lines.count ? lines[offset + 1] : nil
                switch parseLine(
                    line,
                    continuation: continuation,
                    pageNumber: page.pageNumber,
                    source: page.source
                ) {
                case .parsed(let value):
                    // The same marker can legitimately appear twice (a summary table and a
                    // detail table). The more confident read wins.
                    let key = value.marker.storageKey
                    if let existing = byMarker[key], existing.confidenceScore >= value.confidenceScore {
                        continue
                    }
                    byMarker[key] = value
                case .namedButUnreadable:
                    unreadable += 1
                case .notALabLine:
                    continue
                }
            }
        }

        let values = byMarker.values.sorted { lhs, rhs in
            if lhs.confidenceScore != rhs.confidenceScore {
                return lhs.confidenceScore > rhs.confidenceScore
            }
            return lhs.marker.displayName.localizedCompare(rhs.marker.displayName) == .orderedAscending
        }

        return LabReportDraft(
            fileName: document.fileName,
            source: document.source,
            detectedDrawDate: detectDrawDate(in: document.allLines, referenceDate: referenceDate),
            values: values,
            unreadableLineCount: unreadable
        )
    }

    /// What one line yielded.
    enum LineOutcome: Sendable {
        case parsed(ParsedLabValue)

        /// A marker was named but no number could be pulled out — worth counting so the
        /// review screen can say "3 lines I couldn't read" rather than silently dropping them.
        case namedButUnreadable

        case notALabLine
    }

    // MARK: - One line

    static func parseLine(
        _ line: String,
        continuation: String? = nil,
        pageNumber: Int = 1,
        source: LabTextSource = .textLayer
    ) -> LineOutcome {
        let normalized = BiomarkerCatalog.normalizedMapping(line)
        guard !normalized.isEmpty, let match = BiomarkerCatalog.bestMatch(in: normalized) else {
            return .notALabLine
        }

        var numbers = numberTokens(in: line, excluding: match.originalRange)
        var usedContinuation = false
        if numbers.isEmpty, let continuation, BiomarkerCatalog.bestMatch(inLine: continuation) == nil {
            numbers = numberTokens(in: continuation, excluding: nil)
            usedContinuation = true
        }
        guard !numbers.isEmpty else { return .namedButUnreadable }

        let valueLine = usedContinuation ? (continuation ?? line) : line
        let spans = rangeSpans(in: numbers, line: valueLine)
        guard let result = numbers.first(where: { token in !spans.contains { $0.contains(token.order) } }) else {
            // Every number on the line belonged to a reference band, so the result itself
            // was never printed — or was printed as something we could not read.
            return .namedButUnreadable
        }

        let definition = match.definition
        let marker = BloodMarkerKind.standard(definition.key)
        let printedUnit = unitText(after: result, in: valueLine, nextNumber: numbers.first { $0.order == result.order + 1 })
        let recognisedUnit = definition.unit(matching: printedUnit)
        let printedRange = printedRange(spans: spans, numbers: numbers)
        let resolved = resolveGrouping(of: result, unit: recognisedUnit ?? definition.canonicalUnit, definition: definition)

        let score = confidenceScore(
            match: match,
            result: result,
            resolvedValue: resolved.value,
            printedUnit: printedUnit,
            recognisedUnit: recognisedUnit,
            definition: definition,
            source: source,
            usedContinuation: usedContinuation
        )
        guard score >= ParseConfidence.discardThreshold else { return .namedButUnreadable }

        return .parsed(
            ParsedLabValue(
                marker: marker,
                value: resolved.value,
                unitSymbol: printedUnit.isEmpty ? definition.canonicalUnit.symbol : printedUnit,
                unitIsRecognised: recognisedUnit != nil,
                printedRange: printedRange,
                isThreshold: result.isThreshold,
                sourceLine: line.trimmingCharacters(in: .whitespaces),
                pageNumber: pageNumber,
                confidenceScore: score
            )
        )
    }

    // MARK: - Confidence

    /// How much to trust one parsed row, 0…1.
    ///
    /// Every factor is multiplicative and every one of them is a reason a human should look
    /// at the row. The point is not to be clever; it is to be honest about which rows are
    /// guesses so the review screen can sort them to the top.
    private static func confidenceScore(
        match: LabNameMatch,
        result: NumberToken,
        resolvedValue: Double,
        printedUnit: String,
        recognisedUnit: BiomarkerUnit?,
        definition: BiomarkerDefinition,
        source: LabTextSource,
        usedContinuation: Bool
    ) -> Double {
        var score = 1.0

        // A one-token abbreviation is a much weaker claim than a spelled-out name.
        if match.matchedTokens == 1 && match.matchedCharacters <= 3 {
            score *= 0.62
        } else if match.matchedTokens == 1 && match.matchedCharacters <= 5 {
            score *= 0.88
        }

        // Laboratories print the name first. A name found after the number usually means
        // the line was something else that happened to contain the word.
        if match.tokenPosition > 3 {
            score *= 0.75
        }

        if printedUnit.isEmpty {
            score *= 0.80
        } else if recognisedUnit == nil {
            score *= 0.68
        }

        // A single dot with exactly three digits behind it is genuinely ambiguous in a
        // Turkish report: "1.234" is one thousand two hundred and thirty-four to the lab
        // and one point two three four to a decimal parser.
        if result.hasAmbiguousGrouping {
            score *= 0.55
        }

        if usedContinuation {
            score *= 0.85
        }

        if !source.isExact {
            score *= 0.90
        }

        // A value nowhere near the published band is usually a mis-read, not a medical
        // emergency — so it is demoted for review rather than flagged to the user.
        let canonical = (recognisedUnit ?? definition.canonicalUnit).canonicalValue(of: resolvedValue)
        if isImplausible(canonical, for: definition) {
            score *= 0.45
        }

        return min(max(score, 0), 1)
    }

    /// Resolve "1.234": decimal point, or thousands separator?
    ///
    /// The line itself cannot say, so the marker's own reference band breaks the tie. A CK
    /// of 1.234 U/L is three hundred times below the bottom of the band and a CK of 1234 U/L
    /// is an ordinary post-session reading, so the thousands reading is the one that
    /// survives. When neither reading is plausible — or both are — the printed decimal is
    /// kept, and the ambiguity is paid for in confidence either way.
    static func resolveGrouping(
        of token: NumberToken,
        unit: BiomarkerUnit,
        definition: BiomarkerDefinition
    ) -> (value: Double, reinterpreted: Bool) {
        guard token.hasAmbiguousGrouping else { return (token.value, false) }
        let asDecimal = unit.canonicalValue(of: token.value)
        let grouped = token.value * 1000
        let asGrouped = unit.canonicalValue(of: grouped)
        guard isImplausible(asDecimal, for: definition), !isImplausible(asGrouped, for: definition) else {
            return (token.value, false)
        }
        return (grouped, true)
    }

    /// Whether a value sits an order of magnitude outside the marker's own reference band.
    private static func isImplausible(_ value: Double, for definition: BiomarkerDefinition) -> Bool {
        let band = definition.referenceRange.range(for: .notSet)
        guard band.isBounded else { return false }
        if value <= 0 { return true }
        if let maximum = band.maximum, value > maximum * 12 { return true }
        if let minimum = band.minimum, minimum > 0, value < minimum / 12 { return true }
        return false
    }

    // MARK: - Numbers

    /// One number found in a line, with everything the caller needs to reason about it.
    struct NumberToken: Sendable, Equatable {

        let value: Double

        /// Position among the numbers on the line, 0-based.
        let order: Int

        /// Where the number sits in the line.
        let range: Range<String.Index>

        /// The number was printed as a bound: "<0,3", "> 40".
        let isThreshold: Bool

        /// A single dot followed by exactly three digits — decimal point or thousands
        /// separator, and the line does not say which.
        let hasAmbiguousGrouping: Bool
    }

    /// Every number in a line, skipping any that sit inside `excluding` — which is how the
    /// digits in "B12", "HbA1c" and "Serbest T4" stay out of the results.
    static func numberTokens(in line: String, excluding excluded: Range<String.Index>?) -> [NumberToken] {
        var tokens: [NumberToken] = []
        var index = line.startIndex
        var order = 0

        while index < line.endIndex {
            guard line[index].isNumber else {
                index = line.index(after: index)
                continue
            }

            // Walk back over any digits/separators already consumed — cannot happen, since
            // the scanner always jumps past a completed token — then walk forward.
            var end = index
            var sawDot = false
            var sawComma = false
            var digitsAfterLastSeparator = 0
            while end < line.endIndex {
                let character = line[end]
                if character.isNumber {
                    digitsAfterLastSeparator += 1
                } else if character == "." || character == "," {
                    // A separator only continues the number when a digit follows it.
                    let next = line.index(after: end)
                    guard next < line.endIndex, line[next].isNumber else { break }
                    if character == "." { sawDot = true } else { sawComma = true }
                    digitsAfterLastSeparator = 0
                } else {
                    break
                }
                end = line.index(after: end)
            }

            let start = index
            index = end

            // A number welded to the end of a word is part of a name, not a result: the 12
            // in "B12", the 1 in "HbA1c", the 4 in "Serbest T4". A number *followed* by
            // letters is left alone, because "45mg/dL" with no space is a real format.
            let precededByLetter = start > line.startIndex && line[line.index(before: start)].isLetter
            if precededByLetter { continue }

            if let excluded, start < excluded.upperBound, excluded.lowerBound < end { continue }

            let text = String(line[start..<end])
            guard let value = decimalValue(of: text, sawDot: sawDot, sawComma: sawComma) else { continue }

            let (isThreshold, thresholdStart) = thresholdPrefix(before: start, in: line)
            let ambiguous = sawDot && !sawComma && digitsAfterLastSeparator == 3

            tokens.append(
                NumberToken(
                    value: value,
                    order: order,
                    range: thresholdStart..<end,
                    isThreshold: isThreshold,
                    hasAmbiguousGrouping: ambiguous
                )
            )
            order += 1
        }
        return tokens
    }

    /// Read a printed number, resolving which separator was the decimal one.
    ///
    /// When both separators appear, the last one is the decimal — true for both the Turkish
    /// "1.234,5" and the English "1,234.5". When only a comma appears it is decimal, because
    /// that is how Turkish laboratories print. When only a dot appears it is treated as
    /// decimal too, and the caller is told the read was ambiguous if it looked like grouping.
    static func decimalValue(of text: String, sawDot: Bool, sawComma: Bool) -> Double? {
        var cleaned = text
        if sawDot && sawComma {
            if let lastDot = text.lastIndex(of: "."), let lastComma = text.lastIndex(of: ",") {
                if lastComma > lastDot {
                    cleaned = text.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = text.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if sawComma {
            cleaned = text.replacingOccurrences(of: ",", with: ".")
        }
        return Double(cleaned)
    }

    /// Whether a "<", ">", "≤" or "≥" immediately precedes the number, and where that
    /// symbol starts.
    private static func thresholdPrefix(before start: String.Index, in line: String) -> (Bool, String.Index) {
        var cursor = start
        while cursor > line.startIndex {
            let previous = line.index(before: cursor)
            let character = line[previous]
            if character == " " {
                cursor = previous
                continue
            }
            if character == "<" || character == ">" || character == "\u{2264}" || character == "\u{2265}" {
                return (true, previous)
            }
            return (false, start)
        }
        return (false, start)
    }

    // MARK: - Reference bands

    /// Pairs of number orders that form a printed range, e.g. the 30 and 400 in "(30 - 400)".
    ///
    /// A pair counts when nothing but whitespace and a dash sits between the two numbers.
    static func rangeSpans(in numbers: [NumberToken], line: String) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var index = 0
        while index + 1 < numbers.count {
            let left = numbers[index]
            let right = numbers[index + 1]
            let between = line[left.range.upperBound..<right.range.lowerBound]
            let stripped = between.filter { !$0.isWhitespace }
            let isDash = stripped == "-" || stripped == "\u{2013}" || stripped == "\u{2014}" || stripped == "\u{2011}"
            let isWord = between.trimmingCharacters(in: .whitespaces).lowercased() == "to"
            if (isDash || isWord) && left.value <= right.value {
                spans.append(index...(index + 1))
                index += 2
            } else {
                index += 1
            }
        }
        return spans
    }

    /// The laboratory's own printed band, when the line carried one.
    ///
    /// Only a two-sided band is taken. A lone "> 40" is ambiguous — it might be the band,
    /// or it might be the result — so it is left alone rather than guessed at.
    private static func printedRange(spans: [ClosedRange<Int>], numbers: [NumberToken]) -> MarkerRange? {
        guard let span = spans.first else { return nil }
        let low = numbers.first { $0.order == span.lowerBound }
        let high = numbers.first { $0.order == span.upperBound }
        guard let low, let high else { return nil }
        return MarkerRange(minimum: low.value, maximum: high.value)
    }

    // MARK: - Units

    /// The text between a result and whatever follows it, which is where the unit lives.
    static func unitText(after result: NumberToken, in line: String, nextNumber: NumberToken?) -> String {
        let upperBound = nextNumber.map(\.range.lowerBound) ?? line.endIndex
        guard result.range.upperBound <= upperBound else { return "" }
        let slice = line[result.range.upperBound..<upperBound]
        // Drop anything that introduces the reference band rather than naming a unit.
        let stopWords = ["ref", "referans", "aralik", "aralık", "normal", "beklenen"]
        var candidate = String(slice)
        for stop in stopWords {
            if let found = candidate.range(of: stop, options: [.caseInsensitive, .diacriticInsensitive]) {
                candidate = String(candidate[candidate.startIndex..<found.lowerBound])
            }
        }
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " \t:|()[]*"))
        // A unit is short. Anything long is a comment that happened to follow the number.
        return trimmed.count <= 16 ? trimmed : ""
    }

    // MARK: - Dates

    /// The draw date, if the report printed one we can find.
    ///
    /// Lines that label themselves ("Numune Tarihi", "Rapor Tarihi") are preferred; failing
    /// that, the most frequent plausible date in the document wins, because the header date
    /// tends to be repeated on every page.
    static func detectDrawDate(in lines: [String], referenceDate: Date = Date()) -> Date? {
        let labels = ["numune", "alinma", "alinis", "kabul", "rapor", "tarih", "date", "collected", "sample"]
        var labelled: [Date] = []
        var all: [Date: Int] = [:]

        for line in lines {
            let normalized = BiomarkerCatalog.normalize(line)
            let isLabelled = labels.contains { normalized.contains($0) }
            for date in dates(in: line, referenceDate: referenceDate) {
                all[date, default: 0] += 1
                if isLabelled { labelled.append(date) }
            }
        }

        if let earliestLabelled = labelled.min() { return earliestLabelled }
        return all.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }?.key
    }

    /// Every plausible date in one line. Plausible means: a real calendar date, no later
    /// than today, and inside the last fifteen years.
    static func dates(in line: String, referenceDate: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        guard let earliest = calendar.date(byAdding: .year, value: -15, to: referenceDate) else { return [] }

        var found: [Date] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end].isNumber || characters[end] == "." || characters[end] == "/" || characters[end] == "-" {
                end += 1
            }
            let chunk = String(characters[index..<end])
            index = end

            let parts = chunk.split(whereSeparator: { $0 == "." || $0 == "/" || $0 == "-" }).map(String.init)
            guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { continue }

            var components = DateComponents()
            if parts[0].count == 4 {
                components.year = a; components.month = b; components.day = c
            } else {
                components.day = a; components.month = b; components.year = c < 100 ? 2000 + c : c
            }
            components.hour = 12
            guard let month = components.month, (1...12).contains(month) else { continue }
            guard let day = components.day, (1...31).contains(day) else { continue }
            guard let year = components.year, (1900...2200).contains(year) else { continue }
            guard let date = calendar.date(from: components) else { continue }
            guard date <= referenceDate, date >= earliest else { continue }
            found.append(date)
        }
        return found
    }
}
