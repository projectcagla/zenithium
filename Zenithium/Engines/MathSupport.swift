//
//  MathSupport.swift
//  Zenithium
//
//  Shared numeric helpers for the engines. Foundation only, pure, and total: every function
//  here has a defined result for every input, including degenerate ones (§15 rule 8 — every
//  division has a guarded denominator).
//
//  ASSUMPTION CONST-2: like `EngineConstants`, this file is a **leaf** — it reads `Domain` and
//  nothing else, and any layer may read it. That is what lets a view clamp a ring's progress
//  without reimplementing `clamp`, without the view layer depending on the engines, and
//  without a second definition of the same three lines.
//

import Foundation

enum MathSupport {

    /// Clamps a value into a closed range. Non-finite input returns the lower bound, so a
    /// NaN can never propagate into a score.
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Clamps a value into an explicit pair of bounds.
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard lower <= upper else { return lower }
        return clamp(value, to: lower...upper)
    }

    /// Divides, returning `fallback` when the denominator is zero or either side is not finite.
    static func safeDivide(_ numerator: Double, by denominator: Double, fallback: Double = 0) -> Double {
        guard numerator.isFinite, denominator.isFinite, denominator != 0 else { return fallback }
        let result = numerator / denominator
        return result.isFinite ? result : fallback
    }

    /// Formats a decimal number with comma for deterministic Turkish text without C runtime float issues.
    static func decimal(_ value: Double, digits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        let factor = pow(10.0, Double(max(0, digits)))
        let rounded = (value * factor).rounded() / factor
        let intPart = Int(rounded)
        let fracPart = Int(((rounded - Double(intPart)) * factor).rounded())
        if digits == 0 { return "\(intPart)" }
        return "\(intPart),\(abs(fracPart))"
    }

    /// The logistic curve used by the recovery score (§5.1):
    /// `100 / (1 + e^(−slope · z))`.
    ///
    /// The exponent is clamped before `exp` so an extreme `z` saturates rather than
    /// overflowing to infinity.
    static func logisticPercentage(_ z: Double, slope: Double) -> Double {
        guard z.isFinite, slope.isFinite else { return 50 }
        let exponent = clamp(-slope * z, -60, 60)
        return 100 / (1 + exp(exponent))
    }

    /// Winsorizes a value to `mean ± multiple · sigma` (§4.2.2).
    ///
    /// Returns the clamped value and whether clamping occurred, because §4.2.2 requires the
    /// raw value to be logged and the clamped one stored.
    static func winsorize(
        _ value: Double,
        mean: Double,
        sigma: Double,
        multiple: Double
    ) -> (value: Double, wasClamped: Bool) {
        guard value.isFinite, mean.isFinite, sigma.isFinite, sigma > 0, multiple > 0 else {
            return (value, false)
        }
        let bound = multiple * sigma
        let lower = mean - bound
        let upper = mean + bound
        if value < lower { return (lower, true) }
        if value > upper { return (upper, true) }
        return (value, false)
    }

    /// The arithmetic mean, or `nil` for an empty input rather than a sentinel zero.
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Double(values.count)
    }

    /// The unbiased sample variance (`n − 1` denominator), or `nil` below two values.
    static func sampleVariance(_ values: [Double]) -> Double? {
        guard values.count >= 2, let average = mean(values) else { return nil }
        let squaredDeviations = values.reduce(into: 0.0) { total, value in
            let deviation = value - average
            total += deviation * deviation
        }
        return squaredDeviations / Double(values.count - 1)
    }

    /// The `p`-th percentile by nearest rank, or `nil` for an empty input.
    static func percentile(_ p: Double, of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = clamp(p, 0, 1) * Double(sorted.count - 1)
        let index = min(max(Int(position.rounded(.up)), 0), sorted.count - 1)
        return sorted[index]
    }

    /// The signed shortest distance between two points on a circle of `period` units.
    ///
    /// This is what makes 23:50 and 00:10 twenty minutes apart rather than twenty-three
    /// hours and forty (ASSUMPTION SLEEP-5).
    static func circularDifference(_ a: Double, _ b: Double, period: Double) -> Double {
        guard period > 0, a.isFinite, b.isFinite else { return 0 }
        let raw = (a - b).truncatingRemainder(dividingBy: period)
        if raw > period / 2 { return raw - period }
        if raw < -period / 2 { return raw + period }
        return raw
    }

    /// The circular mean of angles expressed as positions on a circle of `period` units.
    ///
    /// Returns `nil` for an empty input, or when the vectors cancel exactly and no mean
    /// direction exists — which is honest rather than returning an arbitrary point.
    static func circularMean(_ values: [Double], period: Double) -> Double? {
        guard !values.isEmpty, period > 0 else { return nil }
        var sumSin = 0.0
        var sumCos = 0.0
        for value in values {
            let angle = value / period * 2 * .pi
            sumSin += sin(angle)
            sumCos += cos(angle)
        }
        guard abs(sumSin) > 1e-12 || abs(sumCos) > 1e-12 else { return nil }
        var angle = atan2(sumSin, sumCos)
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi) * period
    }

    /// Wraps a value into `[0, period)`.
    static func wrap(_ value: Double, period: Double) -> Double {
        guard period > 0, value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder < 0 ? remainder + period : remainder
    }

    /// Rounds to a number of decimal places, for values that are persisted or asserted.
    static func rounded(_ value: Double, places: Int) -> Double {
        guard value.isFinite, places >= 0, places <= 12 else { return value }
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    /// Renormalizes a set of weights so they sum to 1.0 (§4.3).
    ///
    /// Returns an empty dictionary when the surviving weights sum to zero, so a caller can
    /// tell "nothing left to weigh" from "everything weighs the same" — §4.3 forbids
    /// substituting zero for a dropped term, and this is the same rule one level up.
    /// The ordinary least-squares slope of `ys` against `xs`.
    ///
    /// `nil` when the two are not the same length, when there are fewer than two points, or
    /// when every `x` is the same — a vertical line has no slope, and returning a very large
    /// number for one would be worse than returning nothing.
    ///
    /// The units are whatever `y`'s units are, per unit of `x`. Callers decide what `x`
    /// means: days for a vital's trend, years for a laboratory marker's rate of change.
    static func leastSquaresSlope(xs: [Double], ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        guard let meanX = mean(xs), let meanY = mean(ys) else { return nil }

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    static func renormalize<Key: Hashable>(_ weights: [Key: Double]) -> [Key: Double] {
        let total = weights.values.reduce(0, +)
        guard total > 0, total.isFinite else { return [:] }
        return weights.mapValues { $0 / total }
    }
}
