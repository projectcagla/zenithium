import SwiftUI
import Charts

struct TrainingLoadView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                actionCallout: "Antrenman uygulamasından ilk antrenmanınızı kaydedin.",
                retry: { await viewModel.load() },
                requestAccess: nil
            ) { content in
                loadedBody(content)
            }
            .padding(.horizontal, ZenithiumSpacing.screenEdge)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func loadedBody(_ content: TrainingLoadViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Akut/Kronik oran göstergesi (kartsız)
            ratioHero(content)

            // 2. KADEME: Yük dengesi kartı (TEK L2 KART)

            // 3. KADEME: Günlük yük çubukları (Swift Charts, kartsız L1)
            chartCard(content)

            // 4. KADEME: Yorgunluk ve zindelik ayrımı (kartsız L1)
            if content.output.hasEnoughHistory { formCard(content) }
            balanceCard(content)

            // 5. KADEME: Bu hafta özeti (kartsız L1)
            if content.output.consecutiveObservedDays >= 14 { weekCard(content) }

            Text(SafetyCopy.disclaimerFooter)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 1. KADEME (KAHRAMAN): Akut/Kronik Oran Göstergesi (Kartsız)

    private func ratioHero(_ content: TrainingLoadViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Text("AKUT / KRONİK YÜK ORANI")
                .zenithiumEyebrow()

            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.m) {
                Text(content.output.ratio.map { ZenithiumFormat.metric($0, digits: 2) } ?? "—")
                    .heroNumeral()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: content.output.ratio)
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

            bandScale(content.output.ratio)
            HStack {
                Text("Azalan yük")
                Spacer()
                Text("Yakın yük")
                Spacer()
                Text("Ani artış")
            }
            .zenithiumCaption()
            Text("7 günlük akut / 28 günlük kronik yük").zenithiumCaption()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yük oranı")
        .accessibilityValue(content.summary)
    }

    // MARK: - 2. KADEME: Yük Dengesi Kartı (TEK L2 KART)

    private func balanceCard(_ content: TrainingLoadViewModel.Content) -> some View {
        SectionCard(
            title: "Yük Dengesi",
            subtitle: content.band?.displayName ?? "Hesaplanıyor"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Image(systemName: content.band == nil ? "circle.dotted" : (content.band == .productive ? "checkmark.circle.fill" : "chart.bar.xaxis"))
                    .font(.system(size: 20))
                    .foregroundStyle(content.band.map(tint(for:)) ?? ZenithiumColor.accent)
                    .accessibilityHidden(true)

                Text(content.summary)
                    .zenithiumCallout()
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let ceiling = content.sweetSpotCeiling {
                    Text("Oranı 1,30 altında tutan model yükü: \(ZenithiumFormat.metric(ceiling, digits: 0)) TRIMP")
                        .zenithiumCaption()
                }
                Text("Yük oranı tek başına sakatlık olasılığını ölçmez; toparlanma ve hissettiğin yorgunlukla birlikte değerlendirilir.")
                    .zenithiumCaption()
            }
        }
        .accessibilityElement(children: .combine)
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
                            .fill(ZenithiumColor.textSecondary.opacity(0.22))
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

    // MARK: - 3. KADEME: Günlük Yük Çubukları (Swift Charts, Kartsız L1)

    private func chartCard(_ content: TrainingLoadViewModel.Content) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let end = content.series.last?.dayStart ?? .distantPast
        let start = calendar.date(byAdding: .day, value: -27, to: end) ?? end
        let days = content.series.filter { $0.dayStart >= start }
        return SectionBlock(title: "Son 28 gün", subtitle: "Kayıtlı nabız yükü · TRIMP") {
            Chart(days) { day in
                BarMark(x: .value("Gün", day.dayStart, unit: .day), y: .value("Nabız yükü", day.load))
                    .foregroundStyle(ZenithiumColor.accent.opacity(0.7))
            }
            .chartXScale(domain: start...max(start.addingTimeInterval(1), end))
            .zenithiumChart(yValues: 3...4, showBaseline: true)
            .frame(minHeight: chartHeight)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: "Kayıtlı nabız yükü", seriesName: "TRIMP",
                points: days.map { DescribedPoint(date: $0.dayStart, value: $0.load) },
                formatValue: { "\(ZenithiumFormat.metric($0, digits: 0)) TRIMP" }, summary: content.summary))
            Text("\(days.count) kayıtlı gün. Eksik günler boş bırakılır; sıfır yük olarak tamamlanmaz. Oran için 28 kesintisiz kayıtlı gün ve en az 8 etkin gün gerekir.").zenithiumCaption()
        }
    }

    // MARK: - 4. KADEME: Kondisyon ve Yorgunluk (Kartsız L1)

    private func formCard(_ content: TrainingLoadViewModel.Content) -> some View {
        let values = content.output.fitnessFatigue
        return SectionBlock(title: "Yavaş ve hızlı yük", subtitle: "Yavaş ve hızlı yükün farkı") {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                MetricTile(
                    label: "Uzun dönem",
                    value: ZenithiumFormat.metric(values.fitness, digits: 1),
                    accessibilityLabelText: "Kondisyon"
                )
                MetricTile(
                    label: "Kısa dönem",
                    value: ZenithiumFormat.metric(values.fatigue, digits: 1),
                    accessibilityLabelText: "Yorgunluk"
                )
                MetricTile(
                    label: "Fark",
                    value: ZenithiumFormat.signed(values.form, digits: 1),
                    caption: "Model farkı",
                    accessibilityLabelText: "Form"
                )
            }
        }
    }

    // MARK: - 5. KADEME: Hafta Özeti (Kartsız L1)

    private func weekCard(_ content: TrainingLoadViewModel.Content) -> some View {
        SectionBlock(title: "Bu hafta") {
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
