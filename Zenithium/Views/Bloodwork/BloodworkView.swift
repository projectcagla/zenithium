//
//  BloodworkView.swift
//  Zenithium
//
//  The Bloodwork screen. Spec §12 & Design Specification.
//  Kahraman: Sakin bir liste (L1, kartsız). Renk YALNIZCA referans dışı değerde.
//  Normal değerler sessiz gri. Her satırda: belirteç adı, değer, birim, referans aralığı, son test tarihi.
//  Tek L2: Aksiyon gerektiren bulgular özeti (varsa — yoksa tek bir sessiz L1 satır).
//

import SwiftUI

struct BloodworkView: View {

    @State var viewModel: BloodworkViewModel
    var embedInNavigation: Bool = true
    @State private var isAddingEntry = false
    @State private var isImportingReport = false

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
                                    Label("PDF tahlil sonucu içe aktar", systemImage: "doc.text.viewfinder")
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
                    .sheet(isPresented: $isImportingReport) {
                        LabImportView(repository: viewModel.markerRepository) {
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
            // TEK L2 KART: Aksiyon Gerektiren Bulgular Özeti
            actionableFindingsSection(content.observations)

            // KAHRAMAN: Sakin Tahlil Listesi (L1 SectionBlock)
            ForEach(content.panels) { group in
                panelBlock(title: group.panel.displayName, series: group.series)
            }

            let ungrouped = content.series.filter { $0.marker.panel == nil }
            if !ungrouped.isEmpty {
                panelBlock(title: "Diğer Belirteçler", series: ungrouped)
            }
        }
    }

    // MARK: - TEK L2 KART / SESSİZ L1 SATIR: Aksiyon Gerektiren Bulgular

    @ViewBuilder
    private func actionableFindingsSection(_ observations: [LabObservation]) -> some View {
        let actionable = observations.filter(\.requiresClinician)

        if !actionable.isEmpty {
            SectionCard(
                title: "Aksiyon Gerektiren Bulgular",
                subtitle: "Referans aralığı dışı gözlemler — teşhis değil"
            ) {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    ForEach(actionable) { observation in
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(ZenithiumColor.yellow)
                                    .accessibilityHidden(true)
                                Text(observation.message)
                                    .zenithiumBody()
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if observation.requiresClinician {
                                Text(SafetyCopy.clinicianPrompt)
                                    .zenithiumCaption()
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                }
            }
        } else {
            // Hiç referans dışı bulgu yoksa tek bir sessiz L1 satırı
            HStack(spacing: ZenithiumSpacing.s) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(ZenithiumColor.green)
                    .accessibilityHidden(true)
                Text("Tüm belirteçler referans aralığında")
                    .zenithiumBody()
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Spacer()
            }
            .padding(.vertical, ZenithiumSpacing.xs)
            .padding(.horizontal, ZenithiumSpacing.xs)
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
        HStack(alignment: .center, spacing: ZenithiumSpacing.m) {
            // Sol Taraf: Belirteç Adı + Referans Aralığı ve Tarih
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(series.marker.displayName)
                    .zenithiumLabel()
                    .foregroundStyle(ZenithiumColor.textPrimary)

                HStack(spacing: ZenithiumSpacing.xs) {
                    if let latest = series.latest {
                        let range = latest.referenceRange
                        if let minVal = range.minimum, let maxVal = range.maximum {
                            Text("Ref: \(ZenithiumFormat.metric(minVal, digits: series.marker.fractionDigits))–\(ZenithiumFormat.metric(maxVal, digits: series.marker.fractionDigits)) \(latest.unitSymbol)")
                                .zenithiumCaption()
                                .monospacedDigit()
                        } else if let minVal = range.minimum {
                            Text("Ref: >\(ZenithiumFormat.metric(minVal, digits: series.marker.fractionDigits)) \(latest.unitSymbol)")
                                .zenithiumCaption()
                                .monospacedDigit()
                        } else if let maxVal = range.maximum {
                            Text("Ref: <\(ZenithiumFormat.metric(maxVal, digits: series.marker.fractionDigits)) \(latest.unitSymbol)")
                                .zenithiumCaption()
                                .monospacedDigit()
                        }
                        Text("·")
                            .zenithiumCaption()
                        Text(latest.drawnAt.formatted(date: .abbreviated, time: .omitted))
                            .zenithiumCaption()
                    } else {
                        Text("Kayıt yok")
                            .zenithiumCaption()
                    }
                }
            }

            Spacer(minLength: 8)

            // Sağ Taraf: Değer ve Birim (Referans dışı ise kehribar/kırmızı renkli)
            if let latest = series.latest {
                VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xxs) {
                        Text(ZenithiumFormat.metric(latest.value, digits: series.marker.fractionDigits))
                            .sectionTitle()
                            .foregroundStyle(valueColor)
                            .monospacedDigit()
                        Text(latest.unitSymbol)
                            .metricUnit()
                            .foregroundStyle(isOutOfRange ? valueColor : ZenithiumColor.textSecondary)
                    }

                    if isOutOfRange {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(valueColor)
                            Text("Aralık Dışı")
                                .zenithiumEyebrow()
                                .foregroundStyle(valueColor)
                        }
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenithiumColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ZenithiumSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.marker.accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
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
