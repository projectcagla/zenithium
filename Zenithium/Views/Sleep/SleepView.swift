//
//  SleepView.swift
//  Zenithium
//
//  The Sleep screen. Spec §5.2, §10.
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
                .padding(.horizontal, ZenithiumSpacing.l)
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
        VStack(spacing: ZenithiumSpacing.l) {
            headline(content)
            needSection(content)
            componentSection(content)
            stageSection(content)
            timingSection(content)
        }
        .padding(.top, ZenithiumSpacing.s)
    }

    private func headline(_ content: SleepViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.s) {
            ScoreArc(
                score: content.score,
                gradient: ZenithiumColor.sleepGradient,
                tint: ZenithiumColor.spectrumMagenta,
                caption: ZenithiumFormat.duration(seconds: content.record.sleepDurationSeconds),
                accessibilityLabel: "Uyku puanı",
                accessibilityValue: "100 üzerinden \(ZenithiumFormat.score(content.score)), \(ZenithiumFormat.spokenDuration(seconds: content.record.sleepDurationSeconds)) uykuda"
            )
            .padding(.top, ZenithiumSpacing.s)
        }
        .frame(maxWidth: .infinity)
    }

    private func needSection(_ content: SleepViewModel.Content) -> some View {
        SectionCard(title: "İhtiyaç ve gerçekleşen") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                MetricTileGrid {
                    MetricTile(
                        label: "Hedef İhtiyaç",
                        value: ZenithiumFormat.metric(content.sleep.needHours, digits: 1),
                        unit: "sa",
                        caption: needCaption(content),
                        accessibilityLabelText: "Gereken uyku süresi",
                        accessibilityValueText: "\(ZenithiumFormat.metric(content.sleep.needHours, digits: 1)) saat"
                    )
                    MetricTile(
                        label: "Toplam Uyku",
                        value: ZenithiumFormat.metric(content.sleep.asleepHours, digits: 1),
                        unit: "sa",
                        tint: content.shortfallHours > 0.5 ? ZenithiumColor.yellow : ZenithiumColor.green,
                        accessibilityLabelText: "Uykuda geçen süre",
                        accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: content.record.sleepDurationSeconds)
                    )
                }

                if content.shortfallHours > 0.1 {
                    Text("Hedeflenen süreden \(ZenithiumFormat.metric(content.shortfallHours, digits: 1)) saat eksik uyundu. Açık kalan süre uyku borcu modeliyle sonraki günlerin ihtiyacına aktarılır.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// §5.2 — the need is built from four terms, so the tile says which ones moved it.
    private func needCaption(_ content: SleepViewModel.Content) -> String {
        var parts: [String] = ["\(ZenithiumFormat.metric(content.profile.baselineSleepNeedHours, digits: 1))h baseline"]
        if content.sleep.appliedDebtHours > 0.05 {
            parts.append("+\(ZenithiumFormat.metric(content.sleep.appliedDebtHours, digits: 1))h debt")
        }
        if content.sleep.appliedNapCreditHours > 0.05 {
            parts.append("−\(ZenithiumFormat.metric(content.sleep.appliedNapCreditHours, digits: 1))h naps")
        }
        return parts.joined(separator: ", ")
    }

    private func componentSection(_ content: SleepViewModel.Content) -> some View {
        SectionCard(
            title: "Puanı ne oluşturdu",
            subtitle: "Her bileşen ve taşıdığı ağırlık"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                ForEach(content.sleep.components, id: \.component) { component in
                    SleepComponentRow(component: component)
                }

                if content.sleep.weightsWereRenormalized {
                    Divider().overlay(ZenithiumColor.hairline)
                    Text(droppedMessage(content))
                        .font(ZenithiumFont.caption)
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

    private func stageSection(_ content: SleepViewModel.Content) -> some View {
        SectionCard(title: "Evreler") {
            SleepStageBarView(stages: content.stages)
        }
    }

    private func timingSection(_ content: SleepViewModel.Content) -> some View {
        SectionCard(title: "Zamanlama") {
            MetricTileGrid {
                if let start = content.record.sleepStart {
                    MetricTile(
                        label: "Uyudun",
                        value: start.formatted(date: .omitted, time: .shortened),
                        accessibilityLabelText: "Uykuya dalış saati",
                        accessibilityValueText: start.formatted(date: .omitted, time: .shortened)
                    )
                }
                if let wake = content.record.wakeTime {
                    MetricTile(
                        label: "Uyandın",
                        value: wake.formatted(date: .omitted, time: .shortened),
                        accessibilityLabelText: "Uyanma saati",
                        accessibilityValueText: wake.formatted(date: .omitted, time: .shortened)
                    )
                }
                if let efficiency = content.record.sleepEfficiency {
                    MetricTile(
                        label: "Verimlilik",
                        value: ZenithiumFormat.percent(efficiency),
                        caption: "uyku ÷ yatakta geçen süre",
                        accessibilityLabelText: "Uyku verimliliği",
                        accessibilityValueText: ZenithiumFormat.percent(efficiency)
                    )
                }
                if content.record.napSeconds > 0 {
                    MetricTile(
                        label: "Şekerlemeler",
                        value: ZenithiumFormat.duration(seconds: content.record.napSeconds),
                        caption: "yarına sayılıyor",
                        accessibilityLabelText: "Şekerleme süresi",
                        accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: content.record.napSeconds)
                    )
                }
            }
        }
    }
}

/// One weighted component of the sleep score (§5.2).
private struct SleepComponentRow: View {

    let component: SleepComponentScore

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                Text(component.component.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Spacer(minLength: 8)
                Text(ZenithiumFormat.score(component.score))
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text("×\(ZenithiumFormat.metric(component.weight, digits: 2))")
                    .font(ZenithiumFont.caption.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairline)
                    Capsule()
                        .fill(ZenithiumColor.accent)
                        .frame(width: proxy.size.width * MathSupport.clamp(component.score / 100, 0, 1))
                }
            }
            .frame(height: 6)

            Text(component.component.explanation)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.component.displayName)
        .accessibilityValue(
            "100 üzerinden \(ZenithiumFormat.score(component.score)), ağırlık \(ZenithiumFormat.metric(component.weight, digits: 2)). \(component.component.explanation)"
        )
    }
}
