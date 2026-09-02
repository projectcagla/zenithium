//
//  StrengthView.swift
//  Zenithium
//
//  The strength screen. Faz 17.
//
//  Volume first, because it is the number that changes what the next session looks like;
//  then balance, then the bar itself. A one-rep-max chart is what people want to look at and
//  the least useful thing to act on, so it sits last.
//

import SwiftUI

struct StrengthView: View {

    @State var viewModel: StrengthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Kuvvet seansları okunuyor",
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
            .navigationTitle("Kuvvet")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.load() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.32)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: StrengthViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if let deload = content.deload.summary {
                deloadCard(deload)
            }
            volumeCard(content)
            balanceCard(content.balance)
            if !content.oneRepMaxes.isEmpty {
                oneRepMaxCard(content.oneRepMaxes)
            }
        }
    }

    private func deloadCard(_ summary: String) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(ZenithiumColor.yellow)
                    .accessibilityHidden(true)
                Text(summary)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Volume

    private func volumeCard(_ content: StrengthViewModel.Content) -> some View {
        SectionCard(
            title: "Haftalık hacim",
            subtitle: "Kas grubu başına etkili set — \(content.sessionsThisWeek) seans"
        ) {
            if content.weeklyVolume.isEmpty {
                Text("Bu hafta kaydedilmiş kuvvet seansı yok.")
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            } else {
                VStack(spacing: ZenithiumSpacing.s) {
                    ForEach(content.weeklyVolume) { volume in
                        VolumeRow(volume: volume, maximum: content.weeklyVolume.first?.sets ?? 1)
                    }
                }
            }
        }
    }

    // MARK: - Balance

    private func balanceCard(_ balance: StrengthBalance) -> some View {
        SectionCard(title: "Denge") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(spacing: ZenithiumSpacing.m) {
                    MetricTile(
                        label: "İtme",
                        value: ZenithiumFormat.metric(balance.pushSets, digits: 0),
                        caption: "set",
                        accessibilityLabelText: "İtme setleri"
                    )
                    MetricTile(
                        label: "Çekme",
                        value: ZenithiumFormat.metric(balance.pullSets, digits: 0),
                        caption: "set",
                        accessibilityLabelText: "Çekme setleri"
                    )
                    if let chain = balance.chainRatio {
                        MetricTile(
                            label: "Ön/arka",
                            value: ZenithiumFormat.metric(chain, digits: 2),
                            caption: "zincir oranı",
                            accessibilityLabelText: "Ön arka zincir oranı"
                        )
                    }
                }
                if let summary = balance.summary {
                    Text(summary)
                        .font(ZenithiumFont.footnote)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - One-rep max

    private func oneRepMaxCard(_ estimates: [OneRepMaxEstimate]) -> some View {
        SectionCard(title: "Tahmini 1TM", subtitle: "Epley ve Brzycki ortalaması") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(estimates.prefix(8)) { estimate in
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(estimate.exerciseName)
                                .font(ZenithiumFont.headline)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                                // The exercise's name is the row's subject; the number beside
                                // it is short, so there is room to wrap. Yol haritası v4, B7.
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text("\(ZenithiumFormat.metric(estimate.estimate, digits: 1)) kg")
                                .font(ZenithiumFont.body.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            if let change = estimate.change, abs(change) >= 0.01 {
                                Text(ZenithiumFormat.percentTR(change))
                                    .font(ZenithiumFont.caption.monospacedDigit())
                                    .foregroundStyle(change > 0 ? ZenithiumColor.green : ZenithiumColor.textTertiary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        Text("\(ZenithiumFormat.metric(estimate.weight, digits: 1)) kg × \(estimate.reps)"
                             + (estimate.isReliable ? "" : " — formüller bu tekrar sayısında güvenilirliğini yitirir"))
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                    .padding(.vertical, ZenithiumSpacing.s)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(StrengthEngine.progressionSummary(for: estimate))

                    if estimate.id != estimates.prefix(8).last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }
}

/// One muscle group's weekly set count, as a bar against the busiest group.
private struct VolumeRow: View {

    let volume: WeeklyVolume
    let maximum: Double

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            HStack {
                Text(volume.muscle.displayName)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Spacer()
                Text("\(ZenithiumFormat.metric(volume.sets, digits: 1)) set")
                    .font(ZenithiumFont.caption.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Text(volume.band.displayName)
                    .font(ZenithiumFont.caption2)
                    .padding(.horizontal, ZenithiumSpacing.s)
                    .padding(.vertical, ZenithiumSpacing.xxs)
                    .background(Capsule().fill(tint.opacity(0.16)))
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                let fraction = maximum > 0 ? CGFloat(volume.sets / maximum) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairlineSoft)
                    Capsule()
                        .fill(tint.opacity(0.65))
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(volume.muscle.displayName)
        .accessibilityValue("\(ZenithiumFormat.metric(volume.sets, digits: 1)) set, \(volume.band.displayName). \(volume.band.explanation)")
    }

    private var tint: Color {
        switch volume.band {
        case .minimal: return ZenithiumColor.textTertiary
        case .maintenance: return ZenithiumColor.accent
        case .productive: return ZenithiumColor.green
        case .high: return ZenithiumColor.yellow
        }
    }
}
