//
//  TrainingLoadView.swift
//  Zenithium
//
//  The training-load screen. Faz 14.
//
//  Three questions in four cards, in the order they get asked: where is the ratio, how did
//  it get there, how fit versus how fatigued, and what shape was the week. The band scale is
//  the one place on this screen carrying colour, because it is the only reading that changes
//  what the user does today.
//

import SwiftUI
import Charts

struct TrainingLoadView: View {

    @ScaledMetric private var chartHeight: CGFloat = 180
    @State var viewModel: TrainingLoadViewModel
    var embedInNavigation: Bool = true

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Yük")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .refreshable { await viewModel.load() }
            }
            .zenithiumBackground(tint: ZenithiumColor.spectrumAmber, intensity: 0.34)
            .task { await viewModel.onAppear() }
        } else {
            mainContent
                .zenithiumBackground(tint: ZenithiumColor.spectrumAmber, intensity: 0.34)
                .task { await viewModel.onAppear() }
        }
    }

    private var mainContent: some View {
        ScrollView {
            ViewStateContainer(
                state: viewModel.state,
                loadingLabel: "Yük geçmişi okunuyor",
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
    }

    @ViewBuilder
    private func loadedBody(_ content: TrainingLoadViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            ratioCard(content)
            chartCard(content)
            formCard(content)
            weekCard(content)
            Text(SafetyCopy.disclaimerFooter)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Ratio

    private func ratioCard(_ content: TrainingLoadViewModel.Content) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.m) {
                    Text(content.output.ratio.map { ZenithiumFormat.metric($0, digits: 2) } ?? "—")
                        .font(ZenithiumFont.arcValue(size: 46))
                        .foregroundStyle(content.output.ratio == nil ? ZenithiumColor.textTertiary : ZenithiumColor.textPrimary)
                    if let band = content.band {
                        Text(band.displayName)
                            .font(ZenithiumFont.caption)
                            .padding(.horizontal, ZenithiumSpacing.s)
                            .padding(.vertical, ZenithiumSpacing.xs)
                            .background(Capsule().fill(tint(for: band).opacity(0.18)))
                            .foregroundStyle(tint(for: band))
                    }
                    Spacer(minLength: 0)
                }
                Text(content.summary)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                bandScale(content.output.ratio)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yük oranı")
        .accessibilityValue(content.summary)
    }

    /// The band scale, with the current ratio marked on it.
    ///
    /// Drawn rather than listed because the bands are unequal widths, and a row of numbers
    /// would hide that the productive band is the widest thing on the axis.
    /// The hairline between two segments of the band scale.
    ///
    /// Deliberately off the spacing scale: this is a seam in a single continuous bar, not a
    /// gap between two elements, and on the scale's smallest step the segments would read as
    /// separate chips instead of one axis.
    private static let bandGap: CGFloat = 1.5

    private func bandScale(_ ratio: Double?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: Self.bandGap) {
                    ForEach(LoadBand.allCases, id: \.self) { band in
                        Rectangle()
                            .fill(tint(for: band).opacity(0.42))
                            .frame(width: max(0, bandWidth(band, in: width) - Self.bandGap))
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())

                if let ratio {
                    Capsule()
                        .fill(ZenithiumColor.textPrimary)
                        .frame(width: 3, height: 15)
                        .offset(x: position(of: ratio, in: width) - 1.5)
                }
            }
            .frame(height: 15)
        }
        .frame(height: 15)
        .accessibilityHidden(true)
    }

    /// The axis the scale spans. Wide enough to hold every band, tight enough that the
    /// productive band is not a sliver.
    private static let scaleRange: ClosedRange<Double> = 0.5...1.8

    private func position(of ratio: Double, in width: CGFloat) -> CGFloat {
        let range = Self.scaleRange
        let clamped = MathSupport.clamp(ratio, to: range)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound)) * width
    }

    /// Each band's share of the axis.
    private func bandWidth(_ band: LoadBand, in width: CGFloat) -> CGFloat {
        let range = Self.scaleRange
        let span = range.upperBound - range.lowerBound
        let bounds: (Double, Double)
        switch band {
        case .detraining: bounds = (range.lowerBound, 0.80)
        case .maintaining: bounds = (0.80, 1.00)
        case .productive: bounds = (1.00, 1.30)
        case .rising: bounds = (1.30, 1.50)
        case .spike: bounds = (1.50, range.upperBound)
        }
        return width * CGFloat((bounds.1 - bounds.0) / span)
    }

    // MARK: - Chart

    private func chartCard(_ content: TrainingLoadViewModel.Content) -> some View {
        SectionCard(title: "Günlük yük", subtitle: "Çubuklar günün yükü, çizgi yük oranı") {
            Chart {
                ForEach(content.series) { day in
                    BarMark(
                        x: .value("Gün", day.dayStart, unit: .day),
                        y: .value("Yük", day.load)
                    )
                    .foregroundStyle(ZenithiumColor.accent.opacity(0.55))
                }

                ForEach(content.ratioPoints) { point in
                    LineMark(
                        x: .value("Gün", point.dayStart, unit: .day),
                        y: .value("Oran", point.ratio * content.ratioScale),
                        series: .value("Seri", "oran")
                    )
                    .foregroundStyle(ZenithiumColor.spectrumAmber)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
            .zenithiumChartChrome()
            // Saf çizim (Swift Charts): @ScaledMetric ile minHeight kullanılır.
            .frame(minHeight: chartHeight)
            // The daily load, described so VoiceOver can play the block as a tone rather
            // than reading only its one-line summary. Yol haritası v4, B8.
            .accessibilityChartDescriptor(
                SeriesChartDescriptor(
                    title: "Günlük yük",
                    seriesName: "Yük",
                    points: content.series.map { DescribedPoint(date: $0.dayStart, value: $0.load) },
                    formatValue: { ZenithiumFormat.metric($0, digits: 0) },
                    summary: content.summary
                )
            )
            .accessibilityLabel("Günlük yük ve yük oranı")
            .accessibilityValue(content.summary)
        }
    }

    // MARK: - Form

    private func formCard(_ content: TrainingLoadViewModel.Content) -> some View {
        let values = content.output.fitnessFatigue
        return SectionCard(title: "Kondisyon ve yorgunluk", subtitle: "Yavaş ve hızlı yükün farkı") {
            HStack(spacing: ZenithiumSpacing.m) {
                MetricTile(
                    label: "Kondisyon",
                    value: ZenithiumFormat.metric(values.fitness, digits: 1),
                    accessibilityLabelText: "Kondisyon"
                )
                MetricTile(
                    label: "Yorgunluk",
                    value: ZenithiumFormat.metric(values.fatigue, digits: 1),
                    accessibilityLabelText: "Yorgunluk"
                )
                MetricTile(
                    label: "Form",
                    value: ZenithiumFormat.signed(values.form, digits: 1),
                    caption: values.formLabel,
                    accessibilityLabelText: "Form"
                )
            }
        }
    }

    // MARK: - Week

    private func weekCard(_ content: TrainingLoadViewModel.Content) -> some View {
        SectionCard(title: "Bu hafta") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(spacing: ZenithiumSpacing.m) {
                    MetricTile(
                        label: "Toplam",
                        value: ZenithiumFormat.metric(content.output.weekLoad, digits: 0),
                        accessibilityLabelText: "Bu haftanın toplam yükü"
                    )
                    MetricTile(
                        label: "Geçen hafta",
                        value: ZenithiumFormat.metric(content.output.previousWeekLoad, digits: 0),
                        accessibilityLabelText: "Geçen haftanın toplam yükü"
                    )
                    if let ramp = content.output.rampRate {
                        MetricTile(
                            label: "Değişim",
                            value: ZenithiumFormat.percentTR(ramp),
                            caption: ramp >= 0 ? "artış" : "azalış",
                            accessibilityLabelText: "Haftalık değişim"
                        )
                    }
                }
                if let monotonySummary = content.monotonySummary {
                    Text(monotonySummary)
                        .font(ZenithiumFont.footnote)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tint(for band: LoadBand) -> Color {
        switch band {
        case .detraining: return ZenithiumColor.spectrumIndigo
        case .maintaining: return ZenithiumColor.accent
        case .productive: return ZenithiumColor.green
        case .rising: return ZenithiumColor.yellow
        case .spike: return ZenithiumColor.red
        }
    }
}

#Preview("Yük · dolu") {
    TrainingLoadPreviewWrapper(state: .dolu)
}

#Preview("Yük · kalibrasyon") {
    TrainingLoadPreviewWrapper(state: .kalibrasyon)
}

#Preview("Yük · veri yok") {
    TrainingLoadPreviewWrapper(state: .veriyok)
}

private struct TrainingLoadPreviewWrapper: View {
    let state: PreviewState
    @State private var viewModel: TrainingLoadViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TrainingLoadView(viewModel: viewModel)
            } else {
                ZenithiumColor.background.ignoresSafeArea()
                    .task {
                        viewModel = await PreviewFixtures.shared.makeTrainingLoadViewModel(state: state)
                    }
            }
        }
    }
}
