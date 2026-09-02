//
//  HybridView.swift
//  Zenithium
//
//  Hibrit mercek ana ekranı — Hyrox seansları, kompanse koşu, istasyon profili.
//

import SwiftUI
import Charts

struct HybridView: View {

    @State var viewModel: HybridViewModel
    @State private var isLogging = false
    @ScaledMetric(relativeTo: .body) private var chartHeight150: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var chartHeight140: CGFloat = 140

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Seanslar yükleniyor",
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
            .navigationTitle("Hibrit")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isLogging = true } label: {
                        Label("Seans ekle", systemImage: "plus")
                    }
                    .accessibilityLabel("Hibrit seans ekle")
                }
            }
            .sheet(isPresented: $isLogging) {
                HybridSessionLoggerView(viewModel: viewModel)
            }
        }
        .zenithiumBackground(for: .hybrid)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: HybridViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if let analysis = content.latestAnalysis, let session = content.latestSession {
                compromisedSection(analysis, session: session)
                if let guidance = content.guidance {
                    guidanceSection(guidance)
                }
                roxzoneSection(analysis)
                stationSection(analysis)
                runSection(analysis)
            }
            if content.penaltyTrend.count >= 2 {
                trendSection(content.penaltyTrend)
            }
            historySection(content)
        }
    }

    // MARK: - Kompanse koşu

    private func compromisedSection(
        _ analysis: HybridSessionOutput,
        session: HybridSessionSnapshot
    ) -> some View {
        VStack(spacing: ZenithiumSpacing.m) {
            if let compromised = analysis.compromisedRunning {
                // Yay doğrudan `ArcGauge` — `ScoreArc` kendi sayısını çizer ve buradaki
                // okuma bir puan değil, bir ceza yüzdesi. Üstüne ikinci bir sayı bindirmek
                // yerine merkez içeriği burada tanımlanıyor.
                ArcGauge(
                    // Ceza ne kadar küçükse yay o kadar dolu. %20 ceza yayı boşaltır.
                    progress: MathSupport.clamp(1 - compromised.penalty * 5, 0, 1),
                    gradient: ZenithiumColor.arcGradient(for: penaltyBand(compromised.penalty)),
                    trackColor: ZenithiumColor.trackColor(for: penaltyBand(compromised.penalty)),
                    apexColor: ZenithiumColor.color(for: penaltyBand(compromised.penalty)),
                    accessibilityLabel: "Yorgun koşu cezası",
                    accessibilityValue: "referans tempodan \(ZenithiumFormat.percent(compromised.penalty)) yavaş"
                ) {
                    VStack(spacing: ZenithiumSpacing.none) {
                        Text("−\(ZenithiumFormat.percent(compromised.penalty))")
                            .font(ZenithiumFont.arcValue(size: 52))
                            .foregroundStyle(ZenithiumColor.textPrimary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("kompanse koşu")
                            .font(ZenithiumFont.unit)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }

                BandChip(
                    band: penaltyBand(compromised.penalty),
                    detail: penaltyLabel(compromised.penalty)
                )

                HStack(spacing: ZenithiumSpacing.l) {
                    paceLabel("taze", compromised.referencePaceSecondsPerKilometre)
                    paceLabel("istasyon sonrası", compromised.compromisedPaceSecondsPerKilometre)
                }

                if compromised.referenceWasDerivedFromFirstRound {
                    Text("Referans ilk turun temposu — o tur da tamamen taze değil, yani gerçek ceza bundan biraz büyük.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("\(session.kind.displayName) · \(session.performedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func paceLabel(_ title: String, _ pace: Double) -> some View {
        VStack(spacing: ZenithiumSpacing.xxs) {
            Text(title)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
            Text(ZenithiumFormat.pace(secondsPerKilometre: pace))
                .font(ZenithiumFont.dataValue)
                .foregroundStyle(ZenithiumColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Ceza bandı — Hyrox literatüründe elit %3–5, iyi amatör %8–12 civarında seyreder.
    private func penaltyBand(_ penalty: Double) -> RecoveryBand {
        if penalty <= 0.06 { return .green }
        if penalty <= 0.12 { return .yellow }
        return .red
    }

    private func penaltyLabel(_ penalty: Double) -> String {
        if penalty <= 0.06 { return "güçlü" }
        if penalty <= 0.12 { return "geliştirilebilir" }
        return "zayıf halka"
    }

    private func guidanceSection(_ guidance: String) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                Image(systemName: "target")
                    .foregroundStyle(ZenithiumColor.accent)
                    .accessibilityHidden(true)
                Text(guidance)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Roxzone

    private func roxzoneSection(_ analysis: HybridSessionOutput) -> some View {
        SectionCard(
            title: "Roxzone",
            subtitle: "Kondisyondan bağımsız kazanılabilecek en hızlı süre"
        ) {
            MetricTileGrid {
                MetricTile(
                    label: "Toplam geçiş",
                    value: ZenithiumFormat.clock(seconds: analysis.roxzoneSeconds),
                    caption: "\(ZenithiumFormat.percent(analysis.roxzoneShare)) toplam süre",
                    tint: analysis.roxzoneShare > 0.08 ? ZenithiumColor.yellow : ZenithiumColor.textPrimary,
                    accessibilityLabelText: "Toplam geçiş süresi",
                    accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: analysis.roxzoneSeconds)
                )
                MetricTile(
                    label: "Koşu",
                    value: ZenithiumFormat.clock(seconds: analysis.totalRunSeconds),
                    accessibilityLabelText: "Toplam koşu süresi",
                    accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: analysis.totalRunSeconds)
                )
                MetricTile(
                    label: "İstasyon",
                    value: ZenithiumFormat.clock(seconds: analysis.totalStationSeconds),
                    accessibilityLabelText: "Toplam istasyon süresi",
                    accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: analysis.totalStationSeconds)
                )
                MetricTile(
                    label: "Toplam",
                    value: ZenithiumFormat.clock(seconds: analysis.totalDurationSeconds),
                    accessibilityLabelText: "Toplam seans süresi",
                    accessibilityValueText: ZenithiumFormat.spokenDuration(seconds: analysis.totalDurationSeconds)
                )
            }
        }
    }

    // MARK: - İstasyonlar

    private func stationSection(_ analysis: HybridSessionOutput) -> some View {
        SectionCard(
            title: "İstasyonlar",
            subtitle: "Beklenen paya göre sapma"
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(analysis.stationSplits) { split in
                    StationRow(
                        split: split,
                        isWeakest: split.station == analysis.weakestStation
                    )
                    if split.station != analysis.stationSplits.last?.station {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }

            if let ratio = analysis.muscularToCardiovascularRatio {
                Divider().overlay(ZenithiumColor.hairline).padding(.vertical, ZenithiumSpacing.xs)
                HStack {
                    Text("Kas : kardiyo")
                        .font(ZenithiumFont.label)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    Spacer(minLength: 8)
                    Text(ZenithiumFormat.metric(ratio, digits: 2))
                        .font(ZenithiumFont.dataValue)
                        .foregroundStyle(ratio > 1.35 ? ZenithiumColor.yellow : ZenithiumColor.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kassal ve kardiyovasküler süre oranı")
                .accessibilityValue(ZenithiumFormat.metric(ratio, digits: 2))
            }
        }
    }

    // MARK: - Koşu turları

    private func runSection(_ analysis: HybridSessionOutput) -> some View {
        SectionCard(
            title: "Koşu turları",
            subtitle: "Tur başına bozulma: \(ZenithiumFormat.metric(analysis.compromisedRunning?.degradationPerRound ?? 0, digits: 1)) sn/km"
        ) {
            Chart(analysis.runSplits) { split in
                BarMark(
                    x: .value("Tur", split.roundIndex),
                    y: .value("Tempo", split.paceSecondsPerKilometre)
                )
                .foregroundStyle(ZenithiumColor.accent.opacity(0.85))
                .cornerRadius(3)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: analysis.runSplits.map(\.roundIndex)) { value in
                    AxisValueLabel {
                        if let round = value.as(Int.self) {
                            Text("\(round)")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairline)
                    AxisValueLabel {
                        if let pace = value.as(Double.self) {
                            Text(ZenithiumFormat.clock(seconds: pace))
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }
                }
            }
            // Saf çizim (Swift Charts): @ScaledMetric ile minHeight kullanılır.
            .frame(minHeight: chartHeight150)
            .accessibilityElement()
            .accessibilityLabel("Tur tur koşu bölümleri")
            .accessibilityValue(runAccessibilityValue(analysis))
        }
    }

    private func runAccessibilityValue(_ analysis: HybridSessionOutput) -> String {
        analysis.runSplits
            .map { "Tur \($0.roundIndex): \(ZenithiumFormat.pace(secondsPerKilometre: $0.paceSecondsPerKilometre))" }
            .joined(separator: ", ")
    }

    // MARK: - Seyir

    private func trendSection(_ points: [HybridViewModel.PenaltyPoint]) -> some View {
        SectionCard(
            title: "Kompanse koşu seyri",
            subtitle: "Aşağı inmesi iyi"
        ) {
            Chart(points) { point in
                LineMark(
                    x: .value("Tarih", point.date),
                    y: .value("Ceza", point.penalty * 100)
                )
                .foregroundStyle(ZenithiumColor.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Tarih", point.date),
                    y: .value("Ceza", point.penalty * 100)
                )
                .foregroundStyle(ZenithiumColor.accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairline)
                    AxisValueLabel()
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }
            // Saf çizim (Swift Charts): @ScaledMetric ile minHeight kullanılır.
            .frame(minHeight: chartHeight140)
            .accessibilityElement()
            .accessibilityLabel("Zamanla yorgun koşu cezası")
            .accessibilityValue(
                points.map { "\(ZenithiumFormat.percent($0.penalty))" }.joined(separator: ", ")
            )
        }
    }

    private func historySection(_ content: HybridViewModel.Content) -> some View {
        SectionCard(title: "Seanslar") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(content.sessions) { session in
                    HStack(spacing: ZenithiumSpacing.m) {
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(session.kind.displayName)
                                .font(ZenithiumFont.label)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text(session.performedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                            Text(ZenithiumFormat.clock(seconds: session.totalDurationSeconds))
                                .font(ZenithiumFont.dataValue)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            if let penalty = session.compromisedPenalty {
                                Text("−\(ZenithiumFormat.percent(penalty))")
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.delete(id: session.id) }
                        } label: {
                            Image(systemName: "trash").imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ZenithiumColor.red)
                        .accessibilityLabel("Seansı sil")
                    }
                    .padding(.vertical, ZenithiumSpacing.m)
                    .accessibilityElement(children: .contain)

                    if session.id != content.sessions.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }
}

/// Tek istasyon satırı — süre, pay, sapma.
private struct StationRow: View {

    let split: StationSplit
    let isWeakest: Bool

    private var deviationTint: Color {
        if split.deviationFromReference > 0.02 { return ZenithiumColor.yellow }
        if split.deviationFromReference < -0.02 { return ZenithiumColor.green }
        return ZenithiumColor.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(spacing: ZenithiumSpacing.s) {
                Image(systemName: split.station.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(isWeakest ? ZenithiumColor.yellow : ZenithiumColor.textSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                    Text(split.station.displayName)
                        .font(ZenithiumFont.label)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Text(split.station.specification)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                    Text(ZenithiumFormat.clock(seconds: split.durationSeconds))
                        .font(ZenithiumFont.dataValue)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Text(ZenithiumFormat.signed(split.deviationFromReference * 100, digits: 1) + " pp")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(deviationTint)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairline)
                    Capsule()
                        .fill(isWeakest ? ZenithiumColor.yellow : ZenithiumColor.accent)
                        .frame(width: proxy.size.width * MathSupport.clamp(split.shareOfStationTime * 4, 0, 1))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, ZenithiumSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.station.displayName)
        .accessibilityValue(
            "\(ZenithiumFormat.spokenDuration(seconds: split.durationSeconds)), "
            + "referanstan \(ZenithiumFormat.signed(split.deviationFromReference * 100, digits: 1)) puan sapma"
            + (isWeakest ? ", en zayıf istasyon" : "")
        )
    }
}
