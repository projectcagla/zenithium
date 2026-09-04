//
//  MuscleMapView.swift
//  Zenithium
//
//  The Muscle Map — "what can I train". Spec §1, §5.4, §10.
//
//  Each of the 16 groups is its own accessibility element with a label and a value, and each
//  region carries a readiness percentage in text as well as a fill, so the map is never read
//  by colour alone (ASSUMPTION UI-2).
//

import SwiftUI

struct MuscleMapView: View {

    @State var viewModel: MuscleMapViewModel
    var embedInNavigation: Bool = true
    @State private var isLoggingSession = false

    /// The region a pain entry is being logged for, set by a long press on the map.
    @State private var painTarget: MuscleGroup?

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                mainContent
                    .navigationTitle("Kaslar")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isLoggingSession = true
                            } label: {
                                Label("Seans kaydet", systemImage: "plus")
                            }
                            .accessibilityLabel("Kuvvet seansı kaydet")
                        }
                    }
                    .refreshable { await viewModel.refresh() }
                    .navigationDestination(item: $viewModel.selectedMuscle) { muscle in
                        if let readiness = viewModel.state.value?.readiness(for: muscle) {
                            MuscleDetailView(
                                readiness: readiness,
                                sessions: viewModel.sessions
                            )
                        }
                    }
                    .sheet(isPresented: $isLoggingSession) {
                        StrengthSessionLoggerView(viewModel: viewModel)
                    }
                    .sheet(item: $painTarget) { muscle in
                        PainLoggerView(muscle: muscle) { entry in
                            await viewModel.savePain(entry)
                        }
                    }
            }
            .zenithiumBackground(tint: ZenithiumColor.spectrumAmber, intensity: 0.3)
            .task { await viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
        } else {
            mainContent
                .zenithiumBackground(tint: ZenithiumColor.spectrumAmber, intensity: 0.3)
                .task { await viewModel.onAppear() }
                .onDisappear { viewModel.onDisappear() }
        }
    }

    private var mainContent: some View {
        ScrollView {
            ViewStateContainer(
                state: viewModel.state,
                loadingLabel: "Kas toparlanması yansıtılıyor",
                loadingLayout: .scored,
                actionCallout: "Bir kuvvet antrenmanı tamamlayın.",
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
    }

    @ViewBuilder
    private func loadedBody(_ content: MuscleMapViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.sectionSpacing) {
            // 1. KADEME (KAHRAMAN): İnsan Figürü (Tam Genişlik Kartsız)
            mapSection(content)

            // 2. KADEME: En Çok Yorulan Üç Kas (L1 Sessiz Liste)
            fatiguedMusclesSection(content)

            // TEK L2 KART: Sonraki Seans Önerisi
            recommendationCard(content)

            // KATMAN 4: Tüm Gruplar (L1 SectionBlock)
            listSection(content)

            // KATMAN 5: Ağrı ve Seans Kayıtları (L1 SectionBlock)
            if !viewModel.painInsights.isEmpty || !viewModel.painEntries.isEmpty {
                painSection
            }
            sessionSection
        }
        .padding(.top, ZenithiumSpacing.s)
    }

    // MARK: - 1. KADEME (KAHRAMAN): Anatomik Siluet (Kartsız)

    private func mapSection(_ content: MuscleMapViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.m) {
            Picker("Vücut görünümü", selection: $viewModel.selectedSide) {
                ForEach(BodySide.allCases, id: \.self) { side in
                    Text(side.displayName).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Vücut görünümü")

            BodyMapCanvas(
                side: viewModel.selectedSide,
                content: content,
                hasSessions: !viewModel.sessions.isEmpty,
                onSelect: { viewModel.selectedMuscle = $0 },
                onLogPain: { painTarget = $0 }
            )
            .id(viewModel.selectedSide)
            .aspectRatio(BodyGeometry.aspectRatio, contentMode: .fit)
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.96).combined(with: .opacity),
                removal: .scale(scale: 0.96).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: viewModel.selectedSide)

            readinessLegend
        }
        .frame(maxWidth: .infinity)
    }

    private var readinessLegend: some View {
        HStack(spacing: ZenithiumSpacing.l) {
            ForEach([RecoveryBand.red, .yellow, .green], id: \.self) { band in
                HStack(spacing: ZenithiumSpacing.xs) {
                    Image(systemName: band.symbolName)
                        .imageScale(.small)
                        .foregroundStyle(ZenithiumColor.color(for: band))
                        .accessibilityHidden(true)
                    Text(legendLabel(for: band))
                        .zenithiumCaption()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gösterge: toparlanıyor, orta, hazır")
    }

    private func legendLabel(for band: RecoveryBand) -> String {
        switch band {
        case .red: return "Toparlanıyor"
        case .yellow: return "Orta"
        case .green: return "Hazır"
        }
    }

    // MARK: - 2. KADEME: En Çok Yorulan / Toparlanma Süresi Olan Kaslar (L1)

    private func fatiguedMusclesSection(_ content: MuscleMapViewModel.Content) -> some View {
        let sorted = content.readiness.sorted(by: { $0.readiness < $1.readiness })
        let topFatigued = Array(sorted.prefix(3))

        return VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            Text("EN ÇOK YORULAN GRUPLAR")
                .zenithiumEyebrow()

            VStack(spacing: ZenithiumSpacing.xs) {
                ForEach(topFatigued) { item in
                    HStack(spacing: ZenithiumSpacing.s) {
                        Image(systemName: item.band.symbolName)
                            .foregroundStyle(ZenithiumColor.color(for: item.band))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.muscle.displayName)
                                .zenithiumLabel()

                            if let hours = item.hoursUntilReadiness(90), hours > 0.5 {
                                Text("\(Int(hours.rounded())) sa toparlanma kaldı")
                                    .zenithiumCaption()
                                    .foregroundStyle(ZenithiumColor.textTertiary)
                            }
                        }

                        Spacer()

                        Text("%\(ZenithiumFormat.score(item.readiness))")
                            .sectionTitle()
                            .foregroundStyle(ZenithiumColor.color(for: item.band))
                            .monospacedDigit()

                        Text(item.trainingLabel)
                            .zenithiumCaption()
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                    if item.id != topFatigued.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
            .padding(.vertical, ZenithiumSpacing.xs)
        }
    }

    // MARK: - TEK L2 KART: Sonraki Seans Önerisi

    private func areLegsFatigued(_ readiness: [MuscleReadiness]) -> Bool {
        let legMuscles: Set<MuscleGroup> = [.quads, .hamstrings, .calves]
        for item in readiness {
            if legMuscles.contains(item.muscle) && item.readiness < 70 {
                return true
            }
        }
        return false
    }

    private func isUpperReady(_ readiness: [MuscleReadiness]) -> Bool {
        let upperMuscles: Set<MuscleGroup> = [.chest, .lats, .shoulders]
        for item in readiness {
            if upperMuscles.contains(item.muscle) && item.readiness >= 75 {
                return true
            }
        }
        return false
    }

    private func recommendationCard(_ content: MuscleMapViewModel.Content) -> some View {
        let legsFatigued = areLegsFatigued(content.readiness)
        let upperReady = isUpperReady(content.readiness)

        let adviceTitle: String
        let adviceDetail: String
        if legsFatigued && upperReady {
            adviceTitle = "Bacakları Dinlendir, Üst Gövde Hazır"
            adviceDetail = "Alt ekstremite kas grupları toparlanma fazında. Bugün göğüs, sırt veya omuz odaklı bir üst gövde seansı optimum toparlanma dengesi sağlar."
        } else if legsFatigued {
            adviceTitle = "Aktif Toparlanma veya Dinlenme"
            adviceDetail = "Büyük kas grupları yoğun yorgunluk taşıyor. Hafif aerobik toparlanma veya mobilite çalışması önerilir."
        } else {
            adviceTitle = "Tüm Kas Grupları Dengede"
            adviceDetail = "Kas gruplarında belirgin bir lokal yorgunluk birikimi yok. Planlı kuvvet seansına tam kapasiteyle girilebilir."
        }

        return SectionBlock(
            title: "Sonraki Seans Önerisi",
            subtitle: adviceTitle
        ) {
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 24))
                    .foregroundStyle(ZenithiumColor.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                    Text(adviceDetail)
                        .zenithiumBody()
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Faz 32 — what the pain log has to say about load, and where it stops.
    private var painSection: some View {
        SectionBlock(
            title: "Ağrı Kayıtların",
            subtitle: "Yük ile karşılaştırma — teşhis değil",
            showTopDivider: true
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                ForEach(viewModel.painInsights) { insight in
                    HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                        Image(systemName: insight.hasSevereEntry ? "exclamationmark.circle" : "bandage")
                            .font(.system(size: 13))
                            .foregroundStyle(insight.hasSevereEntry ? ZenithiumColor.yellow : ZenithiumColor.textTertiary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(insight.summary)
                            .zenithiumCallout()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                if !viewModel.painEntries.isEmpty {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        ForEach(viewModel.painEntries) { entry in
                            HStack {
                                Text("\(entry.muscle.displayName): \(entry.severity)/10 — \(entry.quality.displayName)")
                                    .zenithiumCaption()
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await viewModel.deletePain(id: entry.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ZenithiumColor.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(entry.muscle.displayName) ağrı kaydını sil")
                            }
                        }
                    }
                }

                Text("Vücut haritasında bir bölgeye uzun bas, ağrı kaydet.")
                    .zenithiumCaption()
            }
        }
    }

    /// Every one of the 16 groups, reachable via linear list for accessibility.
    private func listSection(_ content: MuscleMapViewModel.Content) -> some View {
        SectionBlock(
            title: "Tüm Kas Grupları",
            subtitle: "16 bölgenin toparlanma dökümü",
            showTopDivider: true
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(content.readiness) { readiness in
                    Button {
                        viewModel.selectedMuscle = readiness.muscle
                    } label: {
                        MuscleRow(readiness: readiness)
                    }
                    .buttonStyle(.plain)

                    if readiness.muscle != MuscleGroup.allCases.last {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }

    private var sessionSection: some View {
        SectionBlock(
            title: "Kaydedilen Seanslar",
            subtitle: "Geçmiş kuvvet çalışmaları",
            showTopDivider: true
        ) {
            if viewModel.sessions.isEmpty {
                Text("Son iki haftada kayıt yok. Kardiyoyu otomatik okuyorum; kuvvet seanslarını neyi çalıştığını bilebilmem için kısaca girmen gerekiyor.")
                    .zenithiumCallout()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: ZenithiumSpacing.none) {
                    ForEach(viewModel.sessions) { session in
                        SessionRow(session: session) {
                            Task { await viewModel.deleteSession(id: session.id) }
                        }
                        if session.id != viewModel.sessions.last?.id {
                            Divider().overlay(ZenithiumColor.hairlineSoft)
                        }
                    }
                }
            }
        }
    }
}

/// The drawn figure. One `Canvas` for the fills, invisible overlays for hit testing and
/// accessibility, so each region is independently focusable.
private struct BodyMapCanvas: View {

    let side: BodySide
    let content: MuscleMapViewModel.Content
    let hasSessions: Bool
    let onSelect: (MuscleGroup) -> Void
    let onLogPain: (MuscleGroup) -> Void

    private var regions: [BodyRegion] { BodyGeometry.regions(for: side) }

    /// Paths are built once per size and shared by the fill, the hit-test overlay and its
    /// content shape — the three callers that previously each rebuilt them. Yol haritası v4, A1.
    @State private var pathCache = BodyPathCache()

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let paths = pathCache.paths(for: regions, in: rect)
            ZStack {
                Canvas { context, _ in
                    // The body silhouette base
                    for path in paths.silhouette {
                        context.fill(path, with: .color(ZenithiumColor.surface))
                        context.stroke(path, with: .color(ZenithiumColor.hairline), lineWidth: 1)
                    }

                    for region in regions {
                        let path = paths.path(for: region)
                        let readiness = content.readiness(for: region.muscle)
                        let band = readiness?.band ?? .yellow
                        let value = readiness?.readiness ?? 0
                        let axis = region.gradientAxis(in: rect)

                        if !hasSessions {
                            // Empty state: neutral wireframe without false green
                            context.fill(path, with: .color(ZenithiumColor.surface.opacity(0.4)))
                            context.stroke(path, with: .color(ZenithiumColor.hairline), lineWidth: 1.0)
                        } else {
                            let tint = ZenithiumColor.color(for: band)
                            let fraction = MathSupport.clamp(value / 100, 0, 1)
                            let intensity = 0.28 + 0.52 * fraction

                            context.fill(
                                path,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        tint.opacity(intensity),
                                        tint.opacity(intensity * 0.58)
                                    ]),
                                    startPoint: axis.start,
                                    endPoint: axis.end
                                )
                            )

                            context.stroke(
                                path,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        tint.opacity(0.95),
                                        tint.opacity(0.35)
                                    ]),
                                    startPoint: axis.start,
                                    endPoint: axis.end
                                ),
                                lineWidth: 1.2
                            )
                        }
                    }
                }
                .accessibilityHidden(true)

                ForEach(regions) { region in
                    let readiness = content.readiness(for: region.muscle)
                    let shape = paths.path(for: region)
                    shape
                        .fill(Color.white.opacity(0.001))
                        .contentShape(shape)
                        .frame(minWidth: 44, minHeight: 44)
                        .onTapGesture { onSelect(region.muscle) }
                        .onLongPressGesture(minimumDuration: 0.45) { onLogPain(region.muscle) }
                        .accessibilityElement()
                        .accessibilityLabel(region.muscle.displayName)
                        .accessibilityValue(accessibilityValue(for: readiness))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("\(region.muscle.displayName) ayrıntısını açar")
                        .accessibilityAction(named: "Ağrı kaydet") { onLogPain(region.muscle) }
                }
            }
        }
    }

    private func accessibilityValue(for readiness: MuscleReadiness?) -> String {
        guard hasSessions, let readiness else { return "Kayıtlı yorgunluk yok" }
        return "%\(ZenithiumFormat.score(readiness.readiness)) hazır, \(readiness.trainingLabel)"
    }
}

/// One row in the all-groups list.
private struct MuscleRow: View {

    let readiness: MuscleReadiness

    var body: some View {
        HStack(spacing: ZenithiumSpacing.m) {
            Image(systemName: readiness.band.symbolName)
                .imageScale(.small)
                .foregroundStyle(ZenithiumColor.color(for: readiness.band))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(readiness.muscle.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(readiness.trainingLabel)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            Spacer(minLength: 8)

            Text(ZenithiumFormat.score(readiness.readiness) + "%")
                .font(ZenithiumFont.callout.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textPrimary)

            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readiness.muscle.displayName)
        .accessibilityValue("yüzde \(ZenithiumFormat.score(readiness.readiness)) hazır, \(readiness.trainingLabel)")
        .accessibilityAddTraits(.isButton)
    }
}

/// One logged strength session.
private struct SessionRow: View {

    let session: StrengthSessionSnapshot
    let delete: () -> Void

    var body: some View {
        HStack(spacing: ZenithiumSpacing.m) {
            Image(systemName: session.pattern.symbolName)
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(session.pattern.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(session.performedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            Spacer(minLength: 8)

            Text("Yük \(ZenithiumFormat.score(session.sessionLoad))")
                .font(ZenithiumFont.caption.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textSecondary)

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ZenithiumColor.red)
            .accessibilityLabel("\(session.pattern.displayName) seansını sil")
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Kas · dolu") {
    MuscleMapPreviewWrapper(state: .dolu)
}

#Preview("Kas · kalibrasyon") {
    MuscleMapPreviewWrapper(state: .kalibrasyon)
}

#Preview("Kas · veri yok") {
    MuscleMapPreviewWrapper(state: .veriyok)
}

private struct MuscleMapPreviewWrapper: View {
    let state: PreviewState
    @State private var viewModel: MuscleMapViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MuscleMapView(viewModel: viewModel)
            } else {
                ZenithiumColor.background.ignoresSafeArea()
                    .task {
                        viewModel = await PreviewFixtures.shared.makeMuscleMapViewModel(state: state)
                    }
            }
        }
    }
}
