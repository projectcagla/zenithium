//
//  SleepView.swift
//  Zenithium
//
//  The Sleep screen. Spec §5.2, §10.
//  Redesigned to strict Design Specification:
//  - Tier 1 Hero: Hypnogram (full width, borderless/cardless, quiet time axis, deep sleep emphasized)
//  - Tier 2: Stages (single stacked bar — not 4 cards) and Timing (in bed / asleep / awake — quiet row)
//  - Single L2 Card: Sleep debt and tonight's sleep target
//  - Secondary sections: L1 SectionBlock
//

import SwiftUI

struct SleepView: View {

    @State var viewModel: SleepViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Dün gece okunuyor",
                    loadingLayout: .scored,
                    retry: { await viewModel.refresh() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.screenEdge)
                .padding(.bottom, ZenithiumSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Uyku")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.refresh() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumMagenta, intensity: 0.3)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: SleepViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Uyku Skoru & Tam Genişlik Hipnogram
            hypnogramHero(content)

            // 2. KADEME: Evreler (Tek Yığılmış Çubuk) ve Zamanlama (Sessiz Satır)
            stagesAndTimingLayer(content)

            // TEK L2 KART: Uyku Borcu ve Bu Gecenin Hedefi
            debtAndNeedCard(content)

            // KATMAN 3: Puanı Ne Oluşturdu (L1 SectionBlock)
            componentSection(content)

            // KATMAN 4: Son Günlerin Uyku Seyri (L1 SectionBlock)
            historySection(content)
        }
        .padding(.top, ZenithiumSpacing.s)
    }

    // MARK: - 1. KADEME (KAHRAMAN) — Hipnogram & Uyku Skoru

    private func hypnogramHero(_ content: SleepViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.m) {
            // Uyku Yayı / Skoru
            ScoreArc(
                score: content.score,
                gradient: ZenithiumColor.sleepGradient,
                tint: ZenithiumColor.spectrumMagenta,
                caption: ZenithiumFormat.duration(seconds: content.record.sleepDurationSeconds),
                accessibilityLabel: "Uyku puanı",
                accessibilityValue: "100 üzerinden \(ZenithiumFormat.score(content.score)), \(ZenithiumFormat.spokenDuration(seconds: content.record.sleepDurationSeconds)) uykuda"
            )
            .padding(.top, ZenithiumSpacing.xs)

            // Altında TEK bir sakin cümle
            Text(rationaleSentence(content))
                .zenithiumBody()
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ZenithiumSpacing.s)

            // Tam Genişlik Kartsız Hipnogram
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                Text("GECELİK HİPNOGRAM")
                    .zenithiumEyebrow()

                HypnogramView(record: content.record)
            }
            .padding(.top, ZenithiumSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func rationaleSentence(_ content: SleepViewModel.Content) -> String {
        let duration = ZenithiumFormat.duration(seconds: content.record.sleepDurationSeconds)
        let deep = ZenithiumFormat.duration(seconds: content.record.deepSeconds)
        if content.shortfallHours < 0.2 {
            return "\(duration) kesintisiz uyku; \(deep) derin uyku ile toparlanma tamamlandı."
        } else {
            return "\(duration) uyundu. Hedefin \(ZenithiumFormat.metric(content.shortfallHours, digits: 1)) saat altında kalındığı için toparlanma sınırlı."
        }
    }

    // MARK: - 2. KADEME — Evreler ve Zamanlama (L1 Sessiz Şeritler)

    private func stagesAndTimingLayer(_ content: SleepViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            // 1. Evreler: Tek bir yığılmış çubuk
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text("EVRELER")
                    .zenithiumEyebrow()

                SleepStageBarView(stages: content.stages)
            }

            // 2. Zamanlama: Sessiz bir satır (yattı / uyudu / uyandı / verimlilik)
            timingStrip(content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timingStrip(_ content: SleepViewModel.Content) -> some View {
        HStack(spacing: ZenithiumSpacing.none) {
            if let start = content.record.sleepStart {
                timingItem(
                    label: "Uyudun",
                    value: start.formatted(date: .omitted, time: .shortened)
                )
            }
            Spacer()
            if let wake = content.record.wakeTime {
                timingItem(
                    label: "Uyandın",
                    value: wake.formatted(date: .omitted, time: .shortened)
                )
            }
            Spacer()
            if let efficiency = content.record.sleepEfficiency {
                timingItem(
                    label: "Verimlilik",
                    value: ZenithiumFormat.percent(efficiency)
                )
            }
            if content.record.napSeconds > 0 {
                Spacer()
                timingItem(
                    label: "Şekerleme",
                    value: ZenithiumFormat.duration(seconds: content.record.napSeconds)
                )
            }
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .overlay(alignment: .top) { Divider().overlay(ZenithiumColor.hairlineSoft) }
        .overlay(alignment: .bottom) { Divider().overlay(ZenithiumColor.hairlineSoft) }
    }

    private func timingItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
            Text(label)
                .zenithiumCaption()
            Text(value)
                .sectionTitle()
                .monospacedDigit()
        }
    }

    // MARK: - TEK L2 KART — Uyku Borcu ve Bu Gecenin Hedefi

    private func debtAndNeedCard(_ content: SleepViewModel.Content) -> some View {
        SectionCard(
            title: "Bu Gecenin Uyku Hedefi",
            subtitle: needCaption(content)
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text("Gereken Uyku")
                            .zenithiumCaption()
                        HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                            Text(ZenithiumFormat.metric(content.sleep.needHours, digits: 1))
                                .metricNumeral()
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text("sa")
                                .metricUnit()
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                        Text("Dün Gece")
                            .zenithiumCaption()
                        HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                            Text(ZenithiumFormat.metric(content.sleep.asleepHours, digits: 1))
                                .metricNumeral()
                                .foregroundStyle(content.shortfallHours > 0.5 ? ZenithiumColor.yellow : ZenithiumColor.green)
                            Text("sa")
                                .metricUnit()
                        }
                    }
                }

                if content.shortfallHours > 0.1 {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    HStack(alignment: .top, spacing: ZenithiumSpacing.xs) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundStyle(ZenithiumColor.yellow)
                        Text("Dün geceden \(ZenithiumFormat.metric(content.shortfallHours, digits: 1)) saatlik uyku açığı var. Bu gecenin hedefi borcu kademeli dengeleyecek şekilde güncellendi.")
                            .zenithiumCaption()
                            .foregroundStyle(ZenithiumColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func needCaption(_ content: SleepViewModel.Content) -> String {
        var parts: [String] = ["\(ZenithiumFormat.metric(content.profile.baselineSleepNeedHours, digits: 1)) sa taban"]
        if content.sleep.appliedDebtHours > 0.05 {
            parts.append("+\(ZenithiumFormat.metric(content.sleep.appliedDebtHours, digits: 1)) sa borç")
        }
        if content.sleep.appliedNapCreditHours > 0.05 {
            parts.append("−\(ZenithiumFormat.metric(content.sleep.appliedNapCreditHours, digits: 1)) sa şekerleme")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - KATMAN 3 — Puanı Ne Oluşturdu (L1 SectionBlock)

    private func componentSection(_ content: SleepViewModel.Content) -> some View {
        SectionBlock(
            title: "Puanı Ne Oluşturdu?",
            subtitle: "Her bileşenin skora katkısı ve ağırlığı",
            showTopDivider: true
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                ForEach(content.sleep.components, id: \.component) { component in
                    SleepComponentRow(component: component)
                }

                if content.sleep.weightsWereRenormalized {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    Text(droppedMessage(content))
                        .zenithiumCaption()
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func droppedMessage(_ content: SleepViewModel.Content) -> String {
        let names = content.sleep.droppedComponents.map(\.displayName).joined(separator: ", ")
        return "\(names) dün gece ölçülemedi; kalan parçalar yine %100 edecek şekilde yeniden ağırlıklandırıldı."
    }

    // MARK: - KATMAN 4 — Son Günlerin Uyku Seyri (L1 SectionBlock)

    @ViewBuilder
    private func historySection(_ content: SleepViewModel.Content) -> some View {
        if !content.history.isEmpty {
            let recent = Array(content.history.sorted(by: { $0.dayStart > $1.dayStart }).prefix(7))
            SectionBlock(
                title: "Son Günlerin Uyku Seyri",
                subtitle: "Önceki gecelerin skor ve süre dökümü",
                showTopDivider: true
            ) {
                VStack(spacing: ZenithiumSpacing.s) {
                    ForEach(recent, id: \.dayStart) { (record: BiometricDaySnapshot) in
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.dayStart, format: .dateTime.day().month(.abbreviated).weekday(.short))
                                    .sectionTitle()
                                Text("\(ZenithiumFormat.duration(seconds: record.sleepDurationSeconds)) uykuda")
                                    .zenithiumCaption()
                            }
                            Spacer()
                            if let score = record.sleepScore {
                                Text(ZenithiumFormat.score(score))
                                    .metricNumeral()
                                    .foregroundStyle(score >= 70 ? ZenithiumColor.green : (score >= 50 ? ZenithiumColor.yellow : ZenithiumColor.red))
                            } else {
                                Text("—")
                                    .metricNumeral()
                                    .foregroundStyle(ZenithiumColor.textTertiary)
                            }
                        }
                        if record.dayStart != recent.last?.dayStart {
                            Divider().overlay(ZenithiumColor.hairlineSoft)
                        }
                    }
                }
            }
        }
    }
}

/// One weighted component of the sleep score (§5.2).
private struct SleepComponentRow: View {

    let component: SleepComponentScore

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                Text(component.component.displayName)
                    .zenithiumLabel()
                Spacer(minLength: 8)
                Text(ZenithiumFormat.score(component.score))
                    .font(ZenithiumFont.metricNumeral)
                Text("×\(ZenithiumFormat.metric(component.weight, digits: 2))")
                    .zenithiumCaption()
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairline)
                    Capsule()
                        .fill(ZenithiumColor.accent)
                        .frame(width: proxy.size.width * MathSupport.clamp(component.score / 100, 0, 1))
                }
            }
            .frame(height: 5)

            Text(component.component.explanation)
                .zenithiumCaption()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.component.displayName)
        .accessibilityValue(
            "100 üzerinden \(ZenithiumFormat.score(component.score)), ağırlık \(ZenithiumFormat.metric(component.weight, digits: 2)). \(component.component.explanation)"
        )
    }
}
