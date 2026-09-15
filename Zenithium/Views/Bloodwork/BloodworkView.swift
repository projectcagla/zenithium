import SwiftUI

struct BloodworkView: View {

    @State var viewModel: BloodworkViewModel
    var embedInNavigation: Bool = true
    @State private var selectedPanel: BiomarkerPanel?
    @Namespace private var panelNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isAddingEntry = false
    @State private var isImportingReport = false
    @State private var opensManualAfterImport = false

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Kan Değerleri")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button {
                                    isImportingReport = true
                                } label: {
                                    Label("PDF veya fotoğraf içe aktar", systemImage: "doc.text.viewfinder")
                                }
                                Button {
                                    isAddingEntry = true
                                } label: {
                                    Label("Elle değer gir", systemImage: "square.and.pencil")
                                }
                            } label: {
                                Label("Sonuç ekle", systemImage: "plus")
                            }
                            .accessibilityLabel("Sonuç ekle")
                        }
                    }
                    .sheet(isPresented: $isAddingEntry) {
                        BloodMarkerEditorView(viewModel: viewModel)
                    }
                    .sheet(isPresented: $isImportingReport, onDismiss: {
                        if opensManualAfterImport { opensManualAfterImport = false; isAddingEntry = true }
                        Task { await viewModel.load() }
                    }) {
                        LabImportView(repository: viewModel.markerRepository, documents: viewModel.documentRepository, onManualEntry: { opensManualAfterImport = true }) {
                            Task { await viewModel.load() }
                        }
                    }
            }
            .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.3)
            .task { await viewModel.onAppear() }
        } else {
            mainContent
                .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.3)
                .task { await viewModel.onAppear() }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.sectionSpacing) {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Sonuçlar yükleniyor",
                    actionCallout: "Sağlık ocağı veya laboratuvar tahlilinizi PDF olarak aktarın.",
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }

                disclaimerText
            }
            .padding(.horizontal, ZenithiumSpacing.screenEdge)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    private var disclaimerText: some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(ZenithiumColor.textTertiary)
                .accessibilityHidden(true)
            Text(SafetyCopy.bloodworkDisclaimer)
                .zenithiumCaption()
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ZenithiumSpacing.m)
    }

    @ViewBuilder
    private func loadedBody(_ content: BloodworkViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): Son test tarihi ve genel durum özeti (kartsız)
            headerHero(content)

            // 2. KADEME: Aksiyon Gerektiren Bulgular Özeti (TEK L2 KART)
            actionableFindingsSection(content)
            if !content.trainingContext.isEmpty {
                NavigationLink {
                    LabTrainingContextView(context: content.trainingContext, series: content.series)
                } label: {
                    Label("Tahlil günlerinde HRV ve antrenman yükü", systemImage: "chart.xyaxis.line")
                        .zenithiumBody().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

            // 3. KADEME: Sistemlere Göre Gruplanmış Biyobelirteçler (kartsız L1 SectionBlock)
            panelPicker
            ForEach(content.panels.filter { selectedPanel == nil || $0.panel == selectedPanel }) { group in
                panelBlock(title: group.panel.displayName, series: group.series)
            }

            let ungrouped = content.series.filter { $0.marker.panel == nil }
            if !ungrouped.isEmpty && selectedPanel == nil {
                panelBlock(title: "Diğer Belirteçler", series: ungrouped)
            }
            if let selectedPanel, !content.panels.contains(where: { $0.panel == selectedPanel }) {
                Text("Bu kategoride henüz sonuç yok. Yeni bir tahlil sonucu ekleyebilirsin.")
                    .zenithiumSecondary()
            }
        }
    }

    private var panelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                panelPill(nil, title: "Tümü")
                ForEach(BiomarkerPanel.allCases, id: \.self) { panel in
                    panelPill(panel, title: panel == .inflammation ? "Enflamasyon" : panel.displayName)
                }
            }
        }
    }

    private func panelPill(_ panel: BiomarkerPanel?, title: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedPanel = panel }
        } label: {
            Text(title)
                .font(ZenithiumFont.label)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(selectedPanel == panel ? ZenithiumColor.accent : ZenithiumColor.textSecondary)
                .background {
                    if selectedPanel == panel {
                        Capsule().fill(ZenithiumColor.accent.opacity(0.12))
                            .matchedGeometryEffect(id: "panel-selection", in: panelNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPanel == panel ? .isSelected : [])
    }

    // MARK: - 1. KADEME (KAHRAMAN): Son Test ve Durum Özeti (Kartsız)

    private func headerHero(_ content: BloodworkViewModel.Content) -> some View {
        let lastDate = content.series.compactMap(\.latest).map(\.drawnAt).max()
        let assessed = content.series.compactMap(\.latest).filter { $0.referenceRange.isBounded }
        let within = assessed.filter { $0.referenceRange.contains($0.value) }.count
        return VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Text("REFERANS ARALIĞINDA").zenithiumEyebrow()
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(assessed.isEmpty ? "—" : "\(within)").heroNumeral()
                Text("/ \(assessed.count) belirteç").heroUnit()
            }
            if let lastDate {
                Text("Son tahlil · \(lastDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR"))))")
                    .zenithiumCaption()
            }
            Text("\(content.series.count) belirteç izleniyor. Bu özet, her belirtecin en son sonucu ve laboratuvar referansıyla oluşturulur.")
                .zenithiumSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - TEK L2 KART / SESSİZ L1 SATIR: Aksiyon Gerektiren Bulgular

    private func actionableFindingsSection(_ content: BloodworkViewModel.Content) -> some View {
        let actionable = content.observations
        let outside = content.series.compactMap(\.latest).filter { $0.referenceRange.isBounded && !$0.referenceRange.contains($0.value) }
        let unknown = content.series.compactMap(\.latest).filter { !$0.referenceRange.isBounded }.count
        return SectionCard(title: outside.isEmpty ? "Panel özeti" : "Referans dışı sonuçlar") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                if !outside.isEmpty {
                    Label("\(outside.count) belirteç laboratuvar referansının dışında", systemImage: "exclamationmark.circle")
                        .zenithiumBody()
                        .foregroundStyle(ZenithiumColor.yellow)
                } else {
                    Text("Referansı bulunan son sonuçlarda aralık dışı değer görünmüyor.").zenithiumBody()
                }
                if unknown > 0 {
                    Text("\(unknown) belirteç için referans aralığı bulunmuyor.").zenithiumCaption()
                }
                ForEach(actionable) { observation in
                    Text(observation.message).zenithiumSecondary()
                }
                Text(SafetyCopy.clinicianPrompt).zenithiumCaption()
            }
        }
    }

    // MARK: - KAHRAMAN: Sakin Liste Panelleri (L1)

    private func panelBlock(title: String, series: [BloodworkViewModel.MarkerSeries]) -> some View {
        SectionBlock(
            title: title,
            subtitle: "\(series.count) belirteç",
            showTopDivider: true
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(series) { entry in
                    NavigationLink {
                        BloodMarkerDetailView(series: entry, viewModel: viewModel)
                    } label: {
                        MarkerSummaryRow(series: entry)
                    }
                    .buttonStyle(.plain)

                    if entry.id != series.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }
}

/// One marker row in the serene list.
/// Spec: Calm row. Color ONLY on out-of-reference values (red/yellow). Normal values quiet gray.
/// Columns: marker name, value, unit, reference range, last test date.
private struct MarkerSummaryRow: View {

    let series: BloodworkViewModel.MarkerSeries

    private var isOutOfRange: Bool {
        guard let latest = series.latest, latest.referenceRange.isBounded else { return false }
        return !latest.referenceRange.contains(latest.value)
    }

    private var valueColor: Color {
        if isOutOfRange {
            return ZenithiumColor.yellow
        }
        return ZenithiumColor.textPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(series.marker.displayName).zenithiumBody()
                Spacer(minLength: 4)
                if let latest = series.latest {
                    Text(ZenithiumFormat.metric(latest.value, digits: series.marker.fractionDigits))
                        .metricNumeral().foregroundStyle(valueColor)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(latest.unitSymbol).metricUnit()
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
            if let latest = series.latest {
                if let low = latest.referenceRange.minimum, let high = latest.referenceRange.maximum, high > low {
                    let optimal: ClosedRange<Double>? = {
                        guard let lower = latest.optimalRange.minimum, let upper = latest.optimalRange.maximum, upper > lower else { return nil }
                        return lower...upper
                    }()
                    BaselineBand(values: [latest.value], baseline: (low + high) / 2, sigma: (high - low) / 2, unit: latest.unitSymbol, style: .inline, tint: ZenithiumColor.textSecondary, referenceLabel: "Laboratuvar referansı", horizontalRange: true, secondaryRange: optimal)
                }
                HStack(alignment: .top) {
                    Text(referenceText(latest.referenceRange)).zenithiumCaption()
                    Spacer()
                    Text(latest.drawnAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "tr_TR"))))
                        .zenithiumCaption()
                }
                if let change = series.changeSincePrevious {
                    Text("Önceki ölçümden \(ZenithiumFormat.signed(change, digits: series.marker.fractionDigits)) \(latest.unitSymbol)").zenithiumCaption()
                }
                if isOutOfRange {
                    Label("Referans dışında", systemImage: "exclamationmark.triangle")
                        .font(ZenithiumFont.caption).foregroundStyle(valueColor)
                }
            }
        }
        .padding(.vertical, ZenithiumSpacing.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.marker.accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private func referenceText(_ range: MarkerRange) -> String {
        let digits = series.marker.fractionDigits
        if let lower = range.minimum, let upper = range.maximum {
            return "Referans \(ZenithiumFormat.metric(lower, digits: digits))–\(ZenithiumFormat.metric(upper, digits: digits))"
        }
        if let lower = range.minimum { return "Referans ≥ \(ZenithiumFormat.metric(lower, digits: digits))" }
        if let upper = range.maximum { return "Referans ≤ \(ZenithiumFormat.metric(upper, digits: digits))" }
        return "Referans aralığı yok"
    }

    private var accessibilityValue: String {
        guard let latest = series.latest else { return "Sonuç yok" }
        var val = "\(ZenithiumFormat.metric(latest.value, digits: series.marker.fractionDigits)) \(latest.unitSymbol)"
        if isOutOfRange {
            val += ", referans aralığı dışında"
        }
        val += ", test tarihi \(latest.drawnAt.formatted(date: .abbreviated, time: .omitted))"
        return val
    }
}

#Preview("Tahlil · dolu") {
    BloodworkPreviewWrapper(state: .dolu)
}

#Preview("Tahlil · kalibrasyon") {
    BloodworkPreviewWrapper(state: .kalibrasyon)
}

#Preview("Tahlil · veri yok") {
    BloodworkPreviewWrapper(state: .veriyok)
}

private struct BloodworkPreviewWrapper: View {
    let state: PreviewState
    @State private var viewModel: BloodworkViewModel?

    var body: some View {
        Group {
            if let viewModel {
                BloodworkView(viewModel: viewModel)
            } else {
                ZenithiumColor.background.ignoresSafeArea()
                    .task {
                        viewModel = await PreviewFixtures.shared.makeBloodworkViewModel(state: state)
                    }
            }
        }
    }
}
