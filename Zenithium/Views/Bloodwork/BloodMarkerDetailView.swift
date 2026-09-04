//
//  BloodMarkerDetailView.swift
//  Zenithium
//
//  One marker's history. Spec §12: trends and reference ranges only.
//

import SwiftUI
import Charts

struct BloodMarkerDetailView: View {

    @ScaledMetric private var chartHeight: CGFloat = 180
    let series: BloodworkViewModel.MarkerSeries
    let viewModel: BloodworkViewModel

    /// The rate of change, or the reason there isn't one yet.
    ///
    /// Saying why a number is missing is worth a line: without it, someone with two draws
    /// three weeks apart concludes the feature is broken rather than that the app is
    /// declining to draw a trend through two points. Yol haritası v4, C3.
    private var rateSubtitle: String? {
        guard let unit = series.latest?.unitSymbol else { return nil }
        if let rate = series.annualRate {
            return "Yılda \(ZenithiumFormat.signed(rate, digits: series.marker.fractionDigits)) \(unit)"
        }
        guard series.entries.count >= BloodworkViewModel.MarkerSeries.minimumDrawsForRate else {
            return "Değişim hızı için en az \(BloodworkViewModel.MarkerSeries.minimumDrawsForRate) ölçüm gerekiyor"
        }
        return "Değişim hızı için en az altı aylık aralık gerekiyor"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.l) {
                if series.entries.count >= 2 {
                    chartCard
                }
                impactCard
                historyCard
                rangeCard
            }
            .padding(.horizontal, ZenithiumSpacing.l)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle(series.marker.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
    }

    private var chartCard: some View {
        let displayEntries = ZenithiumChartDownsampler.downsample(
            series.entries,
            maxPoints: 400,
            x: { $0.drawnAt.timeIntervalSince1970 },
            y: { $0.value }
        )
        return SectionCard(title: "Zaman içinde", subtitle: rateSubtitle) {
            Chart {
                if let range = displayEntries.first?.referenceRange,
                   let minimum = range.minimum,
                   let maximum = range.maximum {
                    RectangleMark(
                        yStart: .value("Referans alt", minimum),
                        yEnd: .value("Referans üst", maximum)
                    )
                    .foregroundStyle(ZenithiumColor.textSecondary.opacity(0.10))
                }

                ForEach(displayEntries) { entry in
                    AreaMark(
                        x: .value("Alınma", entry.drawnAt),
                        y: .value(series.marker.displayName, entry.value)
                    )
                    .foregroundStyle(ZenithiumChartGradient.area(for: ZenithiumColor.accent))

                    LineMark(
                        x: .value("Alınma", entry.drawnAt),
                        y: .value(series.marker.displayName, entry.value)
                    )
                    .foregroundStyle(ZenithiumColor.accent)
                    .lineStyle(ZenithiumChartLine.strokeStyle)

                    PointMark(
                        x: .value("Alınma", entry.drawnAt),
                        y: .value(series.marker.displayName, entry.value)
                    )
                    .foregroundStyle(ZenithiumColor.accent)
                }

                if let lastEntry = displayEntries.last {
                    PointMark(
                        x: .value("Alınma", lastEntry.drawnAt),
                        y: .value(series.marker.displayName, lastEntry.value)
                    )
                    .foregroundStyle(ZenithiumColor.accent)
                    .symbolSize(ZenithiumChartLastPoint.symbolSize)
                    .annotation(position: .top, alignment: .trailing) {
                        Text(ZenithiumFormat.metric(lastEntry.value, digits: 1))
                            .font(ZenithiumFont.caption.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }
            }
            .chartYScale(domain: series.axisRange ?? 0...1)
            .zenithiumChart(yValues: 3...4, showBaseline: true)
            // Saf çizim (Swift Charts): sabit 180pt yerine @ScaledMetric ile minHeight kullanılır.
            .frame(minHeight: chartHeight)
            // A marker's shape over years is the point of this screen, so it is playable
            // rather than only summarised. Yol haritası v4, B8.
            .accessibilityChartDescriptor(
                SeriesChartDescriptor(
                    title: series.marker.accessibilityName,
                    seriesName: series.marker.displayName,
                    // `entries` is newest first for the list; an audio graph reads left to
                    // right, so it is reversed here.
                    points: series.entries.reversed().map {
                        DescribedPoint(date: $0.drawnAt, value: $0.value)
                    },
                    formatValue: { [digits = series.marker.fractionDigits] value in
                        ZenithiumFormat.metric(value, digits: digits)
                    },
                    summary: chartAccessibilityValue
                )
            )
            .accessibilityElement()
            .accessibilityLabel("\(series.marker.accessibilityName) zaman içinde")
            .accessibilityValue(chartAccessibilityValue)
        }
    }

    private var chartAccessibilityValue: String {
        let readings = series.entries.prefix(6).map { entry in
            "\(ZenithiumFormat.metric(entry.value, digits: series.marker.fractionDigits)) on \(entry.drawnAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return readings.joined(separator: ", ")
    }

    private var historyCard: some View {
        SectionCard(title: "Sonuçlar") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(series.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.m) {
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(entry.drawnAt.formatted(date: .abbreviated, time: .omitted))
                                .font(ZenithiumFont.label)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(ZenithiumFormat.metric(entry.value, digits: series.marker.fractionDigits))
                            .font(ZenithiumFont.callout.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text(entry.unitSymbol)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)

                        Button(role: .destructive) {
                            Task { await viewModel.delete(id: entry.id) }
                        } label: {
                            Image(systemName: "trash").imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ZenithiumColor.red)
                        .accessibilityLabel("\(entry.drawnAt.formatted(date: .abbreviated, time: .omitted)) tarihli sonucu sil")
                    }
                    .padding(.vertical, ZenithiumSpacing.m)
                    .accessibilityElement(children: .contain)

                    if entry.id != series.entries.last?.id {
                        Divider().overlay(ZenithiumColor.hairline)
                    }
                }
            }
        }
    }

    private var rangeCard: some View {
        SectionCard(title: "Aralıklar") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                rangeRow(
                    title: "Referans",
                    range: series.latest?.referenceRange ?? series.marker.referenceRange,
                    caption: SafetyCopy.bloodworkRangeCaption
                )
                Divider().overlay(ZenithiumColor.hairline)
                rangeRow(
                    title: "Sık anılan",
                    range: series.latest?.optimalRange ?? series.marker.optimalRange,
                    caption: SafetyCopy.bloodworkOptimalCaption
                )
            }
        }
    }

    private func rangeRow(title: String, range: MarkerRange, caption: String) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            HStack {
                Text(title)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Spacer(minLength: 8)
                Text(rangeText(range))
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
            Text(caption)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func rangeText(_ range: MarkerRange) -> String {
        let digits = series.marker.fractionDigits
        switch (range.minimum, range.maximum) {
        case (let minimum?, let maximum?):
            return "\(ZenithiumFormat.metric(minimum, digits: digits))–\(ZenithiumFormat.metric(maximum, digits: digits))"
        case (let minimum?, nil):
            return "≥ \(ZenithiumFormat.metric(minimum, digits: digits))"
        case (nil, let maximum?):
            return "≤ \(ZenithiumFormat.metric(maximum, digits: digits))"
        case (nil, nil):
            return "Girilmemiş"
        }
    }

    private var impactCard: some View {
        SectionCard(title: "Bu değer uygulamayı nasıl etkiliyor?") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                if let modifier = ClinicalModifierRegistry.modifier(forMarkerKey: series.marker.storageKey) {
                    HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(ZenithiumColor.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            HStack {
                                Text(modifier.title)
                                    .font(ZenithiumFont.label)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                Spacer()
                                if modifier.multiplier < 1.0 {
                                    Text("×\(ZenithiumFormat.metric(modifier.multiplier, digits: 2))")
                                        .font(ZenithiumFont.callout.monospacedDigit())
                                        .foregroundStyle(ZenithiumColor.spectrumAmber)
                                }
                            }
                            Text(modifier.rationale)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Bu değer hesaplamaları etkilemiyor; yalnızca kaydediliyor.")
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
