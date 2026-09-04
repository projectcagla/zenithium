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
    var embedInNavigation: Bool = true

    @Namespace private var todayNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingReason: Bool = false
    @State private var selectedMetricForDetail: SupportingMetricDetail? = nil

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Bugün")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .refreshable { await viewModel.refresh() }
            }
            .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.42)
            .task { await viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
        } else {
            mainContent
                .zenithiumBackground(tint: ZenithiumColor.spectrumViolet, intensity: 0.42)
                .task { await viewModel.onAppear() }
                .onDisappear { viewModel.onDisappear() }
        }
    }

    private var mainContent: some View {
        ZStack {
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

            if let metric = selectedMetricForDetail {
                metricDetailOverlay(metric)
                    .zIndex(15)
            }

            if showingReason, let content = viewModel.state.value {
                ReasonView(
                    recommendation: viewModel.recommendations.first ?? fallbackRecommendation(content),
                    embedInNavigation: false,
                    namespace: todayNamespace,
                    onDismiss: {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82)) {
                            showingReason = false
                        }
                    }
                )
                .background(ZenithiumColor.background.ignoresSafeArea())
                .transition(.opacity)
                .zIndex(20)
            }
        }
    }

    @ViewBuilder
    private func loadedBody(_ content: TodayViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Toparlanma Skoru Dairesi (64pt sayı, ortalanmış, kartsız)
            recoveryHero(content)

            // 2. KADEME: Günün Tek Önerisi (TEK L2 KART) → Dokununca Neden ekranına
            prescriptionCard(content)

            // 3. KADEME: 4 Destekleyici Metrik (HRV, İstirahat, Uyku, Sıcaklık — kartsız yatay akış + .micro taban bandı)
            supportingMetricsStrip(content)

            // 4. KADEME: Karar İzi (Dikey 3 Adımlı Çizgi, kartsız L1)
            evidenceSection(content)

            // SİRKADİYEN RİTİM: 24 Saatlik İnce Şerit (Sessiz bant)
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
            .matchedGeometryEffect(id: "today-reason-score", in: todayNamespace)
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
        HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
            supportingMetricItem(
                id: "hrv",
                label: "HRV",
                value: content.record.heartRateVariability.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "ms",
                bandValues: [content.record.heartRateVariability ?? 49.0],
                baseline: 52.0,
                sigma: 6.0,
                description: "Gece boyunca ölçülen kalp atış hızı değişkenliği (rMSSD). Otonom sinir sistemi dengesini ve parasempatik aktiviteyi yansıtır."
            )

            Divider().overlay(ZenithiumColor.hairlineSoft).frame(height: 60)

            supportingMetricItem(
                id: "rhr",
                label: "İstirahat",
                value: content.record.restingHeartRate.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "bpm",
                bandValues: [content.record.restingHeartRate ?? 54.0],
                baseline: 53.0,
                sigma: 3.5,
                description: "Uyku sırasındaki en düşük dinlenme kalp atış hızı. Kardiyovasküler toparlanma ve sistemik yorgunluğun birincil göstergesidir."
            )

            Divider().overlay(ZenithiumColor.hairlineSoft).frame(height: 60)

            supportingMetricItem(
                id: "sleep",
                label: "Uyku",
                value: content.record.sleepScore.map { ZenithiumFormat.score($0) } ?? "—",
                unit: "%",
                bandValues: [content.record.sleepScore ?? 100.0],
                baseline: 85.0,
                sigma: 8.0,
                description: "Uyku süresi, evre dağılımı (derin, REM) ve gece bölünmelerinin ağırlıklı bileşik skoru."
            )

            Divider().overlay(ZenithiumColor.hairlineSoft).frame(height: 60)

            supportingMetricItem(
                id: "temp",
                label: "Sıcaklık",
                value: content.record.wristTemperatureDelta.map {
                    let converted = content.profile.unitPreference.temperatureDelta(fromCelsius: $0)
                    return ZenithiumFormat.signed(converted, digits: 1)
                } ?? "—",
                unit: content.profile.unitPreference.temperatureDeltaSymbol,
                bandValues: [content.record.wristTemperatureDelta ?? -0.3],
                baseline: 0.0,
                sigma: 0.35,
                description: "Taban çizgisine göre bilek cilt sıcaklığı sapması. İmmün yanıt veya aşırı antrenman yükünü erken haber verir."
            )
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .overlay(alignment: .top) { Divider().overlay(ZenithiumColor.hairlineSoft) }
        .overlay(alignment: .bottom) { Divider().overlay(ZenithiumColor.hairlineSoft) }
    }

    private func supportingMetricItem(
        id: String,
        label: String,
        value: String,
        unit: String,
        bandValues: [Double],
        baseline: Double,
        sigma: Double,
        description: String
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82)) {
                selectedMetricForDetail = SupportingMetricDetail(
                    id: id,
                    label: label,
                    value: value,
                    unit: unit,
                    bandValues: bandValues,
                    baseline: baseline,
                    sigma: sigma,
                    description: description
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(label.uppercased())
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                    Text(value)
                        .font(ZenithiumFont.metricNumeral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(unit)
                        .font(ZenithiumFont.metricUnit)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
                if selectedMetricForDetail?.id != id {
                    BaselineBand(
                        values: bandValues,
                        baseline: baseline,
                        sigma: sigma,
                        unit: unit,
                        style: .micro
                    )
                    .matchedGeometryEffect(id: "baseline-\(id)", in: todayNamespace)
                    .frame(height: 20)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value) \(unit)")
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

        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82)) {
                showingReason = true
            }
        } label: {
            SectionCard(
                title: "Günün Önerisi",
                subtitle: actionTitle(action)
            ) {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    // Eylem ve Yük Tavanı
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                            HStack(spacing: 6) {
                                Text(actionBadgeText(action))
                                    .font(ZenithiumFont.label)
                                    .foregroundStyle(actionColor(action))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(actionColor(action).opacity(0.16))
                                    )
                                    .matchedGeometryEffect(id: "today-reason-hero", in: todayNamespace)

                                Spacer()
                            }

                            Text(decision?.headline ?? content.headline)
                                .zenithiumBody()
                                .foregroundStyle(ZenithiumColor.textPrimary)
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
        .buttonStyle(.plain)
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

    private func actionBadgeText(_ action: DecisionAction) -> String {
        switch action {
        case .push: return "Öneri"
        case .maintain: return "Denge"
        case .recover: return "Uyarı"
        case .calibrate: return "Kalibrasyon"
        }
    }

    private func fallbackRecommendation(_ content: TodayViewModel.Content) -> Recommendation {
        viewModel.recommendations.first ?? PreviewFixtures.sampleRecommendation
    }

    private func metricDetailOverlay(_ metric: SupportingMetricDetail) -> some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedMetricForDetail = nil
                    }
                }

            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label.uppercased())
                            .zenithiumEyebrow()
                        HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                            Text(metric.value)
                                .font(ZenithiumFont.metricNumeral)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text(metric.unit)
                                .zenithiumCaption()
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedMetricForDetail = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                BaselineBand(
                    values: metric.bandValues,
                    baseline: metric.baseline,
                    sigma: metric.sigma,
                    unit: metric.unit,
                    style: .full
                )
                .matchedGeometryEffect(id: "baseline-\(metric.id)", in: todayNamespace)
                .frame(height: 180)

                Text(metric.description)
                    .zenithiumBody()
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenithiumSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                    .fill(ZenithiumColor.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                            .strokeBorder(ZenithiumColor.hairline, lineWidth: 1)
                    )
            )
            .padding(.horizontal, ZenithiumSpacing.m)
        }
    }
}

struct SupportingMetricDetail: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let unit: String
    let bandValues: [Double]
    let baseline: Double
    let sigma: Double
    let description: String
}

#Preview("Bugün · dolu") {
    TodayPreviewWrapper(state: .dolu)
}

#Preview("Bugün · kalibrasyon") {
    TodayPreviewWrapper(state: .kalibrasyon)
}

#Preview("Bugün · veri yok") {
    TodayPreviewWrapper(state: .veriyok)
}

private struct TodayPreviewWrapper: View {
    let state: PreviewState
    @State private var viewModel: TodayViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TodayView(viewModel: viewModel)
            } else {
                ZenithiumColor.background.ignoresSafeArea()
                    .task {
                        viewModel = await PreviewFixtures.shared.makeTodayViewModel(state: state)
                    }
            }
        }
    }
}
