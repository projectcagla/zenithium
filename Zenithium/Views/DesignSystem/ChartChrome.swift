//
//  ChartChrome.swift
//  Zenithium
//
//  The shared look of every time-series chart. Yol haritası v4, B2.
//
//  Four screens — trends, training load, endurance and a single blood marker — each carried
//  their own copy of the same axis configuration: leading Y marks with monospaced digits,
//  automatic X marks at a softer grid line, both labelled in the tertiary text colour. Four
//  copies meant four places to miss when the grid line changed, and the drift had already
//  started: the X axis asked for three marks in one screen and four in the others for no
//  reason anybody had written down.
//
//  One modifier now. Where a chart genuinely needs something else — the hybrid analysis
//  labels its X axis by round number, not by date — it configures its own axes and does not
//  reach for this.
//

import Charts
import SwiftUI

/// How a chart labels its date axis.
enum ZenithiumChartDateAxis {

    /// "12 Şub" — for windows measured in weeks or a few months.
    case dayAndMonth

    /// "Şub 24" — for windows measured in years, where the day is noise.
    case monthAndYear
}

extension View {

    /// The house style for a time-series chart's axes.
    ///
    /// - Parameters:
    ///   - dateAxis: how the horizontal axis labels its dates.
    ///   - desiredXCount: roughly how many horizontal marks to aim for. Charts treats this
    ///     as a hint, so a narrower chart still drops labels rather than crowding them.
    func zenithiumChartChrome(
        dateAxis: ZenithiumChartDateAxis = .dayAndMonth,
        desiredXCount: Int = 3
    ) -> some View {
        self
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairlineSoft)
                    AxisValueLabel(anchor: .leading)
                        .foregroundStyle(ZenithiumColor.textTertiary.opacity(0.85))
                        .font(ZenithiumFont.caption.monospacedDigit())
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairlineSoft.opacity(0.5))
                    AxisTick().foregroundStyle(ZenithiumColor.hairlineSoft.opacity(0.5))
                    AxisValueLabel(anchor: .top, collisionResolution: .greedy)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .font(ZenithiumFont.caption)
                }
            }
    }
}
