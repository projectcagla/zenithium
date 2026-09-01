//
//  BloodworkView.swift
//  Zenithium
//
//  The Bloodwork screen. Spec §12 governs this file completely: reference ranges and trends
//  only. Nothing here interprets a value, flags one, or suggests anything about it. There is
//  no "good"/"bad" colour, no arrow that means improvement, and no advice.
//

import SwiftUI

struct BloodworkView: View {

    @State var viewModel: BloodworkViewModel
    @State private var isAddingEntry = false
    @State private var isImportingReport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ZenithiumSpacing.l) {
                    disclaimerCard
                    ViewStateContainer(
                        state: viewModel.state,
                        loadingLabel: "Sonuçlar yükleniyor",
                        retry: { await viewModel.load() },
                        requestAccess: nil
                    ) { content in
                        loadedBody(content)
                    }
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Kan değerleri")
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
    }

    private var disclaimerCard: some View {
        SectionCard {
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                Image(systemName: "info.circle")
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .accessibilityHidden(true)
                Text(SafetyCopy.bloodworkDisclaimer)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func loadedBody(_ content: BloodworkViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if !content.observations.isEmpty {
                observationsCard(content.observations)
            }

            // Grouped by panel where the catalogue knows the marker, so the screen is
            // organised the way a laboratory report is. Anything the catalogue does not
            // recognise still appears, under its own heading rather than under a guess.
            // Yol haritası v4, C3.
            ForEach(content.panels) { group in
                panelSection(title: group.panel.displayName, series: group.series)
            }

            let ungrouped = content.series.filter { $0.marker.panel == nil }
            if !ungrouped.isEmpty {
                panelSection(title: "Diğer", series: ungrouped)
            }
        }
    }

    @ViewBuilder
    private func panelSection(title: String, series: [BloodworkViewModel.MarkerSeries]) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            Text(title)
                .font(ZenithiumFont.eyebrow)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, ZenithiumSpacing.xs)
                .accessibilityAddTraits(.isHeader)

            ForEach(series) { entry in
                NavigationLink {
                    BloodMarkerDetailView(series: entry, viewModel: viewModel)
                } label: {
                    MarkerSummaryCard(series: entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// What the panel says about itself.
    ///
    /// §12 in one view: nothing here names a condition or suggests a treatment. Values
    /// outside a reference band get one response and only one — the clinician prompt — and
    /// it is attached to the row itself rather than buried in a footer, so the two can
    /// never be read apart.
    private func observationsCard(_ observations: [LabObservation]) -> some View {
        SectionCard(title: "Panelin hakkında", subtitle: "Gözlem — teşhis değil") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                ForEach(observations) { observation in
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                        HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                            Image(systemName: symbol(for: observation.kind))
                                .font(.system(size: 13))
                                .foregroundStyle(tint(for: observation))
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(observation.message)
                                .font(ZenithiumFont.callout)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if observation.requiresClinician {
                            Text(SafetyCopy.clinicianPrompt)
                                .font(ZenithiumFont.footnote)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                                .padding(.leading, ZenithiumSpacing.xl)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func symbol(for kind: LabObservationKind) -> String {
        switch kind {
        case .outsideReference: return "exclamationmark.circle"
        case .outsideOptimal: return "circle.lefthalf.filled"
        case .movement: return "arrow.up.arrow.down"
        case .aging: return "clock"
        case .panelGap: return "square.dashed"
        case .timingCaveat: return "figure.run"
        case .context: return "text.book.closed"
        }
    }

    private func tint(for observation: LabObservation) -> Color {
        observation.requiresClinician ? ZenithiumColor.yellow : ZenithiumColor.textTertiary
    }
}

/// One marker's latest value with its range position. A position, not a verdict (§12).
struct MarkerSummaryCard: View {

    let series: BloodworkViewModel.MarkerSeries

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                    Text(series.marker.displayName)
                        .font(ZenithiumFont.sectionTitle)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Spacer(minLength: 8)
                    if let latest = series.latest {
                        Text(ZenithiumFormat.metric(latest.value, digits: series.marker.fractionDigits))
                            .font(ZenithiumFont.metricValue)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text(latest.unitSymbol)
                            .font(ZenithiumFont.unit)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }

                if let latest = series.latest {
                    RangeBar(entry: latest)

                    // How fast, over the whole history rather than between the last two
                    // draws — and still only a number (§12). Yol haritası v4, C3.
                    if let rate = series.annualRate {
                        Text("Yılda \(ZenithiumFormat.signed(rate, digits: series.marker.fractionDigits)) \(latest.unitSymbol)")
                            .font(ZenithiumFont.caption.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textSecondary)
                            .accessibilityLabel("Yıllık değişim hızı")
                            .accessibilityValue("\(ZenithiumFormat.signed(rate, digits: series.marker.fractionDigits)) \(latest.unitSymbol) yılda")
                    }

                    HStack(spacing: ZenithiumSpacing.s) {
                        Text(latest.drawnAt.formatted(date: .abbreviated, time: .omitted))
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)

                        if let change = series.changeSincePrevious, series.entries.count >= 2 {
                            // A number and a direction. Not a judgement (§12).
                            Text("\(ZenithiumFormat.signed(change, digits: series.marker.fractionDigits)) önceki ölçüme göre")
                                .font(ZenithiumFont.caption.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.marker.accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tüm geçmişi açar")
    }

    private var accessibilityValue: String {
        guard let latest = series.latest else { return "Sonuç yok" }
        var value = "\(ZenithiumFormat.metric(latest.value, digits: series.marker.fractionDigits)) \(latest.unitSymbol), drawn \(latest.drawnAt.formatted(date: .abbreviated, time: .omitted))"
        let range = latest.referenceRange
        if let minimum = range.minimum, let maximum = range.maximum {
            value += ". Reference range \(ZenithiumFormat.metric(minimum, digits: series.marker.fractionDigits)) to \(ZenithiumFormat.metric(maximum, digits: series.marker.fractionDigits))"
        }
        return value
    }
}

/// The value's position across the reference range, with the optimal band marked.
///
/// The bar is deliberately monochrome: colouring it by position would be an interpretation,
/// which §12 forbids.
struct RangeBar: View {

    let entry: BloodMarkerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenithiumColor.hairline)

                    if let optimal = optimalFraction {
                        Capsule()
                            .fill(ZenithiumColor.textSecondary.opacity(0.30))
                            .frame(
                                width: max(proxy.size.width * (optimal.upper - optimal.lower), 2)
                            )
                            .offset(x: proxy.size.width * optimal.lower)
                    }

                    if let position = entry.positionInReferenceRange {
                        Circle()
                            .fill(ZenithiumColor.textPrimary)
                            .frame(width: 10, height: 10)
                            .offset(x: proxy.size.width * position - 5)
                    }
                }
            }
            .frame(height: 10)

            HStack {
                if let minimum = entry.referenceRange.minimum {
                    Text(ZenithiumFormat.metric(minimum, digits: 0))
                        .font(ZenithiumFont.caption.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
                Spacer(minLength: 0)
                Text(SafetyCopy.bloodworkRangeCaption)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let maximum = entry.referenceRange.maximum {
                    Text(ZenithiumFormat.metric(maximum, digits: 0))
                        .font(ZenithiumFont.caption.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Where the optimal band sits inside the reference range, as 0…1 fractions.
    private var optimalFraction: (lower: Double, upper: Double)? {
        let reference = entry.referenceRange
        let optimal = entry.optimalRange
        guard let refMin = reference.minimum,
              let refMax = reference.maximum,
              refMax > refMin,
              let optMin = optimal.minimum,
              let optMax = optimal.maximum else { return nil }
        let span = refMax - refMin
        let lower = MathSupport.clamp((optMin - refMin) / span, 0, 1)
        let upper = MathSupport.clamp((optMax - refMin) / span, 0, 1)
        guard upper > lower else { return nil }
        return (lower, upper)
    }
}
