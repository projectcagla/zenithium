//
//  SeriesChartDescriptor.swift
//  Zenithium
//
//  Audio graphs for the time-series charts. Yol haritası v4, B8.
//
//  The trends chart already described itself to VoiceOver, so someone navigating by speech
//  could play the series as a tone and hear where it moved. The training-load, endurance and
//  blood-marker charts only carried a one-line summary — accurate, but it says "yük oranı
//  1,12" and nothing about the shape that produced it, which is the entire reason those
//  screens draw a chart instead of printing a number.
//
//  This is the trends chart's descriptor, generalised: a titled series of dated values with
//  a formatter for each axis. The charts that have their own vocabulary keep their own
//  descriptor; everything that is "one line over time" uses this.
//
//  ASSUMPTION UI-7 still applies: this file imports `Accessibility` for the `AX…Descriptor`
//  types, which are first-party and add no capability beyond describing a chart.
//

import SwiftUI
import Accessibility
import Foundation

/// One dated value in a described series.
struct DescribedPoint: Sendable {

    let date: Date
    let value: Double
}

/// Describes a dated series to VoiceOver, so it can be played as an audio graph.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {

    /// What the chart is called.
    let title: String

    /// The series' own name, spoken before its values.
    let seriesName: String

    /// The points, oldest first.
    let points: [DescribedPoint]

    /// How a value is spoken — "1,12" reads differently from "112 milisaniye".
    let formatValue: @Sendable (Double) -> String

    /// A sentence placing the series: how many days, and where it sat.
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Gün",
            range: 0...Double(max(points.count - 1, 1)),
            gridlinePositions: []
        ) { position in
            let index = Int(position.rounded())
            guard points.indices.contains(index) else { return "" }
            return points[index].date.formatted(date: .abbreviated, time: .omitted)
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: seriesName,
            // The upper bound is nudged so a flat series still describes a range rather than
            // a single point, which VoiceOver renders as silence.
            range: min(lower, upper)...max(lower, upper + 1),
            gridlinePositions: [],
            valueDescriptionProvider: formatValue
        )

        let series = AXDataSeriesDescriptor(
            name: seriesName,
            isContinuous: true,
            dataPoints: points.enumerated().map { index, point in
                AXDataPoint(
                    x: Double(index),
                    y: point.value,
                    additionalValues: [],
                    label: point.date.formatted(date: .abbreviated, time: .omitted)
                )
            }
        )

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // Rebuilt whenever the points change, because they are part of the value this struct
        // is constructed from.
    }
}
