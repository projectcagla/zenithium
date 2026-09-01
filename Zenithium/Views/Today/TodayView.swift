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
        VStack(spacing: ZenithiumSpacing.l) {
            ringSection(content)
            if let briefing = viewModel.briefing {
                BriefingCard(briefing: briefing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let decision = viewModel.athleticDecision {
                DecisionTraceCard(result: decision)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let prescription = viewModel.prescription {
                PrescriptionCard(prescription: prescription, plan: viewModel.planPosition)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            guidanceSection(content)
            driverSection(content)
            overnightSection(content)
            if let circadian = content.circadian {
                circadianSection(circadian)
            }
            disclaimerFooter
        }
        .padding(.top, ZenithiumSpacing.s)
        .animation(.easeOut(duration: 0.25), value: viewModel.briefing)
        .animation(.easeOut(duration: 0.25), value: viewModel.athleticDecision)
        .animation(.easeOut(duration: 0.25), value: viewModel.prescription)
    }

    // MARK: - Sections

    private func ringSection(_ content: TodayViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            RecoveryArc(
                score: content.score,
                band: content.band,
                confidence: content.recovery.confidence
            )
            .padding(.top, ZenithiumSpacing.s)

            BandChip(band: content.band)

            if content.recovery.confidence < 1 {
                // §4.2.4 — a blended score says so, rather than presenting a thin baseline
                // with the same authority as a settled one.
                Text("Taban çizgin kurulurken toplum ortalamalarıyla harmanlanıyor — \(ZenithiumFormat.percent(content.recovery.confidence)) kişisel.")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func guidanceSection(_ content: TodayViewModel.Content) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text(content.headline)
                    .font(ZenithiumFont.sectionTitle)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(content.guidance)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(content.driverSentence)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let ceiling = content.ceiling {
                    Divider().overlay(ZenithiumColor.hairline)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Bugünün hedef zorlanması")
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
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func driverSection(_ content: TodayViewModel.Content) -> some View {
        SectionCard(
            title: "Bunu ne hareket ettirdi",
            subtitle: "Her belirleyicinin bugünkü sapmadaki payı"
        ) {
            DriverBreakdownView(
                drivers: content.recovery.drivers,
                missing: content.recovery.missingDrivers,
                weightsWereRenormalized: content.recovery.weightsWereRenormalized,
                unitPreference: content.profile.unitPreference
            )
        }
    }

    private func overnightSection(_ content: TodayViewModel.Content) -> some View {
        SectionCard(title: "Dün gece") {
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
}
