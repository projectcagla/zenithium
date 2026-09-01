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
    @State private var isLoggingSession = false

    /// The region a pain entry is being logged for, set by a long press on the map.
    @State private var painTarget: MuscleGroup?

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Kas toparlanması yansıtılıyor",
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
    }

    @ViewBuilder
    private func loadedBody(_ content: MuscleMapViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            summarySection(content)
            mapSection(content)
            if !viewModel.painInsights.isEmpty {
                painSection
            }
            listSection(content)
            sessionSection
        }
        .padding(.top, ZenithiumSpacing.s)
    }

    /// Faz 32 — what the pain log has to say about load, and where it stops.
    ///
    /// Entries at or above the clinician threshold replace the load sentence entirely rather
    /// than sitting beside it. Offering "your Tuesday tempo run was heavier" next to an 8/10
    /// sharp pain would be a distraction from the only sentence that belongs there.
    private var painSection: some View {
        SectionCard(title: "Ağrı kayıtların", subtitle: "Yük ile karşılaştırma — teşhis değil") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                ForEach(viewModel.painInsights) { insight in
                    HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                        Image(systemName: insight.hasSevereEntry ? "exclamationmark.circle" : "bandage")
                            .font(.system(size: 13))
                            .foregroundStyle(insight.hasSevereEntry ? ZenithiumColor.yellow : ZenithiumColor.textTertiary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(insight.summary)
                            .font(ZenithiumFont.callout)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Vücut haritasında bir bölgeye uzun bas, ağrı kaydet.")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
        }
    }

    private func summarySection(_ content: MuscleMapViewModel.Content) -> some View {
        SectionCard(title: viewModel.sessions.isEmpty ? "Kas toparlanma durumu" : "Çalışmaya hazır") {
            if viewModel.sessions.isEmpty {
                HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 24))
                        .foregroundStyle(ZenithiumColor.spectrumAmber)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text("Kayıtlı Yorgunluk Yok")
                            .font(ZenithiumFont.headline)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text("Kuvvet seansı kaydettikçe kas gruplarının biyolojik yarı ömürlü toparlanma süreci burada izlenecektir.")
                            .font(ZenithiumFont.callout)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }
                .padding(.vertical, ZenithiumSpacing.xs)
            } else {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    ForEach(content.mostReady) { readiness in
                        HStack(spacing: ZenithiumSpacing.s) {
                            Image(systemName: readiness.band.symbolName)
                                .foregroundStyle(ZenithiumColor.color(for: readiness.band))
                                .accessibilityHidden(true)
                            Text(readiness.muscle.displayName)
                                .font(ZenithiumFont.label)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Spacer(minLength: 8)
                            Text(ZenithiumFormat.score(readiness.readiness) + "%")
                                .font(ZenithiumFont.callout.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(readiness.muscle.displayName)
                        .accessibilityValue("yüzde \(ZenithiumFormat.score(readiness.readiness)) hazır, \(readiness.trainingLabel)")
                    }
                }
            }
        }
    }

    private func mapSection(_ content: MuscleMapViewModel.Content) -> some View {
        SectionCard {
            VStack(spacing: ZenithiumSpacing.l) {
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
                .aspectRatio(BodyGeometry.aspectRatio, contentMode: .fit)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)

                readinessLegend
            }
        }
    }

    /// The colour scale, stated in words as well as swatches.
    private var readinessLegend: some View {
        HStack(spacing: ZenithiumSpacing.l) {
            ForEach([RecoveryBand.red, .yellow, .green], id: \.self) { band in
                HStack(spacing: ZenithiumSpacing.xs) {
                    Image(systemName: band.symbolName)
                        .imageScale(.small)
                        .foregroundStyle(ZenithiumColor.color(for: band))
                        .accessibilityHidden(true)
                    Text(legendLabel(for: band))
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textSecondary)
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

    /// Every one of the 16 groups, so a group not drawn on the current view is still
    /// reachable — and so VoiceOver has a linear list rather than only a canvas.
    private func listSection(_ content: MuscleMapViewModel.Content) -> some View {
        SectionCard(title: "Tüm gruplar") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(content.readiness) { readiness in
                    Button {
                        viewModel.selectedMuscle = readiness.muscle
                    } label: {
                        MuscleRow(readiness: readiness)
                    }
                    .buttonStyle(.plain)

                    if readiness.muscle != MuscleGroup.allCases.last {
                        Divider().overlay(ZenithiumColor.hairline)
                    }
                }
            }
        }
    }

    private var sessionSection: some View {
        SectionCard(
            title: "Kaydedilen seanslar",
            subtitle: "Saatinden okuyamadığım kuvvet çalışmaları"
        ) {
            if viewModel.sessions.isEmpty {
                Text("Son iki haftada kayıt yok. Kardiyoyu otomatik okuyorum; kuvvet seanslarını neyi çalıştığını bilebilmem için kısaca girmen gerekiyor.")
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: ZenithiumSpacing.none) {
                    ForEach(viewModel.sessions) { session in
                        SessionRow(session: session) {
                            Task { await viewModel.deleteSession(id: session.id) }
                        }
                        if session.id != viewModel.sessions.last?.id {
                            Divider().overlay(ZenithiumColor.hairline)
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
