//
//  Sparkline.swift
//  Zenithium
//
//  The small series that sits at the end of a row. Faz 25.
//
//  A sparkline has one job: say whether the number in the row has been going up, down or
//  nowhere. So it carries no axis, no labels and no grid — anything else would compete with
//  the value it is annotating. The last point is marked, because "where it ended" is the
//  part the eye looks for.
//
//  It is `accessibilityHidden` at every call site: the row's own accessibility value already
//  says the number and where it sits, and a shape with no labels adds nothing to speech.
//

import SwiftUI

struct Sparkline: View {

    let values: [Double]
    var tint: Color = ZenithiumColor.accent

    /// How many points are drawn. More than this and the line is denser than the width can
    /// resolve, so the tail is taken — recent history is what a sparkline is for.
    private static let maximumPoints = 40

    var body: some View {
        Canvas { context, size in
            let points = Array(values.suffix(Self.maximumPoints))
            guard points.count >= 2 else { return }

            guard let minimum = points.min(), let maximum = points.max() else { return }
            let span = maximum - minimum
            // A flat series would divide by zero; drawing it down the middle is the honest
            // rendering of "this did not move".
            let denominator = span > 0 ? span : 1
            let offset = span > 0 ? minimum : minimum - 0.5

            func position(_ index: Int, _ value: Double) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let normalized = (value - offset) / denominator
                let y = size.height * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            for (index, value) in points.enumerated() {
                let point = position(index, value)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }

            context.stroke(
                path,
                with: .color(tint.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )

            let last = position(points.count - 1, points[points.count - 1])
            context.fill(
                Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)),
                with: .color(tint)
            )
        }
    }
}
