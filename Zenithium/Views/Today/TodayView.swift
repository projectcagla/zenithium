//
//  TodayView.swift
//  Zenithium
//
//  The Today screen — "how recovered am I". Spec §1, §10.
//
//  Every number rendered here arrives pre-computed on the view model's `Content` (§9). The
//  view chooses layout and wording; it never does arithmetic on a score.
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
                .padding(.horizontal, ZenithiumSpacing.l)
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
        VStack(spacing: ZenithiumSpacing.xl) {
            // KATMAN 1 — KARAR: Bugün ne yapmalıyım?
            decisionHero(content)

            // KATMAN 2 — KANITI: Neden? & Ne kadar eminsin?
            evidenceLayer(content)

            // KATMAN 2.5 — BİLİMSEL ÖNERİLER & KANIT LİSTESİ (Faz 34)
            if !viewModel.recommendations.isEmpty {
                RecommendationListView(recommendations: viewModel.recommendations)
            }

            // KATMAN 3 — DÜN GECE: Ham ölçümler ve sınırlar
            overnightLayer(content)

            if let circadian = content.circadian {
                circadianSection(circadian)
            }

            disclaimerFooter
        }
        .padding(.top, ZenithiumSpacing.s)
        .animation(.easeOut(duration: 0.25), value: viewModel.briefing)
        .animation(.easeOut(duration: 0.25), value: viewModel.athleticDecision)
        .animation(.easeOut(duration: 0.25), value: viewModel.prescription)
        .animation(.easeOut(duration: 0.25), value: viewModel.recommendations)
    }

    // MARK: - KATMAN 1 — KARAR (Günün Hükmü - Kart Değil, Ekranın Başı)

    private func decisionHero(_ content: TodayViewModel.Content) -> some View {
        let decision = viewModel.athleticDecision?.value
        let confidence = viewModel.athleticDecision?.confidence.value ?? content.recovery.confidence
        let action = decision?.action ?? defaultAction(for: content.score, ceiling: content.ceiling)

        return VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            // Üst Başlık & Güven Rozeti
            HStack(alignment: .center) {
                Text("BUGÜNÜN HÜKMÜ")
                    .zenithiumEyebrow()

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(confidenceColor(confidence))
                        .frame(width: 6, height: 6)
                    Text("%\(Int(confidence * 100)) Güven")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
                .padding(.horizontal, ZenithiumSpacing.s)
                .padding(.vertical, 3)
                .background(ZenithiumColor.surfaceElevated)
                .clipShape(Capsule())
            }

            // Ana Eylem ve Hedef
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(actionTitle(action))
                        .font(ZenithiumFont.verdict)
                        .foregroundStyle(actionColor(action))

                    Text(decision?.headline ?? content.headline)
                        .font(ZenithiumFont.body)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                // Skor / Tavan
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(ZenithiumFormat.score(content.score))
                            .font(ZenithiumFont.displayValue)
                            .foregroundStyle(ZenithiumColor.color(for: content.band))
                        Text("%")
                            .font(ZenithiumFont.unit)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                    .contentTransition(.numericText())

                    BandChip(band: content.band)
                }
            }

            // Düşük Güven / Kalibrasyon Bildirimi
            if confidence < 0.70 {
                HStack(alignment: .top, spacing: ZenithiumSpacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ZenithiumColor.yellow)
                    Text("Taban çizgisi oturana kadar karar genişletilmiş toleransla hesaplanıyor (%\(Int(confidence * 100)) güven düzeyi).")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            Divider()
                .overlay(ZenithiumColor.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ZenithiumSpacing.xs)
    }

    // MARK: - KATMAN 2 — KANITI (Gerekçe, Sürücüler & Epistemik İz)

    private func evidenceLayer(_ content: TodayViewModel.Content) -> some View {
        SectionCard(
            title: "Neden Bu Karar?",
            subtitle: "Fizyolojik gerekçe, belirleyiciler ve kanıt izi"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                // 1. Gerekçe Paragrafı
                Text(viewModel.athleticDecision?.value.primaryRationale ?? content.guidance)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 2. En Baskın Biyometrik Sürücüler
                DriverBreakdownView(
                    drivers: content.recovery.drivers,
                    missing: content.recovery.missingDrivers,
                    weightsWereRenormalized: content.recovery.weightsWereRenormalized,
                    unitPreference: content.profile.unitPreference
                )

                // 3. Hedef Yük Tavanı
                if let ceiling = content.ceiling {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Bugünün hedef fizyolojik yük tavanı")
                            .font(ZenithiumFont.label)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                        Spacer(minLength: 8)
                        Text(ZenithiumFormat.strain(ceiling))
                            .font(ZenithiumFont.metricValue)
                            .foregroundStyle(ZenithiumColor.accent)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Bugünün hedef zorlanması")
                    .accessibilityValue("21 üzerinden \(ZenithiumFormat.strain(ceiling))")
                }

                // 4. Günün Egzersiz Reçetesi
                if let prescription = viewModel.prescription {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    PrescriptionCard(prescription: prescription, plan: viewModel.planPosition)
                }

                // 5. Deterministik Karar İzi
                if let decision = viewModel.athleticDecision {
                    Divider().overlay(ZenithiumColor.hairlineSoft)
                    DecisionTraceCard(result: decision)
                }
            }
        }
    }

    // MARK: - KATMAN 3 — DÜN GECE (Ham Ölçümler)

    private func overnightLayer(_ content: TodayViewModel.Content) -> some View {
        SectionCard(
            title: "Dün Gece",
            subtitle: "Ham biyometrik ölçümler"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
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

    private func circadianSection(_ arc: CircadianArc) -> some View {
        SectionCard(
            title: "Günün",
            subtitle: "Gün boyunca uyanıklık, uykuna göre demirlenmiş"
        ) {
            CircadianArcView(arc: arc)
                .frame(height: 140)
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
