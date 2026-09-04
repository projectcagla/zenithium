//
//  TodayView.swift
//  Zenithium
//
//  The Today screen — "how recovered am I". Spec §1, §10.
//  Redesigned to strict Design Specification:
//  - Exactly ONE Tier 1 hero (Recovery score Arc + 64pt heroNumeral + single rationale)
//  - Tier 2 supporting metrics strip (HRV, RHR, Sleep, Temp in quiet L1 strip)
//  - Exactly ONE L2 card in first fold (Daily recommendation / prescription)
//  - Circadian 5-row list moved to CircadianDetailView, thin 24h strip remains
//  - All secondary sections are L1 SectionBlock
//

import SwiftUI

struct TodayView: View {

    @State var viewModel: TodayViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Dün gece okunuyor",
                    loadingLayout: .scored,
                    retry: { await viewModel.refresh() },
                    requestAccess: { await viewModel.requestAuthorization() }
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.screenEdge)
                .padding(.bottom, ZenithiumSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Bugün")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.refresh() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.42)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: TodayViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Toparlanma Skoru + Tek Cümle Gerekçe
            recoveryHero(content)

            // 2. KADEME: Dört Destekleyici Ölçüm (KART DEĞİL, Tek Satırlık Sessiz Şerit)
            supportingMetricsStrip(content)

            // TEK L2 KART: Günün Önerisi (Güç rozeti + gerekçe + tavan + güven çubuğu)
            prescriptionCard(content)

            // SİRKADİYEN RİTİM: 24 Saatlik İnce Şerit (5 satırlık liste kaldırıldı, detay ekranına bağlı)
            if let circadian = content.circadian {
                circadianStripSection(circadian)
            }

            // DÜN GECE: Ham Biyometrik Ölçümler (L1 SectionBlock)
            overnightSection(content)

            // KANIT İZİ: Belirleyiciler & Deterministik Karar İzi (L1 SectionBlock)
            evidenceSection(content)

            // BİLİMSEL ÖNERİLER (L1 SectionBlock)
            if !viewModel.recommendations.isEmpty {
                recommendationsSection
            }

            disclaimerFooter
        }
        .padding(.top, ZenithiumSpacing.s)
        .animation(.snappy, value: viewModel.briefing)
        .animation(.snappy, value: viewModel.athleticDecision)
        .animation(.snappy, value: viewModel.prescription)
        .animation(.snappy, value: viewModel.recommendations)
    }

    // MARK: - 1. KADEME (KAHRAMAN) — Toparlanma Skoru

    private func recoveryHero(_ content: TodayViewModel.Content) -> some View {
        let confidence = viewModel.athleticDecision?.confidence.value ?? content.recovery.confidence
        let rationale = viewModel.athleticDecision?.value.primaryRationale ?? content.guidance

        return VStack(spacing: ZenithiumSpacing.m) {
            // Büyük Açık Yay (Hero Numeral 64pt)
            RecoveryArc(
                score: content.score,
                band: content.band,
                confidence: confidence
            )
            .padding(.top, ZenithiumSpacing.xs)

            // Band Sembolü + Band Adı (Renk körlüğü için sembol + metin)
            HStack(spacing: ZenithiumSpacing.xs) {
                Circle()
                    .fill(ZenithiumColor.color(for: content.band))
                    .frame(width: 8, height: 8)
                Text(content.band.displayName)
                    .sectionTitle()
                    .foregroundStyle(ZenithiumColor.color(for: content.band))
                Text("•")
                    .zenithiumCaption()
                Text("%\(Int(content.score.rounded()))")
                    .zenithiumCaption()
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            // Altında TEK bir cümle: neden bu skor
            Text(rationale)
                .zenithiumBody()
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ZenithiumSpacing.s)

            if confidence < 0.70 {
                HStack(alignment: .center, spacing: ZenithiumSpacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ZenithiumColor.yellow)
                    Text("Taban çizgisi kalibrasyonda (%\(Int(confidence * 100)) güven düzeyi).")
                        .zenithiumCaption()
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 2. KADEME — Dört Destekleyici Ölçüm Şeridi (L1 Sessiz Şerit)

    private func supportingMetricsStrip(_ content: TodayViewModel.Content) -> some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.none) {
            supportingMetricItem(
                label: "HRV",
                value: content.record.heartRateVariability.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "ms",
                arrow: hrvArrow(content)
            )
            Spacer()
            supportingMetricItem(
                label: "İstirahat",
                value: content.record.restingHeartRate.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "bpm",
                arrow: rhrArrow(content)
            )
            Spacer()
            supportingMetricItem(
                label: "Uyku",
                value: content.record.sleepScore.map { ZenithiumFormat.score($0) } ?? "—",
                unit: "%",
                arrow: sleepArrow(content)
            )
            Spacer()
            supportingMetricItem(
                label: "Sıcaklık",
                value: content.record.wristTemperatureDelta.map {
                    let converted = content.profile.unitPreference.temperatureDelta(fromCelsius: $0)
                    return ZenithiumFormat.signed(converted, digits: 1)
                } ?? "—",
                unit: content.profile.unitPreference.temperatureDeltaSymbol,
                arrow: tempArrow(content)
            )
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .overlay(alignment: .top) { Divider().overlay(ZenithiumColor.hairlineSoft) }
        .overlay(alignment: .bottom) { Divider().overlay(ZenithiumColor.hairlineSoft) }
    }

    private func supportingMetricItem(
        label: String,
        value: String,
        unit: String,
        arrow: (symbol: String, color: Color)?
    ) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
            Text(label)
                .zenithiumCaption()
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                Text(value)
                    .metricNumeral()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(unit)
                    .metricUnit()
                if let arrow {
                    Image(systemName: arrow.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(arrow.color)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func hrvArrow(_ content: TodayViewModel.Content) -> (symbol: String, color: Color)? {
        guard let driver = content.recovery.drivers.first(where: { $0.driver == .heartRateVariability }) else { return nil }
        return (driver.isPositive ? "arrow.up" : "arrow.down", driver.isPositive ? ZenithiumColor.green : ZenithiumColor.red)
    }

    private func rhrArrow(_ content: TodayViewModel.Content) -> (symbol: String, color: Color)? {
        guard let driver = content.recovery.drivers.first(where: { $0.driver == .restingHeartRate }) else { return nil }
        return (driver.isPositive ? "arrow.down" : "arrow.up", driver.isPositive ? ZenithiumColor.green : ZenithiumColor.red)
    }

    private func sleepArrow(_ content: TodayViewModel.Content) -> (symbol: String, color: Color)? {
        guard let driver = content.recovery.drivers.first(where: { $0.driver == .sleep }) else { return nil }
        return (driver.isPositive ? "arrow.up" : "arrow.down", driver.isPositive ? ZenithiumColor.green : ZenithiumColor.red)
    }

    private func tempArrow(_ content: TodayViewModel.Content) -> (symbol: String, color: Color)? {
        guard let driver = content.recovery.drivers.first(where: { $0.driver == .temperature }) else { return nil }
        return (driver.isPositive ? "arrow.right" : "arrow.down", driver.isPositive ? ZenithiumColor.green : ZenithiumColor.yellow)
    }

    // MARK: - TEK L2 KART — Günün Önerisi

    private func prescriptionCard(_ content: TodayViewModel.Content) -> some View {
        let decision = viewModel.athleticDecision?.value
        let confidence = viewModel.athleticDecision?.confidence.value ?? content.recovery.confidence
        let action = decision?.action ?? defaultAction(for: content.score, ceiling: content.ceiling)

        return SectionCard(
            title: "Günün Önerisi",
            subtitle: actionTitle(action)
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                // Eylem ve Yük Tavanı
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                        Text(decision?.headline ?? content.headline)
                            .zenithiumBody()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let ceiling = content.ceiling {
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: ZenithiumSpacing.none) {
                            Text("TAVAN")
                                .zenithiumEyebrow()
                            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                                Text(ZenithiumFormat.strain(ceiling))
                                    .metricNumeral()
                                    .foregroundStyle(ZenithiumColor.accent)
                                Text("/21")
                                    .metricUnit()
                            }
                        }
                    }
                }

                // Egzersiz Reçetesi
                if let prescription = viewModel.prescription {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    PrescriptionCard(prescription: prescription, plan: viewModel.planPosition)
                }

                // Güven Çubuğu
                Divider().overlay(ZenithiumColor.hairlineSoft)
                HStack(spacing: ZenithiumSpacing.s) {
                    Text("Karar Güveni")
                        .zenithiumCaption()
                    Spacer()
                    Text("%\(Int((confidence * 100).rounded()))")
                        .zenithiumCaption()
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ZenithiumColor.hairline)
                            .frame(height: 4)
                        Capsule()
                            .fill(confidenceColor(confidence))
                            .frame(width: max(8, geo.size.width * CGFloat(confidence)), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - SİRKADİYEN RİTİM (24 Saatlik İnce Şerit)

    private func circadianStripSection(_ arc: CircadianArc) -> some View {
        SectionBlock(title: "Sirkadiyen Ritim", showTopDivider: true) {
            NavigationLink {
                CircadianDetailView(arc: arc)
            } label: {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    CircadianArcView(arc: arc, showLegend: false)

                    HStack {
                        if let next = nextCircadianMarker(in: arc) {
                            let diff = next.date.timeIntervalSinceNow
                            let hours = Int(diff / 3600)
                            let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
                            let remaining = diff > 0 ? " (\(hours > 0 ? "\(hours) sa " : "")\(max(1, minutes)) dk kaldı)" : ""
                            Text("Sonraki: \(next.event.displayName) · \(next.date.formatted(date: .omitted, time: .shortened))\(remaining)")
                                .zenithiumCaption()
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        } else {
                            Text("24 saatlik uyanıklık ve melatonin döngüsü")
                                .zenithiumCaption()
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func nextCircadianMarker(in arc: CircadianArc) -> CircadianMarker? {
        let now = Date()
        return arc.markers.first { $0.date > now } ?? arc.markers.first
    }

    // MARK: - DÜN GECE (Ham Ölçümler - L1 SectionBlock)

    private func overnightSection(_ content: TodayViewModel.Content) -> some View {
        SectionBlock(title: "Dün Gece", subtitle: "Ham biyometrik ölçümler", showTopDivider: true) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                MetricTileGrid {
                    if let hrv = content.record.heartRateVariability {
                        MetricTile(
                            label: "HRV",
                            value: ZenithiumFormat.metric(hrv, digits: 0),
                            unit: "ms",
                            accessibilityLabelText: "Kalp atış hızı değişkenliği",
                            accessibilityValueText: "\(ZenithiumFormat.metric(hrv, digits: 0)) milisaniye"
                        )
                    }
                    if let rhr = content.record.restingHeartRate {
                        MetricTile(
                            label: "İstirahat nabzı",
                            value: ZenithiumFormat.metric(rhr, digits: 0),
                            unit: "bpm",
                            accessibilityLabelText: "İstirahat kalp atış hızı",
                            accessibilityValueText: "\(ZenithiumFormat.metric(rhr, digits: 0)) atım bölü dakika"
                        )
                    }
                    if let sleepScore = content.record.sleepScore {
                        MetricTile(
                            label: "Uyku",
                            value: ZenithiumFormat.score(sleepScore),
                            caption: ZenithiumFormat.duration(seconds: content.record.sleepDurationSeconds),
                            accessibilityLabelText: "Uyku puanı",
                            accessibilityValueText: "100 üzerinden \(ZenithiumFormat.score(sleepScore)), \(ZenithiumFormat.spokenDuration(seconds: content.record.sleepDurationSeconds)) uykuda"
                        )
                    }
                    if let delta = content.record.wristTemperatureDelta {
                        let converted = content.profile.unitPreference.temperatureDelta(fromCelsius: delta)
                        MetricTile(
                            label: "Bilek sıcaklığı",
                            value: ZenithiumFormat.signed(converted, digits: 2),
                            unit: content.profile.unitPreference.temperatureDeltaSymbol,
                            caption: "taban çizgine göre",
                            accessibilityLabelText: "Bilek sıcaklığı sapması",
                            accessibilityValueText: "taban çizgine göre \(ZenithiumFormat.signed(converted, digits: 2)) derece"
                        )
                    }
                    if let respiratory = content.record.respiratoryRate {
                        MetricTile(
                            label: "Solunum",
                            value: ZenithiumFormat.metric(respiratory, digits: 1),
                            unit: "br/min",
                            accessibilityLabelText: "Solunum hızı",
                            accessibilityValueText: "\(ZenithiumFormat.metric(respiratory, digits: 1)) soluk bölü dakika"
                        )
                    }
                    if let oxygen = content.record.oxygenSaturation {
                        MetricTile(
                            label: "Kandaki oksijen",
                            value: ZenithiumFormat.percent(oxygen),
                            caption: "gösteriliyor, puanlanmıyor",
                            accessibilityLabelText: "Kandaki oksijen",
                            accessibilityValueText: ZenithiumFormat.percent(oxygen)
                        )
                    }
                }

                QualityChip(
                    quality: content.record.dataQuality,
                    reasons: content.record.dataQualityReasons
                )
            }
        }
    }

    // MARK: - KARAR KANITI (L1 SectionBlock)

    private func evidenceSection(_ content: TodayViewModel.Content) -> some View {
        SectionBlock(
            title: "Karar Kanıtı",
            subtitle: "Fizyolojik belirleyiciler ve deterministik iz",
            showTopDivider: true
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                DriverBreakdownView(
                    drivers: content.recovery.drivers,
                    missing: content.recovery.missingDrivers,
                    weightsWereRenormalized: content.recovery.weightsWereRenormalized,
                    unitPreference: content.profile.unitPreference
                )

                if let decision = viewModel.athleticDecision {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    DecisionTraceCard(result: decision)
                }
            }
        }
    }

    // MARK: - BİLİMSEL ÖNERİLER (L1 SectionBlock)

    private var recommendationsSection: some View {
        SectionBlock(title: "Bilimsel Öneriler", showTopDivider: true) {
            RecommendationListView(recommendations: viewModel.recommendations)
        }
    }

    private var disclaimerFooter: some View {
        Text(SafetyCopy.disclaimerFooter)
            .zenithiumCaption()
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, ZenithiumSpacing.xs)
    }

    // MARK: - Helpers

    private func defaultAction(for score: Double, ceiling: Double?) -> DecisionAction {
        let target = ceiling ?? 12.0
        if score >= 67 { return .push(targetStrain: target) }
        if score >= 34 { return .maintain(targetStrain: target) }
        return .recover
    }

    private func actionTitle(_ action: DecisionAction) -> String {
        switch action {
        case .push: return "Yüksek Adaptasyon Kapasitesi"
        case .maintain: return "Dengeli Yüklenme"
        case .recover: return "Toparlanma Önceliği"
        case .calibrate: return "Kalibrasyon Süreci"
        }
    }

    private func actionColor(_ action: DecisionAction) -> Color {
        switch action {
        case .push: return ZenithiumColor.green
        case .maintain: return ZenithiumColor.yellow
        case .recover: return ZenithiumColor.red
        case .calibrate: return ZenithiumColor.spectrumViolet
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.80 { return ZenithiumColor.green }
        if confidence >= 0.50 { return ZenithiumColor.yellow }
        return ZenithiumColor.red
    }
}
