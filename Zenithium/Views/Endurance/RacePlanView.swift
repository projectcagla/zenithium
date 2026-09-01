//
//  RacePlanView.swift
//  Zenithium
//
//  Kilometre targets for a real course. Yol haritası v4, C2.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct RacePlanView: View {

    @State private var viewModel: RacePlanViewModel
    @State private var isPickingCourse = false

    init(health: any HealthDataProviding) {
        _viewModel = State(initialValue: RacePlanViewModel(health: health))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.l) {
                courseCard
                if case .loaded(let content) = viewModel.state {
                    targetCard(content)
                    profileCard(content.plan)
                    splitsCard(content.plan)
                    caveatCard
                }
            }
            .padding(.horizontal, ZenithiumSpacing.l)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Yarış temposu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
        .fileImporter(
            isPresented: $isPickingCourse,
            allowedContentTypes: Self.courseTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await viewModel.load(fileURL: url) }
        }
    }

    private var pickerLabel: some View {
        Text(viewModel.loadedCourse == nil ? "GPX seç" : "Başka parkur")
            .font(ZenithiumFont.label)
            .frame(maxWidth: .infinity)
    }

    /// GPX has no registered system type on every install, so the plain XML and data types
    /// are offered alongside it — otherwise a perfectly good course is greyed out in the
    /// picker.
    private static let courseTypes: [UTType] = {
        var types: [UTType] = []
        if let gpx = UTType(filenameExtension: "gpx") { types.append(gpx) }
        types.append(contentsOf: [.xml, .data])
        return types
    }()

    // MARK: - Course

    private var courseCard: some View {
        SectionCard(title: "Parkur", subtitle: viewModel.loadedCourse?.name) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                if let course = viewModel.loadedCourse {
                    MetricTileGrid {
                        MetricTile(
                            label: "Mesafe",
                            value: ZenithiumFormat.metric(course.distance / 1_000, digits: 2),
                            unit: "km",
                            accessibilityLabelText: "Parkur mesafesi"
                        )
                        MetricTile(
                            label: "Toplam tırmanış",
                            value: ZenithiumFormat.metric(course.ascent, digits: 0),
                            unit: "m",
                            accessibilityLabelText: "Toplam tırmanış"
                        )
                        MetricTile(
                            label: "Toplam iniş",
                            value: ZenithiumFormat.metric(course.descent, digits: 0),
                            unit: "m",
                            accessibilityLabelText: "Toplam iniş"
                        )
                    }
                } else {
                    Text("""
                    Yarışın sitesinden indirdiğin GPX dosyasını seç. Zenithium parkurun \
                    eğim profilini okuyup, eşit *efor* için kilometre başına hedef tempo \
                    çıkarır — eşit tempo için değil.
                    """)
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let error = viewModel.importError {
                    Text(error)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: ZenithiumSpacing.m) {
                    // Prominent while there is nothing loaded, quiet once there is: the
                    // button is the whole screen before a course arrives and a secondary
                    // action afterwards.
                    if viewModel.loadedCourse == nil {
                        Button { isPickingCourse = true } label: { pickerLabel }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button { isPickingCourse = true } label: { pickerLabel }
                            .buttonStyle(.bordered)
                    }

                    if viewModel.isReading {
                        ProgressView().tint(ZenithiumColor.accent)
                    }
                }
                .tint(ZenithiumColor.accent)
                .disabled(viewModel.isReading)
            }
        }
    }

    // MARK: - Target

    private func targetCard(_ content: RacePlanViewModel.Content) -> some View {
        SectionCard(title: "Hedef", subtitle: "Bitiş süresi") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(spacing: ZenithiumSpacing.l) {
                    Button {
                        viewModel.adjustTarget(bySeconds: -60)
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 27))
                    }
                    .accessibilityLabel("Hedefi bir dakika kısalt")

                    VStack(spacing: ZenithiumSpacing.xxs) {
                        Text(ZenithiumFormat.longClock(seconds: content.plan.targetFinishSeconds))
                            .font(ZenithiumFont.displayValue.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: content.plan.targetFinishSeconds)
                        Text("ortalama \(ZenithiumFormat.pace(secondsPerKilometre: content.plan.averagePace))")
                            .font(ZenithiumFont.caption.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        viewModel.adjustTarget(bySeconds: 60)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 27))
                    }
                    .accessibilityLabel("Hedefi bir dakika uzat")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ZenithiumColor.accent)
                .sensoryFeedback(.selection, trigger: content.plan.targetFinishSeconds)

                Divider().overlay(ZenithiumColor.hairlineSoft)

                MetricTileGrid {
                    MetricTile(
                        label: "Düz zemin karşılığı",
                        value: ZenithiumFormat.pace(secondsPerKilometre: content.plan.flatEquivalentPace),
                        caption: "Bu eforu düz bir pistte koşsan",
                        accessibilityLabelText: "Düz zemin karşılığı tempo"
                    )
                    MetricTile(
                        label: "Arazi maliyeti",
                        value: ZenithiumFormat.metric((content.plan.terrainCostRatio - 1) * 100, digits: 1),
                        unit: "%",
                        caption: "Aynı uzunlukta düz bir parkura göre",
                        accessibilityLabelText: "Arazinin ek maliyeti"
                    )
                }

                if let suggestion = content.suggestion {
                    suggestionRow(suggestion)
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: (seconds: Double, extrapolation: Double)) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            Text("Son eforlarının işaret ettiği bitiş: \(ZenithiumFormat.longClock(seconds: suggestion.seconds))")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if suggestion.extrapolation > 1.5 {
                // The critical-speed model over-predicts long distances because it has no
                // term for the slow component of oxygen uptake. Saying so is the difference
                // between a model and a promise.
                Text("Bu mesafe modelin ölçtüğü eforlardan \(ZenithiumFormat.metric(suggestion.extrapolation, digits: 1))× uzun — tahmin iyimser olabilir.")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Bu hedefi kullan") { viewModel.useSuggestedTarget() }
                .font(ZenithiumFont.label)
                .buttonStyle(.bordered)
                .tint(ZenithiumColor.accent)
        }
    }

    // MARK: - Profile

    private func profileCard(_ plan: RacePlan) -> some View {
        SectionCard(title: "Yükseklik profili") {
            Chart(plan.course.points, id: \.distance) { point in
                AreaMark(
                    x: .value("Mesafe", point.distance / 1_000),
                    y: .value("Yükseklik", point.elevation)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            ZenithiumColor.spectrumTeal.opacity(0.45),
                            ZenithiumColor.spectrumTeal.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Mesafe", point.distance / 1_000),
                    y: .value("Yükseklik", point.elevation)
                )
                .foregroundStyle(ZenithiumColor.spectrumTeal)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: plan.course.elevationRange ?? 0...1)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairline)
                    AxisValueLabel()
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .font(ZenithiumFont.caption.monospacedDigit())
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(ZenithiumColor.hairline.opacity(0.6))
                    AxisValueLabel {
                        if let kilometre = value.as(Double.self) {
                            Text("\(Int(kilometre.rounded()))K")
                                .foregroundStyle(ZenithiumColor.textTertiary)
                                .font(ZenithiumFont.caption)
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityChartDescriptor(
                SeriesChartDescriptor(
                    title: "Yükseklik profili",
                    seriesName: "Yükseklik",
                    // The descriptor speaks in dates; a course speaks in metres, so the axis
                    // is mapped onto one second per metre. VoiceOver plays the shape, which is
                    // what the chart is for, and the summary carries the real numbers.
                    points: plan.course.points.map {
                        DescribedPoint(
                            date: Date(timeIntervalSince1970: $0.distance),
                            value: $0.elevation
                        )
                    },
                    formatValue: { "\(ZenithiumFormat.metric($0, digits: 0)) metre" },
                    summary: profileSummary(plan)
                )
            )
            .accessibilityLabel("Parkurun yükseklik profili")
            .accessibilityValue(profileSummary(plan))
        }
    }

    private func profileSummary(_ plan: RacePlan) -> String {
        let distance = ZenithiumFormat.metric(plan.course.distance / 1_000, digits: 1)
        let ascent = ZenithiumFormat.metric(plan.course.ascent, digits: 0)
        let descent = ZenithiumFormat.metric(plan.course.descent, digits: 0)
        return "\(distance) kilometre, \(ascent) metre tırmanış, \(descent) metre iniş."
    }

    // MARK: - Splits

    private func splitsCard(_ plan: RacePlan) -> some View {
        SectionCard(title: "Kilometre hedefleri", subtitle: "Eşit efor, değişen tempo") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(plan.splits) { split in
                    SplitRow(split: split, flatPace: plan.flatEquivalentPace)
                    if split.id != plan.splits.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }

    // MARK: - Caveat

    private var caveatCard: some View {
        SectionCard {
            Text("""
            Bu plan yalnızca zemini hesaba katar. Sıcak, rakım, rüzgâr, kalabalık ilk \
            kilometre ve o günkü hâlin burada yok — plan bir başlangıç noktası, bir söz değil.
            """)
            .font(ZenithiumFont.caption)
            .foregroundStyle(ZenithiumColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One kilometre's row: its climb, its target and the clock at the end of it.
private struct SplitRow: View {

    let split: RaceSplit
    let flatPace: Double

    var body: some View {
        HStack(spacing: ZenithiumSpacing.m) {
            Text("\(split.index)")
                .font(ZenithiumFont.dataValue.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(width: 26, alignment: .trailing)

            gradientChip

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(ZenithiumFormat.pace(secondsPerKilometre: split.targetPace))
                    .font(ZenithiumFont.headline.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(deltaText)
                    .font(ZenithiumFont.caption2.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }

            Spacer(minLength: 0)

            Text(ZenithiumFormat.longClock(seconds: split.elapsedSeconds))
                .font(ZenithiumFont.dataValue.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .padding(.vertical, ZenithiumSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilometre \(split.index)")
        .accessibilityValue(accessibilityValue)
    }

    private var gradientChip: some View {
        Text(gradientText)
            .font(ZenithiumFont.caption2.monospacedDigit())
            .foregroundStyle(gradientTint)
            .padding(.horizontal, ZenithiumSpacing.s)
            .padding(.vertical, ZenithiumSpacing.xxs)
            .background {
                Capsule().fill(gradientTint.opacity(0.14))
            }
            .frame(width: 58)
    }

    private var gradientText: String {
        let percent = split.gradient * 100
        return "\(percent >= 0 ? "+" : "")\(ZenithiumFormat.metric(percent, digits: 1))%"
    }

    /// Colour by steepness, not by good or bad: a climb and a descent are both work.
    private var gradientTint: Color {
        let magnitude = abs(split.gradient)
        if magnitude < 0.01 { return ZenithiumColor.textTertiary }
        if split.gradient > 0 { return ZenithiumColor.spectrumAmber }
        return ZenithiumColor.spectrumTeal
    }

    private var deltaText: String {
        let delta = split.deltaFromFlat(flatPace)
        guard abs(delta) >= 1 else { return "düz zemin temposu" }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(ZenithiumFormat.clock(seconds: abs(delta))) düze göre"
    }

    private var accessibilityValue: String {
        let pace = ZenithiumFormat.pace(secondsPerKilometre: split.targetPace)
        let elapsed = ZenithiumFormat.longClock(seconds: split.elapsedSeconds)
        return "\(gradientText) eğim, hedef \(pace), bitişte \(elapsed)"
    }
}
