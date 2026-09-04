//
//  EnduranceView.swift
//  Zenithium
//
//  The endurance screen. Faz 15.
//
//  Leads with critical pace, because that single number is what every other reading on the
//  screen is derived from — and saying so makes the zones and the predictions inspectable
//  rather than magic.
//

import SwiftUI
import Charts

struct EnduranceView: View {

    @ScaledMetric private var chartHeight: CGFloat = 150
    @State var viewModel: EnduranceViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Koşular okunuyor",
                    loadingLayout: .chart,
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Koşu")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.load() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumMagenta, intensity: 0.32)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: EnduranceViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if let model = content.model {
                criticalSpeedCard(model, summary: content.summary)
                if !content.zones.isEmpty { zonesCard(content.zones) }
                if !content.predictions.isEmpty { predictionsCard(content.predictions) }
            } else {
                notEnoughCard(content)
            }
            if !content.weeklyDistance.isEmpty { volumeCard(content.weeklyDistance) }
            heatCard(content.heat)
            shapesCard(content.shapes)
            if !content.efforts.isEmpty { effortsCard(content.efforts) }
        }
    }

    // MARK: - Critical speed

    private func criticalSpeedCard(_ model: CriticalSpeedModel, summary: String?) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text("Kritik tempo")
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Text(ZenithiumFormat.pace(secondsPerKilometre: model.criticalPace))
                    .font(ZenithiumFont.arcValue(size: 44))
                    .foregroundStyle(ZenithiumColor.textPrimary)

                if let summary {
                    Text(summary)
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(ZenithiumColor.hairline)

                HStack(spacing: ZenithiumSpacing.m) {
                    MetricTile(
                        label: "D′",
                        value: ZenithiumFormat.metric(model.anaerobicDistance, digits: 0),
                        unit: "m",
                        caption: "kritik hız üstü mesafe",
                        accessibilityLabelText: "Anaerobik mesafe"
                    )
                    MetricTile(
                        label: "Efor",
                        value: "\(model.effortCount)",
                        caption: "modeli kuran",
                        accessibilityLabelText: "Modeli kuran efor sayısı"
                    )
                    MetricTile(
                        label: "Uyum",
                        value: ZenithiumFormat.metric(model.rSquared, digits: 3),
                        caption: model.isWellConditioned ? "sağlam" : "zayıf",
                        accessibilityLabelText: "Modelin uyum katsayısı"
                    )
                }
            }
        }
    }

    private func notEnoughCard(_ content: EnduranceViewModel.Content) -> some View {
        SectionCard(title: "Model henüz kurulamadı") {
            Text("Kritik hız modeli için farklı uzunluklarda en az \(EnduranceEngine.minimumEfforts) koşu gerekiyor; \(content.efforts.count) tane var. 2–40 dakika arası, tempolu koşular en iyi veriyi verir.")
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Zones

    private func zonesCard(_ zones: [PaceZoneBand]) -> some View {
        SectionCard(title: "Tempo bölgeleri", subtitle: "Yaş formülünden değil, kendi eforlarından türetildi") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(zones) { band in
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                        HStack {
                            Text(band.zone.displayName)
                                .font(ZenithiumFont.headline)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Spacer()
                            Text("\(ZenithiumFormat.pace(secondsPerKilometre: band.fastPace)) – \(ZenithiumFormat.pace(secondsPerKilometre: band.slowPace))")
                                .font(ZenithiumFont.callout.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Text(band.zone.purpose)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                    .padding(.vertical, ZenithiumSpacing.s)
                    .accessibilityElement(children: .combine)

                    if band.id != zones.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }

    // MARK: - Predictions

    private func predictionsCard(_ predictions: [RacePrediction]) -> some View {
        SectionCard(title: "Yarış tahmini", subtitle: "Modelin uzattığı, senin verinle kalibre") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(predictions) { prediction in
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                        HStack {
                            Text(prediction.distance.displayName)
                                .font(ZenithiumFont.headline)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Spacer()
                            Text(ZenithiumFormat.longClock(seconds: prediction.seconds))
                                .font(ZenithiumFont.body.monospacedDigit())
                                .foregroundStyle(prediction.isReliable ? ZenithiumColor.textPrimary : ZenithiumColor.textTertiary)
                            Text(ZenithiumFormat.pace(secondsPerKilometre: prediction.pace))
                                .font(ZenithiumFont.caption.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textTertiary)
                                .frame(width: 68, alignment: .trailing)
                        }
                        if let caveat = prediction.caveat {
                            Text(caveat)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, ZenithiumSpacing.s)
                    .accessibilityElement(children: .combine)

                    if prediction.id != predictions.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }

    // MARK: - Recurring sessions

    /// The sessions this person keeps doing. Yol haritası v4, C8.
    ///
    /// Descriptive names only. The data says a forty-minute eight-kilometre run happened
    /// eight times; it does not say whether those were tempo runs or commutes, and naming
    /// them would be inferring an intention from a duration.
    @ViewBuilder
    private func shapesCard(_ shapes: [SessionShape]) -> some View {
        if !shapes.isEmpty {
            SectionCard(
                title: "Tekrar eden seanslar",
                subtitle: "Son \(SessionShapeEngine.windowDays) günde kaydettiklerinden"
            ) {
                VStack(spacing: ZenithiumSpacing.none) {
                    ForEach(shapes.prefix(4)) { shape in
                        HStack(spacing: ZenithiumSpacing.m) {
                            Image(systemName: shape.activity.symbolName)
                                .foregroundStyle(ZenithiumColor.spectrumViolet)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                                Text(shape.displayName)
                                    .font(ZenithiumFont.headline)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                    .lineLimit(2)
                                Text(SessionShapeEngine.summary(for: shape))
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }

                            Spacer(minLength: 0)

                            VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                                Text("\(shape.minutes) dk")
                                    .font(ZenithiumFont.dataValue.monospacedDigit())
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                if let rate = shape.averageHeartRate {
                                    Text("\(Int(rate.rounded())) bpm")
                                        .font(ZenithiumFont.caption2.monospacedDigit())
                                        .foregroundStyle(ZenithiumColor.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, ZenithiumSpacing.s)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(shape.displayName)
                        .accessibilityValue(SessionShapeEngine.summary(for: shape))

                        if shape.id != shapes.prefix(4).last?.id {
                            Divider().overlay(ZenithiumColor.hairlineSoft)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Heat

    /// Where heat adaptation stands. Yol haritası v4, C7.
    ///
    /// Reports the state and says nothing about what to do with a hot afternoon — §1 rules
    /// out telling somebody to train less because of the weather, and the app has no way to
    /// know whether they can hydrate, find shade, or stop.
    @ViewBuilder
    private func heatCard(_ state: HeatAcclimationState) -> some View {
        if let summary = HeatAcclimationEngine.summary(for: state) {
            SectionCard(title: "Sıcak ortam uyumu", subtitle: "Hava verisi kaydeden seanslardan") {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(ZenithiumColor.surfaceElevated)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ZenithiumColor.spectrumAmber.opacity(0.65),
                                            ZenithiumColor.spectrumAmber
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, proxy.size.width * state.adaptation))
                        }
                    }
                    .frame(height: 10)
                    .animation(.snappy, value: state.adaptation)
                    .accessibilityHidden(true)

                    Text(summary)
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(
                            state.isDecaying ? ZenithiumColor.spectrumAmber : ZenithiumColor.textSecondary
                        )
                        .fixedSize(horizontal: false, vertical: true)

                    if let peak = state.peakTemperature {
                        MetricTileGrid {
                            MetricTile(
                                label: "Sıcak seans",
                                value: "\(state.exposures.count)",
                                caption: "son \(HeatAcclimationEngine.windowDays) gün",
                                accessibilityLabelText: "Sıcak ortamdaki seans sayısı"
                            )
                            MetricTile(
                                label: "En sıcağı",
                                value: ZenithiumFormat.metric(peak, digits: 0),
                                unit: "°C",
                                accessibilityLabelText: "En yüksek seans sıcaklığı"
                            )
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sıcak ortam uyumu")
                .accessibilityValue(summary)
            }
        }
    }

    // MARK: - Volume
    private func volumeCard(_ weeks: [EnduranceViewModel.WeeklyDistance]) -> some View {
        let displayWeeks = ZenithiumChartDownsampler.downsample(weeks, maxPoints: 400, x: { $0.weekStart.timeIntervalSince1970 }, y: { $0.distance })
        return SectionCard(title: "Haftalık hacim", subtitle: "Kilometre") {
            Chart(displayWeeks) { week in
                BarMark(
                    x: .value("Hafta", week.weekStart, unit: .weekOfYear),
                    y: .value("Kilometre", week.distance)
                )
                .foregroundStyle(ZenithiumColor.spectrumMagenta.opacity(0.7))
            }
            .zenithiumChart(yValues: 3...4, showBaseline: true)
            // Saf çizim (Swift Charts): @ScaledMetric ile minHeight kullanılır.
            .frame(minHeight: chartHeight)
            // Playable, so a build-up or a drop in weekly volume is audible rather than
            // only being a label. Yol haritası v4, B8.
            .accessibilityChartDescriptor(
                SeriesChartDescriptor(
                    title: "Haftalık koşu mesafesi",
                    seriesName: "Kilometre",
                    points: weeks.map { DescribedPoint(date: $0.weekStart, value: $0.distance) },
                    formatValue: { "\(ZenithiumFormat.metric($0, digits: 1)) kilometre" },
                    summary: volumeSummary(weeks)
                )
            )
            .accessibilityLabel("Haftalık koşu mesafesi")
        }
    }

    /// How many weeks the chart covers, and the range they span.
    private func volumeSummary(_ weeks: [EnduranceViewModel.WeeklyDistance]) -> String {
        let distances = weeks.map(\.distance)
        guard let low = distances.min(), let high = distances.max() else {
            return "Henüz hafta yok"
        }
        return "\(weeks.count) hafta. En az \(ZenithiumFormat.metric(low, digits: 1)), en çok \(ZenithiumFormat.metric(high, digits: 1)) kilometre."
    }

    // MARK: - Efforts

    private func effortsCard(_ efforts: [BestEffort]) -> some View {
        SectionCard(title: "Modeli kuran koşular") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(efforts.prefix(8)) { effort in
                    HStack {
                        Text("\(ZenithiumFormat.metric(effort.distance / 1000, digits: 2)) km")
                            .font(ZenithiumFont.callout.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Spacer()
                        Text(ZenithiumFormat.longClock(seconds: effort.duration))
                            .font(ZenithiumFont.callout.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textSecondary)
                        Text(ZenithiumFormat.pace(secondsPerKilometre: effort.pace))
                            .font(ZenithiumFont.caption.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textTertiary)
                            .frame(width: 68, alignment: .trailing)
                    }
                    .padding(.vertical, ZenithiumSpacing.s)
                    .accessibilityElement(children: .combine)

                    if effort.id != efforts.prefix(8).last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }
}
