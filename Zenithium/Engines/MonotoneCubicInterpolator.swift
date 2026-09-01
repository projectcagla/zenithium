//
//  MonotoneCubicInterpolator.swift
//  Zenithium
//
//  Monotone cubic Hermite interpolation, Fritsch–Carlson (PCHIP). Spec §5.5 requires this
//  rather than Catmull-Rom, "which overshoots and produces alertness > 100", and §11 tests
//  that the arc never exceeds 100 anywhere.
//
//  The no-overshoot property is structural: after the Fritsch–Carlson tangent limiter runs,
//  the interpolant is monotone on every interval, so on each interval its value lies between
//  the two knot values that bound it. The curve therefore cannot exceed the largest knot
//  value — which for the circadian anchor set is exactly 100.
//

import Foundation

/// A fitted monotone cubic spline over strictly increasing knots.
struct MonotoneCubicInterpolator: Sendable, Equatable {

    private let xs: [Double]
    private let ys: [Double]
    private let tangents: [Double]

    /// Fits the spline. Returns `nil` when there are fewer than two knots or the abscissae
    /// are not strictly increasing — the caller must handle a degenerate anchor set rather
    /// than receive a silently wrong curve.
    init?(points: [(x: Double, y: Double)]) {
        guard points.count >= 2 else { return nil }
        let sorted = points.sorted { $0.x < $1.x }
        var xs: [Double] = []
        var ys: [Double] = []
        xs.reserveCapacity(sorted.count)
        ys.reserveCapacity(sorted.count)
        for point in sorted {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            if let last = xs.last, point.x <= last { return nil }
            xs.append(point.x)
            ys.append(point.y)
        }
        self.xs = xs
        self.ys = ys
        self.tangents = Self.fritschCarlsonTangents(xs: xs, ys: ys)
    }

    /// Evaluates the spline at `x`, clamping to the end knots outside the fitted range.
    func value(at x: Double) -> Double {
        guard let first = xs.first, let last = xs.last, let firstY = ys.first, let lastY = ys.last else {
            return 0
        }
        if x <= first { return firstY }
        if x >= last { return lastY }

        let index = intervalIndex(for: x)
        let x0 = xs[index]
        let x1 = xs[index + 1]
        let h = x1 - x0
        guard h > 0 else { return ys[index] }

        let t = (x - x0) / h
        let t2 = t * t
        let t3 = t2 * t

        // Hermite basis.
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return h00 * ys[index]
            + h10 * h * tangents[index]
            + h01 * ys[index + 1]
            + h11 * h * tangents[index + 1]
    }

    /// The largest knot value, which is also the curve's supremum (see the note above).
    var maximumKnotValue: Double {
        ys.max() ?? 0
    }

    /// Binary search for the interval containing `x`. `x` is known to be interior.
    private func intervalIndex(for x: Double) -> Int {
        var low = 0
        var high = xs.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if xs[mid] <= x {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    /// Fritsch–Carlson tangents: the three-step construction that makes the spline monotone.
    private static func fritschCarlsonTangents(xs: [Double], ys: [Double]) -> [Double] {
        let count = xs.count
        guard count >= 2 else { return Array(repeating: 0, count: count) }

        // 1. Secant slopes.
        var secants = [Double](repeating: 0, count: count - 1)
        for index in 0..<(count - 1) {
            let h = xs[index + 1] - xs[index]
            secants[index] = h > 0 ? (ys[index + 1] - ys[index]) / h : 0
        }

        // 2. Initial tangents: one-sided at the ends, averaged in the interior.
        var tangents = [Double](repeating: 0, count: count)
        tangents[0] = secants[0]
        tangents[count - 1] = secants[count - 2]
        for index in 1..<(count - 1) {
            tangents[index] = (secants[index - 1] + secants[index]) / 2
        }

        // 3. The limiter. A flat secant pins both surrounding tangents to zero; otherwise the
        //    tangent pair is projected back inside the circle of radius 3, which is the
        //    condition guaranteeing monotonicity on the interval.
        for index in 0..<(count - 1) {
            let secant = secants[index]
            if secant == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let alpha = tangents[index] / secant
            let beta = tangents[index + 1] / secant

            // A tangent pointing against the secant would create an overshoot before the
            // magnitude limiter ever applies, so it is flattened first.
            if alpha < 0 { tangents[index] = 0 }
            if beta < 0 { tangents[index + 1] = 0 }

            let a = tangents[index] / secant
            let b = tangents[index + 1] / secant
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                tangents[index] = tau * a * secant
                tangents[index + 1] = tau * b * secant
            }
        }
        return tangents
    }
}
