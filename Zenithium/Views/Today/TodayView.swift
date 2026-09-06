import SwiftUI
import SwiftData

struct TodayView: View {

    @State var viewModel: TodayViewModel
    var embedInNavigation: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var baselineSnapshots: [BaselineSnapshot] = []
    @State private var metricTrendsViewModel: TrendsViewModel?
    @State private var metricHistory: [String: [Double]] = [:]
    @State private var showingProfile = false

    @Namespace private var todayNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingReason: Bool = false
    @State private var selectedMetricForDetail: SupportingMetricDetail? = nil

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Bugün")
                    .navigationBarTitleDisplayMode(.inline)
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
                    actionCallout: "İlk gecenizden sonra toparlanma skorunuz burada hesaplanacak.",
                    retry: { await viewModel.refresh() },
                    requestAccess: { await viewModel.requestAuthorization() }
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.screenEdge)
                .padding(.bottom, ZenithiumSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityHidden(showingReason || selectedMetricForDetail != nil)
            .background(ZenithiumColor.background.ignoresSafeArea())

            if let metric = selectedMetricForDetail {
                metricDetailOverlay(metric)
                    .zIndex(15)
            }

            if showingReason, let content = viewModel.state.value {
                ReasonView(
                    recommendation: dailyRecommendation(content),
                    embedInNavigation: false,
                    namespace: todayNamespace,
                    calculationSteps: viewModel.athleticDecision?.calculationSteps ?? [],
                    relatedRecommendations: viewModel.recommendations,
                    onDismiss: {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            showingReason = false
                        }
                    }
                )
                .background(ZenithiumColor.background.ignoresSafeArea())
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .toolbar(showingReason || selectedMetricForDetail != nil ? .hidden : .visible, for: .navigationBar)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }

    @ViewBuilder
    private func loadedBody(_ content: TodayViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            HStack {
                Button { showingProfile = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Profil özeti")
                Spacer()
                Text(content.record.dayStart.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "tr_TR"))))
                    .zenithiumCaption()
            }
            recoveryHero(content)
            supportingMetricsStrip(content)
            prescriptionCard(content)
            if let circadian = content.circadian { circadianStripSection(circadian) }
            DisclosureGroup("Ölçümler ve karar ayrıntıları") {
                VStack(spacing: ZenithiumSpacing.sectionSpacing) {
                    overnightSection(content)
                    evidenceSection(content)
                    if !viewModel.recommendations.isEmpty { recommendationsSection }
                }
                .padding(.top, ZenithiumSpacing.xl)
            }
            .font(ZenithiumFont.secondary)
            .tint(ZenithiumColor.textSecondary)
            disclaimerFooter
        }
        .padding(.top, ZenithiumSpacing.s)
        .task(id: content.record.computedAt) { loadMetricHistory(before: content.record.dayStart) }
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xl) {
                    Text("Sana göre bir ritim").screenTitle()
                    Text(content.profile.trainingLens.displayName).sectionTitle()
                    Text("Toparlanma, uyku ve antrenman verilerin bu merceğe göre yorumlanıyor. Profil tercihlerini Daha fazla → Ayarlar bölümünden düzenleyebilirsin.")
                        .zenithiumSecondary()
                    QualityChip(quality: content.record.dataQuality, reasons: content.record.dataQualityReasons)
                    Spacer()
                }
                .padding(ZenithiumSpacing.screenEdge)
                .background(ZenithiumColor.background)
                .navigationTitle("Profil")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showingProfile = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 1. KADEME (KAHRAMAN) — Toparlanma Skoru

    private func recoveryHero(_ content: TodayViewModel.Content) -> some View {
        let confidence = viewModel.athleticDecision?.confidence.value ?? content.recovery.confidence
        let rationale = viewModel.athleticDecision?.value.primaryRationale ?? content.guidance

        return VStack(spacing: ZenithiumSpacing.m) {
            Text("TOPARLANMA").zenithiumEyebrow()
            if !showingReason {
                RecoveryArc(score: content.score, band: content.band, confidence: confidence)
                    .matchedGeometryEffect(id: "today-reason-score", in: todayNamespace)
            } else {
                Color.clear.frame(height: 180)
            }
            Text(recoveryTitle(content.band))
                .font(ZenithiumFont.eyebrow)
                .tracking(1.2)
                .foregroundStyle(ZenithiumColor.color(for: content.band))
            Text(rationale)
                .zenithiumBody()
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .accessibilityLabel(rationale)
            if confidence < 0.70 {
                Label("Kişisel tabanın gelişiyor · \(ZenithiumFormat.percent(confidence)) güven", systemImage: "circle.dotted")
                    .zenithiumCaption()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, ZenithiumSpacing.s)
    }

    private func recoveryTitle(_ band: RecoveryBand) -> String {
        switch band {
        case .green: return "YÜKSEK TOPARLANMA"
        case .yellow: return "DENGELİ TOPARLANMA"
        case .red: return "TOPARLANMAYA ALAN AÇ"
        }
    }

    // MARK: - 2. KADEME — Dört Destekleyici Ölçüm Şeridi (L1 Sessiz Şerit)

    private func supportingMetricsStrip(_ content: TodayViewModel.Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            supportingMetricItem(
                id: "hrv", label: "HRV",
                value: content.record.heartRateVariability.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "ms", bandValues: history("hrv", current: content.record.heartRateVariability),
                baseline: baseline(.heartRateVariability)?.mean,
                sigma: baseline(.heartRateVariability)?.standardDeviation,
                description: "Apple Sağlık'ta kaydedilen HRV (SDNN). Koridor, mevcut 60 günlük ağırlıklı kişisel tabanı gösterir. Tek ölçüm bir tanı değildir."
            )
            ribbonDivider
            supportingMetricItem(
                id: "rhr", label: "Dinlenme",
                value: content.record.restingHeartRate.map { ZenithiumFormat.metric($0, digits: 0) } ?? "—",
                unit: "bpm", bandValues: history("rhr", current: content.record.restingHeartRate),
                baseline: baseline(.restingHeartRate)?.mean,
                sigma: baseline(.restingHeartRate)?.standardDeviation,
                description: "Dinlenme nabzının kişisel tabanına göre seyri. Koridor, mevcut 60 günlük ağırlıklı ortalaman ve ±1 standart sapmadır."
            )
            ribbonDivider
            supportingMetricItem(
                id: "sleep", label: "Uyku",
                value: content.record.sleepDurationSeconds > 0 ? ZenithiumFormat.metric(content.record.sleepDurationSeconds / 3600, digits: 1) : "—",
                unit: "sa", bandValues: history("sleep", current: content.record.sleepDurationSeconds > 0 ? content.record.sleepDurationSeconds / 3600 : nil),
                baseline: nil, sigma: nil,
                description: "Kaydedilen toplam uyku süresi. Bu ölçüm için kişisel taban modeli bulunmadığından yalnızca gerçek gece süreleri gösterilir."
            )
            ribbonDivider
            supportingMetricItem(
                id: "temp", label: "Bilek",
                value: content.record.wristTemperatureDelta.map { ZenithiumFormat.signed($0, digits: 1) } ?? "—",
                unit: "Δ°C", bandValues: history("temp", current: content.record.wristTemperatureDelta),
                baseline: baseline(.wristTemperature).map { _ in 0 },
                sigma: baseline(.wristTemperature)?.standardDeviation,
                description: "Bilek sıcaklığının kişisel tabana göre farkı. Sıfır çizgisi tabanı, koridor ölçülen değişkenliği gösterir."
            )
        }
    }

    @ViewBuilder private var ribbonDivider: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Rectangle().fill(ZenithiumColor.hairline).frame(width: 0.5, height: 88)
        }
    }

    private func baseline(_ metric: MetricKind) -> BaselineSnapshot? {
        baselineSnapshots.first { $0.metric == metric && $0.isSeeded }
    }

    private func history(_ id: String, current: Double?) -> [Double] {
        guard let current, current.isFinite else { return [] }
        return (metricHistory[id] ?? []) + [current]
    }

    private func loadMetricHistory(before date: Date) {
        baselineSnapshots = ((try? modelContext.fetch(FetchDescriptor<BaselineState>())) ?? []).compactMap(\.snapshot)
        let start = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -60, to: date) ?? date
        var query = FetchDescriptor<BiometricDayRecord>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart < date },
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        query.fetchLimit = 60
        guard let rows = try? modelContext.fetch(query) else { metricHistory = [:]; return }
        let ordered = rows.reversed()
        metricHistory = [
            "hrv": ordered.compactMap(\.hrvSDNN),
            "rhr": ordered.compactMap(\.restingHR),
            "sleep": ordered.filter { $0.sleepDurationSeconds > 0 }.map { $0.sleepDurationSeconds / 3600 },
            "temp": ordered.compactMap(\.wristTempDelta)
        ]
    }

    private func supportingMetricItem(
        id: String,
        label: String,
        value: String,
        unit: String,
        bandValues: [Double],
        baseline: Double?,
        sigma: Double?,
        description: String
    ) -> some View {
        Button {
            if id == "hrv" || id == "rhr" {
                let store = ZenithiumStore(modelContainer: modelContext.container)
                metricTrendsViewModel = TrendsViewModel(repository: store, bloodMarkers: store)
            } else {
                metricTrendsViewModel = nil
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(ZenithiumFont.eyebrow)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .metricNumeral()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(ZenithiumFont.metricUnit)
                    .foregroundStyle(ZenithiumColor.textSecondary)
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

        return SectionCard(title: "Günün kararı") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(actionTitle(action))
                            .font(ZenithiumFont.label)
                            .foregroundStyle(actionColor(action))
                            .matchedGeometryEffect(id: "today-reason-hero", in: todayNamespace, isSource: !showingReason)
                        Text(decision?.headline ?? content.headline).zenithiumBody()
                    }
                    Spacer(minLength: 0)
                    if let ceiling = content.ceiling {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TAVAN").zenithiumEyebrow()
                            Text(ZenithiumFormat.strain(ceiling)).metricNumeral()
                            Text("/ 21").zenithiumCaption()
                        }
                    }
                }
                if let prescription = viewModel.prescription {
                    DisclosureGroup("Antrenman ve alternatifler") {
                        PrescriptionCard(prescription: prescription, plan: viewModel.planPosition)
                            .padding(.top, 12)
                    }
                    .font(ZenithiumFont.secondary)
                    .tint(ZenithiumColor.accent)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showingReason = true }
                } label: {
                    HStack {
                        Label("Bu kararın nedeni", systemImage: "arrow.up.right")
                        Spacer()
                        Text("\(ZenithiumFormat.percent(confidence)) güven")
                    }
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            RecommendationListView(recommendations: viewModel.recommendations, showsSurfaces: false)
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

    private func dailyRecommendation(_ content: TodayViewModel.Content) -> Recommendation {
        let result = viewModel.athleticDecision
        return Recommendation(
            id: "daily-decision", domain: .training, strength: .observation,
            headline: result?.value.headline ?? content.headline,
            body: result?.value.primaryRationale ?? content.guidance,
            confidence: result?.confidence ?? ConfidenceScore(value: content.recovery.confidence),
            evidence: result?.evidence ?? [],
            limitations: result?.limitations ?? [],
            wouldChangeIf: ["Yeni uyku, toparlanma veya antrenman verisi kaydedildiğinde karar yeniden değerlendirilir."],
            disclaimerTier: .training
        )
    }

    @ViewBuilder
    private func metricDetailOverlay(_ metric: SupportingMetricDetail) -> some View {
        if let metricTrendsViewModel {
            VStack(spacing: 0) {
                HStack {
                    Text("Trendler").sectionTitle()
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { selectedMetricForDetail = nil }
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Trendleri kapat")
                }
                .padding(.horizontal, ZenithiumSpacing.screenEdge)
                TrendsView(viewModel: metricTrendsViewModel, embedInNavigation: false,
                           initialMetric: metric.id == "hrv" ? .heartRateVariability : .restingHeartRate,
                           transitionNamespace: todayNamespace, transitionID: "baseline-\(metric.id)", transitionPreview: metric)
            }
            .background(ZenithiumColor.background.ignoresSafeArea())
            .transition(.opacity)
        } else {
            metricHistoryOverlay(metric)
        }
    }

    private func metricHistoryOverlay(_ metric: SupportingMetricDetail) -> some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        selectedMetricForDetail = nil
                    }
                }

            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label.uppercased(with: Locale(identifier: "tr_TR")))
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
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            selectedMetricForDetail = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(ZenithiumColor.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ölçüm ayrıntısını kapat")
                }

                BaselineBand(
                    values: metric.bandValues,
                    baseline: metric.baseline,
                    sigma: metric.sigma,
                    unit: metric.unit,
                    style: .full
                )
                .matchedGeometryEffect(id: "baseline-\(metric.id)", in: todayNamespace)

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
    let baseline: Double?
    let sigma: Double?
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
