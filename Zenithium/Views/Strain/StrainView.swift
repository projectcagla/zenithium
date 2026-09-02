//
//  StrainView.swift
//  Zenithium
//
//  The Strain screen — "how hard should I go". Spec §1, §5.3, §10.
//

import SwiftUI

struct StrainView: View {

    @State var viewModel: StrainViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Bugünün nabzı okunuyor",
                    loadingLayout: .scored,
                    retry: { await viewModel.refresh() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Zorlanma")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.refresh() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumTeal, intensity: 0.3)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: StrainViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            ringSection(content)
            guidanceSection(content)
            if let stress = content.stress {
                stressSection(stress)
            }
            zoneSection(content)
            detailSection(content)
            historySection(content)
            disclaimerFooter
        }
        .padding(.top, ZenithiumSpacing.s)
    }

    @ViewBuilder
    private func historySection(_ content: StrainViewModel.Content) -> some View {
        if !content.history.isEmpty {
            let recent = Array(content.history.sorted(by: { $0.dayStart > $1.dayStart }).prefix(7))
            SectionCard(title: "Son Günlerin Antrenman ve Yük Seyri", subtitle: "Önceki günlerin zorlanma ve antrenman yükü dökümü") {
                VStack(spacing: ZenithiumSpacing.m) {
                    ForEach(recent, id: \.dayStart) { (record: BiometricDaySnapshot) in
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.dayStart, format: .dateTime.day().month(.abbreviated).weekday(.short))
                                    .font(ZenithiumFont.body)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                Text("TRIMP Yükü: \(ZenithiumFormat.metric(record.trimp, digits: 0))")
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                            Spacer()
                            Text(ZenithiumFormat.strain(record.dayStrain))
                                .font(ZenithiumFont.metricValue)
                                .foregroundStyle(ZenithiumColor.accent)
                        }
                        if record.dayStart != recent.last?.dayStart {
                            Divider().overlay(ZenithiumColor.hairlineSoft)
                        }
                    }
                }
            }
        }
    }

    /// Faz 13 — where the day's load came from.
    ///
    /// This card is what makes "8.2" mean something to someone who did not train. It is also
    /// useful to someone who did: a stressful Tuesday and an easy run score alike, and only
    /// the split tells them apart.
    private func stressSection(_ stress: StressDay) -> some View {
        SectionCard(title: "Fizyolojik Yük Dağılımı") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text(stress.summary)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let share = stress.trainingShare {
                    GeometryReader { proxy in
                        HStack(spacing: ZenithiumSpacing.xxs) {
                            Capsule()
                                .fill(ZenithiumColor.accent)
                                .frame(width: max(2, proxy.size.width * CGFloat(share)))
                            Capsule()
                                .fill(ZenithiumColor.spectrumIndigo.opacity(0.7))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)

                    HStack(spacing: ZenithiumSpacing.m) {
                        MetricTile(
                            label: "Antrenman",
                            value: ZenithiumFormat.metric(stress.trainingLoad, digits: 1),
                            caption: "TRIMP",
                            accessibilityLabelText: "Antrenmandan gelen yük"
                        )
                        MetricTile(
                            label: "Gün İçi Yaşam Yükü",
                            value: ZenithiumFormat.metric(stress.nonTrainingLoad, digits: 1),
                            caption: "TRIMP",
                            accessibilityLabelText: "Antrenman dışından gelen yaşam yükü"
                        )
                    }
                }

                if let summary = StressEngine.recoverySummary(for: stress, calendar: .autoupdatingCurrent) {
                    Text(summary)
                        .font(ZenithiumFont.footnote)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ringSection(_ content: StrainViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.m) {
            StrainArc(strain: content.strain.strain, ceiling: content.ceiling)
                .padding(.top, ZenithiumSpacing.s)

            if content.strain.hasExceededCeiling {
                // Past the target is not a failure and must not read like one (§12).
                Label("Günlük Hedef Kapasiteye Ulaşıldı", systemImage: "flag.checkered")
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.yellow)
                    .accessibilityLabel("Bugünün hedef zorlanması geçildi")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func guidanceSection(_ content: StrainViewModel.Content) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text(content.guidance)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if content.strain.wasClampedToPreviousValue {
                    // ASSUMPTION STRAIN-1 — say when the shown value is held rather than
                    // letting a recompute look like a stall.
                    Text("Bugün gösterilen en yüksek değerde tutuluyor — zorlanma gün içinde yalnızca artar.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if content.strain.uncoveredSeconds > 0 {
                    Text("Bugünün \(ZenithiumFormat.duration(seconds: content.strain.uncoveredSeconds)) kadarında nabız verisi yoktu; o süre zorlanmaya sayılmadı.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func zoneSection(_ content: StrainViewModel.Content) -> some View {
        SectionCard(
            title: "Bölgeler",
            subtitle: "Kalp atış rezervindeki pay"
        ) {
            ZoneBarsView(bars: content.zoneBars)
        }
    }

    private func detailSection(_ content: StrainViewModel.Content) -> some View {
        SectionCard(title: "Bu nasıl ölçüldü") {
            MetricTileGrid {
                MetricTile(
                    label: "TRIMP",
                    value: ZenithiumFormat.metric(content.strain.trimp, digits: 0),
                    caption: "Antrenman impulsu",
                    accessibilityLabelText: "Antrenman impulsu",
                    accessibilityValueText: ZenithiumFormat.metric(content.strain.trimp, digits: 0)
                )
                MetricTile(
                    label: "Kullanılan maks. nabız",
                    value: ZenithiumFormat.metric(content.strain.maxHeartRateUsed, digits: 0),
                    unit: "bpm",
                    caption: content.strain.maxHeartRateSource.displayName,
                    accessibilityLabelText: "Kullanılan maksimum kalp atış hızı",
                    accessibilityValueText: "\(ZenithiumFormat.metric(content.strain.maxHeartRateUsed, digits: 0)) atım bölü dakika, \(content.strain.maxHeartRateSource.displayName)"
                )
                if let ceiling = content.ceiling {
                    MetricTile(
                        label: "Hedef",
                        value: ZenithiumFormat.strain(ceiling),
                        caption: "Bugünün toparlanmasından",
                        tint: ZenithiumColor.accent,
                        accessibilityLabelText: "Hedef zorlanma",
                        accessibilityValueText: "21 üzerinden \(ZenithiumFormat.strain(ceiling))"
                    )
                }
                MetricTile(
                    label: "Örnek",
                    value: "\(content.strain.contributingSampleCount)",
                    caption: "Sayılan nabız ölçümü",
                    accessibilityLabelText: "Sayılan nabız ölçümü",
                    accessibilityValueText: "\(content.strain.contributingSampleCount)"
                )
            }

            if content.strain.maxHeartRateSource.invitesCorrection {
                // ASSUMPTION HRMAX-1 — the assumed age is visible and correctable rather
                // than a silent default.
                Text("\(EngineConstants.Strain.assumedAgeYears) yaşında olduğunu varsayıyorum. Daha isabetli bir tahmin için Ayarlar'a doğum tarihini ekle.")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disclaimerFooter: some View {
        Text(SafetyCopy.disclaimerFooter)
            .font(ZenithiumFont.caption)
            .foregroundStyle(ZenithiumColor.textTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, ZenithiumSpacing.xs)
    }
}
