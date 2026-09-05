//
//  TrendsView.swift
//  Zenithium
//
//  The Trends screen. Spec §10: 7 / 30 / 90-day ranges, scrubbable Swift Charts.
//

import SwiftUI
import SwiftData

struct TrendsView: View {

    @Query private var baselineStates: [BaselineState]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State var viewModel: TrendsViewModel
    var embedInNavigation: Bool = true

    @Namespace private var trendsNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    actionCallout: "En az 3 günlük veri toplandığında eğilimler burada görünecek.",
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
                    Text("\(range.days)G")
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
                            isSelected: metric == viewModel.metric,
                            namespace: trendsNamespace
                        ) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                viewModel.select(metric: metric)
                            }
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
        let reference = reference(for: content)
        VStack(alignment: .leading, spacing: ZenithiumSpacing.sectionSpacing) {
            Text(content.metric.displayName.uppercased(with: Locale(identifier: "tr_TR"))).zenithiumEyebrow()
            TrendChart(content: content, baseline: reference.mean, sigma: reference.sigma, referenceLabel: reference.label)
            statistics(content, baseline: reference.mean)
            SectionBlock(title: "Kendi ritmini izle") {
                Text("\(reference.label). Koridor ±1 standart sapmayı gösterir; bir sağlık sınırı değildir.")
                    .zenithiumSecondary()
                if !content.bloodEvents.isEmpty {
                    Label("Kesikli dikey çizgiler tahlil günlerini gösterir.", systemImage: "drop")
                        .zenithiumCaption()
                    ForEach(content.bloodEvents) { event in
                        Text("\(event.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))) · \(event.panelName)")
                            .zenithiumCaption()
                    }
                }
                Text("\(content.points.count) ölçüm günü · Grafikte bir güne dokunarak değerini incele.")
                    .zenithiumCaption()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: content.metric)
    }

    private func reference(for content: TrendsViewModel.Content) -> (mean: Double?, sigma: Double?, label: String) {
        let kind: MetricKind?
        switch content.metric {
        case .heartRateVariability: kind = .heartRateVariability
        case .restingHeartRate: kind = .restingHeartRate
        default: kind = nil
        }
        if let kind {
            if let snapshot = baselineStates.compactMap(\.snapshot).first(where: { $0.metric == kind && $0.isSeeded }) {
                return (snapshot.mean, snapshot.standardDeviation, "Mevcut 60 günlük ağırlıklı kişisel taban")
            }
            return (nil, nil, "Kişisel taban henüz oluşmadı")
        }
        let values = content.points.map(\.value).filter(\.isFinite)
        guard let average = content.average, values.count > 1 else { return (content.average, nil, "Seçili dönem ortalaması") }
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return (average, sqrt(variance), "Seçili \(content.range.days) günün ortalaması")
    }

    private func statistics(_ content: TrendsViewModel.Content, baseline: Double?) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
        let delta = content.points.last.flatMap { point in baseline.map { point.value - $0 } }
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            stat("Ortalama", value: content.average, content: content)
            stat("En düşük", value: content.minimum, content: content)
            stat("En yüksek", value: content.maximum, content: content)
            stat("Taban farkı", value: delta, content: content, signed: true)
        }
    }

    private func stat(_ label: String, value: Double?, content: TrendsViewModel.Content, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).zenithiumCaption()
            Text(value.map { signed ? ZenithiumFormat.signed($0, digits: content.metric.fractionDigits) : formatted($0, metric: content.metric) } ?? "—")
                .modifier(ZenithiumFont.Scaled(size: 28, relativeTo: .title2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(content.metric.unitSymbol == "%" ? (signed ? "puan" : "yüzde") : content.metric.unitSymbol)
                .zenithiumCaption()
        }
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ value: Double, metric: TrendMetric) -> String {
        let number = ZenithiumFormat.metric(value, digits: metric.fractionDigits)
        return metric.unitSymbol == "%" ? "%" + number : number
    }

}

/// A metric selector chip.
private struct MetricPill: View {

    let metric: TrendMetric
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(metric.displayName)
                .font(ZenithiumFont.label)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ZenithiumSpacing.m)
                .padding(.vertical, ZenithiumSpacing.m)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(ZenithiumColor.accent.opacity(0.20))
                            .matchedGeometryEffect(id: "trend-pill-selection", in: namespace)
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.clear)
                    }
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
