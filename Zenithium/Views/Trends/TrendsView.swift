//
//  TrendsView.swift
//  Zenithium
//
//  The Trends screen. Spec §10: 7 / 30 / 90-day ranges, scrubbable Swift Charts.
//

import SwiftUI

struct TrendsView: View {

    @State var viewModel: TrendsViewModel

    var body: some View {
        NavigationStack {
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
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Trendler")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.load() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.3)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
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
        VStack(spacing: ZenithiumSpacing.l) {
            SectionCard {
                TrendChart(content: content)
            }

            SectionCard(title: "Bu pencerede") {
                MetricTileGrid {
                    if let average = content.average {
                        MetricTile(
                            label: "Ortalama",
                            value: ZenithiumFormat.metric(average, digits: content.metric.fractionDigits),
                            unit: content.metric.unitSymbol,
                            accessibilityLabelText: "Ortalama \(content.metric.displayName)",
                            accessibilityValueText: "\(ZenithiumFormat.metric(average, digits: content.metric.fractionDigits)) \(content.metric.unitSymbol)"
                        )
                    }
                    if let minimum = content.minimum {
                        MetricTile(
                            label: "En düşük",
                            value: ZenithiumFormat.metric(minimum, digits: content.metric.fractionDigits),
                            unit: content.metric.unitSymbol,
                            accessibilityLabelText: "En düşük \(content.metric.displayName)",
                            accessibilityValueText: "\(ZenithiumFormat.metric(minimum, digits: content.metric.fractionDigits)) \(content.metric.unitSymbol)"
                        )
                    }
                    if let maximum = content.maximum {
                        MetricTile(
                            label: "En yüksek",
                            value: ZenithiumFormat.metric(maximum, digits: content.metric.fractionDigits),
                            unit: content.metric.unitSymbol,
                            accessibilityLabelText: "En yüksek \(content.metric.displayName)",
                            accessibilityValueText: "\(ZenithiumFormat.metric(maximum, digits: content.metric.fractionDigits)) \(content.metric.unitSymbol)"
                        )
                    }
                    MetricTile(
                        label: "Gün",
                        value: "\(content.points.count)",
                        caption: "veri olan",
                        accessibilityLabelText: "Veri olan günler",
                        accessibilityValueText: "\(content.points.count)"
                    )
                }
            }
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
