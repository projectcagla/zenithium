//
//  TrendsView.swift
//  Zenithium
//
//  The Trends screen. Spec §10: 7 / 30 / 90-day ranges, scrubbable Swift Charts.
//

import SwiftUI

struct TrendsView: View {

    @State var viewModel: TrendsViewModel
    var embedInNavigation: Bool = true

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Trendler")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .refreshable { await viewModel.load() }
            }
            .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.3)
            .task { await viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
        } else {
            mainContent
                .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.3)
                .task { await viewModel.onAppear() }
                .onDisappear { viewModel.onDisappear() }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.l) {
                controls
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Geçmiş yükleniyor",
                    loadingLayout: .chart,
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
            }
            .padding(.horizontal, ZenithiumSpacing.screenEdge)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    private var controls: some View {
        VStack(spacing: ZenithiumSpacing.m) {
            Picker("Aralık", selection: rangeBinding) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.displayName)
                        .accessibilityLabel(range.accessibilityName)
                        .tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Zaman aralığı")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ZenithiumSpacing.s) {
                    ForEach(TrendMetric.allCases) { metric in
                        MetricPill(
                            metric: metric,
                            isSelected: metric == viewModel.metric
                        ) {
                            viewModel.select(metric: metric)
                        }
                    }
                }
                .padding(.horizontal, ZenithiumSpacing.xxs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityLabel("Ölçüm")
        }
    }

    /// A binding that routes through the view model's explicit setter (ASSUMPTION VM-3).
    private var rangeBinding: Binding<TrendRange> {
        Binding(
            get: { viewModel.range },
            set: { viewModel.select(range: $0) }
        )
    }

    @ViewBuilder
    private func loadedBody(_ content: TrendsViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Tam Genişlik Kartsız Grafik (Üstte Seçili Değer & Tarih)
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text(content.metric.displayName.uppercased())
                    .zenithiumEyebrow()

                let values = content.points.map(\.value)
                let avg = content.average ?? (values.last ?? 50.0)
                let variance = values.isEmpty ? 4.0 : (values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count))
                let sigma = max(sqrt(variance), 2.0)

                BaselineBand(
                    values: values,
                    baseline: avg,
                    sigma: sigma,
                    unit: content.metric.unitSymbol,
                    style: .full
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // TEK L2 KART: Değişim Özeti
            changeSummaryCard(content)
        }
    }

    /// Detaylı Swift Charts grafiği
    private func trendChartDetailed(_ content: TrendsViewModel.Content) -> some View {
        TrendChart(content: content)
            .zenithiumChart(yValues: 3...4, showBaseline: true)
    }

    private func changeSummaryCard(_ content: TrendsViewModel.Content) -> some View {
        let trendDirection = trendSlopeDirection(content)

        return SectionCard(
            title: "Değişim Özeti",
            subtitle: "\(content.range.displayName) içindeki seyir"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text("Ortalama")
                            .zenithiumCaption()
                        if let average = content.average {
                            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                                Text(ZenithiumFormat.metric(average, digits: content.metric.fractionDigits))
                                    .metricNumeral()
                                Text(content.metric.unitSymbol)
                                    .metricUnit()
                            }
                        } else {
                            Text("—").metricNumeral()
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                        Text("Eğilim")
                            .zenithiumCaption()
                        HStack(spacing: ZenithiumSpacing.xs) {
                            Image(systemName: trendDirection.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(trendDirection.color)
                            Text(trendDirection.text)
                                .sectionTitle()
                                .foregroundStyle(trendDirection.color)
                        }
                    }
                }

                Divider().overlay(ZenithiumColor.hairlineSoft)

                HStack(spacing: ZenithiumSpacing.none) {
                    if let minimum = content.minimum {
                        summaryMiniStat(
                            label: "En Düşük",
                            value: ZenithiumFormat.metric(minimum, digits: content.metric.fractionDigits),
                            unit: content.metric.unitSymbol
                        )
                    }
                    Spacer()
                    if let maximum = content.maximum {
                        summaryMiniStat(
                            label: "En Yüksek",
                            value: ZenithiumFormat.metric(maximum, digits: content.metric.fractionDigits),
                            unit: content.metric.unitSymbol
                        )
                    }
                    Spacer()
                    summaryMiniStat(
                        label: "Veri Günü",
                        value: "\(content.points.count)",
                        unit: "gün"
                    )
                }
            }
        }
    }

    private func summaryMiniStat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
            Text(label)
                .zenithiumCaption()
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                Text(value)
                    .sectionTitle()
                    .monospacedDigit()
                Text(unit)
                    .zenithiumCaption()
            }
        }
    }

    private func trendSlopeDirection(_ content: TrendsViewModel.Content) -> (symbol: String, color: Color, text: String) {
        guard content.points.count >= 2,
              let first = content.points.first?.value,
              let last = content.points.last?.value else {
            return ("arrow.right", ZenithiumColor.textTertiary, "Yatay")
        }
        let delta = last - first
        let threshold = abs(first) * 0.03
        if delta > threshold {
            return ("arrow.up.right", ZenithiumColor.green, "Yukarı")
        } else if delta < -threshold {
            return ("arrow.down.right", ZenithiumColor.yellow, "Aşağı")
        } else {
            return ("arrow.right", ZenithiumColor.textSecondary, "Dengeli")
        }
    }
}

/// A metric selector chip.
private struct MetricPill: View {

    let metric: TrendMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(metric.displayName)
                .font(ZenithiumFont.label)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ZenithiumSpacing.m)
                .padding(.vertical, ZenithiumSpacing.s)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? ZenithiumColor.accent.opacity(0.20) : ZenithiumColor.surface)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? ZenithiumColor.accent : ZenithiumColor.hairline,
                            lineWidth: 1
                        )
                }
                .foregroundStyle(isSelected ? ZenithiumColor.accent : ZenithiumColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Trendler · dolu") {
    TrendsPreviewWrapper(state: .dolu)
}

#Preview("Trendler · kalibrasyon") {
    TrendsPreviewWrapper(state: .kalibrasyon)
}

#Preview("Trendler · veri yok") {
    TrendsPreviewWrapper(state: .veriyok)
}

private struct TrendsPreviewWrapper: View {
    let state: PreviewState
    @State private var viewModel: TrendsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TrendsView(viewModel: viewModel)
            } else {
                ZenithiumColor.background.ignoresSafeArea()
                    .task {
                        viewModel = await PreviewFixtures.shared.makeTrendsViewModel(state: state)
                    }
            }
        }
    }
}
