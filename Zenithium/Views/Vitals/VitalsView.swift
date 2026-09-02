//
//  VitalsView.swift
//  Zenithium
//
//  The vitals screen. Faz 11, Faz 28.
//
//  Eighteen signals is a lot of rows, so the screen leads with the one thing that could
//  change someone's day — whether this morning sits outside their recent range — and then
//  lists everything else grouped, each row carrying its own sparkline and a plain sentence
//  about where it sits.
//

import SwiftUI

struct VitalsView: View {

    @State var viewModel: VitalsViewModel
    @State private var expanded: VitalSign?
    @ScaledMetric(relativeTo: .body) private var ledgerHeight: CGFloat = 64

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Sağlık ölçümleri okunuyor",
                    loadingLayout: .chart,
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Sağlık")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.load() }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumTeal, intensity: 0.3)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: VitalsViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if let summary = content.deviationSummary {
                deviationCard(summary: summary, score: content.deviation)
            }

            if let shift = content.timeZoneShift {
                contextCard(symbol: "airplane", text: shift.summary, tint: ZenithiumColor.spectrumIndigo)
            }

            if let longevity = content.longevity {
                longevityCard(longevity)
            }

            if let daylight = content.daylight.summary {
                contextCard(symbol: "sun.max", text: daylight, tint: ZenithiumColor.spectrumAmber)
            }

            sleepDebtCard(content)

            if let norm = content.vo2MaxNorm {
                normCard(norm)
            }

            ForEach(content.groups, id: \.category) { group in
                SectionCard(title: group.category.displayName) {
                    VStack(spacing: ZenithiumSpacing.none) {
                        ForEach(group.readings) { reading in
                            VitalRow(
                                reading: reading,
                                isExpanded: expanded == reading.sign
                            ) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    expanded = expanded == reading.sign ? nil : reading.sign
                                }
                            }
                            if reading.id != group.readings.last?.id {
                                Divider().overlay(ZenithiumColor.hairlineSoft)
                            }
                        }
                    }
                }
            }

            if !content.missing.isEmpty {
                missingCard(content.missing)
            }

            Text(SafetyCopy.disclaimerFooter)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Deviation

    /// Faz 28's whole output, and the §12 line drawn around it.
    ///
    /// The card names which signals moved and how far, then hands the question to the
    /// person and their clinician. It does not say what the pattern means, because it does
    /// not know — several very ordinary things produce it.
    private func deviationCard(summary: String, score: DeviationScore) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(spacing: ZenithiumSpacing.s) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(ZenithiumColor.yellow)
                        .accessibilityHidden(true)
                    Text("Biyometrik Sapma Tespiti")
                        .font(ZenithiumFont.sectionTitle)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Spacer(minLength: 0)
                    Text(score.level.displayName)
                        .font(ZenithiumFont.caption)
                        .padding(.horizontal, ZenithiumSpacing.s)
                        .padding(.vertical, ZenithiumSpacing.xxs)
                        .background(Capsule().fill(ZenithiumColor.yellow.opacity(0.18)))
                        .foregroundStyle(ZenithiumColor.yellow)
                }

                Text(summary)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    ForEach(score.contributors.filter { $0.orientedZ >= 1.0 }) { contributor in
                        HStack {
                            Text(contributor.sign.displayName)
                                .font(ZenithiumFont.footnote)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                            Spacer()
                            Text("\(ZenithiumFormat.signed(contributor.zScore, digits: 1))σ")
                                .font(ZenithiumFont.footnote.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Longevity

    /// Faz 29 — the composite, always shown with its parts.
    ///
    /// The breakdown is not an optional disclosure. A single number that moves over months
    /// is exactly the kind of thing users start trusting without knowing what it contains,
    /// so the components, their weights and their contributions are on the same card.
    private func longevityCard(_ score: LongevityScore) -> some View {
        SectionCard(title: "Zenithium İndeksi", subtitle: "Bireysel geçmişe dayalı uzun vadeli eğilim") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.m) {
                    Text(ZenithiumFormat.score(score.score))
                        .font(ZenithiumFont.arcValue(size: 42))
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    if let change = score.monthlyChange, abs(change) >= 0.5 {
                        Text("\(ZenithiumFormat.signed(change, digits: 1))/ay")
                            .font(ZenithiumFont.caption.monospacedDigit())
                            .foregroundStyle(change > 0 ? ZenithiumColor.green : ZenithiumColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                Text(score.summary)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(ZenithiumColor.hairlineSoft)

                VStack(spacing: ZenithiumSpacing.s) {
                    ForEach(score.components) { component in
                        LongevityRow(component: component)
                    }
                }

                Text("Bu değer tıbbi bir teşhis değildir; kardiyovasküler ve toparlanma eğilimlerinizin ağırlıklı bileşik indeksidir.")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zenithium skoru")
        .accessibilityValue(score.summary)
    }

    /// A one-line context card — daylight, a time-zone change.
    /// Where VO₂max sits against a published reference band. Yol haritası v4, C11.
    ///
    /// The one place in the app that compares somebody to other people rather than to their
    /// own history. It says where the reading sits and stops there — §12 rules out reading a
    /// verdict into a percentile, and the copy is written so none can be.
    private func normCard(_ norm: NormPosition) -> some View {
        SectionCard(title: "VO₂max — referans", subtitle: "Yayımlanmış yaş ve cinsiyet bandı") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ZenithiumColor.surfaceElevated)
                            .frame(height: 10)
                        // The interquartile band, so the middle half of the reference group
                        // is visible as a region rather than implied by three numbers.
                        Capsule()
                            .fill(ZenithiumColor.accent.opacity(0.22))
                            .frame(width: width * 0.5, height: 10)
                            .offset(x: width * 0.25)
                        Capsule()
                            .fill(ZenithiumColor.textPrimary)
                            .frame(width: 3, height: 20)
                            .offset(x: max(0, min(width - 3, width * norm.approximatePercentile)))
                    }
                    .frame(height: 20)
                }
                .frame(height: 20)
                .accessibilityHidden(true)

                HStack {
                    Text("%25")
                    Spacer()
                    Text("ortanca")
                    Spacer()
                    Text("%75")
                }
                .font(ZenithiumFont.caption2.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textTertiary)

                MetricTileGrid {
                    MetricTile(
                        label: "Senin",
                        value: ZenithiumFormat.metric(norm.value, digits: 1),
                        unit: "mL/kg/dk",
                        accessibilityLabelText: "Senin VO₂max değerin"
                    )
                    MetricTile(
                        label: "Grup ortancası",
                        value: ZenithiumFormat.metric(norm.median, digits: 1),
                        unit: "mL/kg/dk",
                        accessibilityLabelText: "Referans grubun ortancası"
                    )
                }

                Text(norm.summary)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("VO₂max referans konumu")
            .accessibilityValue(norm.summary)
        }
    }

    /// Sleep owed, and how far the clock drifts at the weekend. Yol haritası v4, C4.
    ///
    /// Two numbers and their nightly bars. §1 rules out the obvious next sentence — this
    /// says how many hours, and never when to go to bed.
    @ViewBuilder
    private func sleepDebtCard(_ content: VitalsViewModel.Content) -> some View {
        let ledger = content.sleepDebt
        if ledger.nights > 0 {
            SectionCard(title: "Uyku defteri", subtitle: "Son \(ledger.windowDays) gün") {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xs) {
                        Text(ZenithiumFormat.metric(ledger.hours, digits: 1))
                            .font(ZenithiumFont.displayValue.monospacedDigit())
                            .foregroundStyle(
                                ledger.hours >= 1 ? ZenithiumColor.spectrumAmber : ZenithiumColor.textPrimary
                            )
                            .contentTransition(.numericText())
                            .animation(.snappy, value: ledger.hours)
                        Text("saat")
                            .font(ZenithiumFont.unit)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Birikmiş uyku")
                    .accessibilityValue("\(ZenithiumFormat.metric(ledger.hours, digits: 1)) saat")

                    Text(SleepDebtEngine.summary(for: ledger))
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if ledger.isReliable {
                        nightlyBars(ledger)
                    }

                    if let jetlag = content.socialJetlag {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                        HStack(spacing: ZenithiumSpacing.s) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .foregroundStyle(ZenithiumColor.spectrumViolet)
                                .accessibilityHidden(true)
                            Text(SleepDebtEngine.summary(for: jetlag))
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Hafta sonu uyku kayması")
                    }
                }
            }
        }
    }

    /// One bar per night: below the line is a shortfall, above it a surplus.
    private func nightlyBars(_ ledger: SleepDebtLedger) -> some View {
        let extent = max(
            2,
            ledger.nightly.map { abs($0.shortfallHours) }.max() ?? 2
        )
        return HStack(alignment: .center, spacing: ZenithiumSpacing.xxs) {
            ForEach(ledger.nightly) { night in
                VStack(spacing: ZenithiumSpacing.none) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: barHeight(for: max(0, -night.shortfallHours), extent: extent))
                    Rectangle()
                        .fill(ZenithiumColor.spectrumTeal.opacity(0.8))
                        .frame(height: barHeight(for: max(0, -night.shortfallHours), extent: extent))
                    Rectangle()
                        .fill(ZenithiumColor.hairline)
                        .frame(height: 1)
                    Rectangle()
                        .fill(ZenithiumColor.spectrumAmber.opacity(0.8))
                        .frame(height: barHeight(for: max(0, night.shortfallHours), extent: extent))
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: barHeight(for: max(0, night.shortfallHours), extent: extent))
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: ZenithiumRadius.small, style: .continuous))
            }
        }
        // Saf çizim (Haftalık borç grafiği): @ScaledMetric ile minHeight kullanılır.
        .frame(minHeight: ledgerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gecelik eksik ve fazla uyku")
        .accessibilityValue(nightlyAccessibilityValue(ledger))
    }

    private func barHeight(for hours: Double, extent: Double) -> CGFloat {
        // Half the well is 30pt, so a full-extent night fills its side exactly.
        CGFloat(min(1, hours / extent) * 30)
    }

    private func nightlyAccessibilityValue(_ ledger: SleepDebtLedger) -> String {
        let short = ledger.nightly.filter { $0.shortfallHours > 0.25 }.count
        let over = ledger.nightly.filter { $0.shortfallHours < -0.25 }.count
        return "\(ledger.nights) gecenin \(short)'inde ihtiyacın altında, \(over)'inde üstünde uyudun."
    }

    private func contextCard(symbol: String, text: String, tint: Color) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(text)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Missing

    private func missingCard(_ missing: [VitalSign]) -> some View {
        SectionCard(title: "Veri gelmeyenler", subtitle: "Bunlar boş, çünkü kayıt bulunamadı") {
            Text(missing.map(\.displayName).joined(separator: " · "))
                .font(ZenithiumFont.footnote)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One vital sign's row: value, where it sits, and a sparkline. Tapping opens the
/// explanation, because half of these are signals nobody has been told the meaning of.
private struct VitalRow: View {

    let reading: VitalReading
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: ZenithiumSpacing.m) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text(reading.sign.displayName)
                            .font(ZenithiumFont.headline)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        if let label = reading.deviationLabel {
                            Text(label)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }

                    Spacer(minLength: 8)

                    Sparkline(values: reading.history.map(\.value), tint: ZenithiumColor.accent)
                        .frame(width: 56, height: 22)
                        .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xs) {
                        Text(valueText)
                            .font(ZenithiumFont.body.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        if !reading.sign.unitSymbol.isEmpty {
                            Text(reading.sign.unitSymbol)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(reading.sign.explanation)
                    .font(ZenithiumFont.footnote)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if reading.sign.isDisplayOnly {
                    Text("Bu değer yalnızca gösterilir; Zenithium onu yorumlamaz.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }
        }
        .padding(.vertical, ZenithiumSpacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reading.sign.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(reading.sign.explanation)
    }

    private var valueText: String {
        guard let latest = reading.latest else { return "—" }
        return ZenithiumFormat.metric(latest.value, digits: reading.sign.fractionDigits)
    }

    private var accessibilityValue: String {
        guard reading.latest != nil else { return "Veri yok" }
        var spoken = "\(valueText) \(reading.sign.unitSymbol)"
        if let label = reading.deviationLabel { spoken += ", \(label)" }
        return spoken
    }
}


/// One pillar of the composite, with what it contributed.
private struct LongevityRow: View {

    let component: LongevityComponent

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            HStack {
                Text(component.pillar.displayName)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Spacer()
                Text(ZenithiumFormat.score(component.score))
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Text(ZenithiumFormat.percentTR(component.pillar.weight))
                    .font(ZenithiumFont.caption2.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairlineSoft)
                    Capsule()
                        .fill(ZenithiumColor.accent.opacity(0.65))
                        .frame(width: max(2, proxy.size.width * CGFloat(component.score / 100)))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(component.pillar.displayName)
        .accessibilityValue("\(ZenithiumFormat.score(component.score)) puan, ağırlık \(ZenithiumFormat.percentTR(component.pillar.weight)). \(component.pillar.rationale)")
    }
}
