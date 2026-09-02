//
//  DecisionTraceCard.swift
//  Zenithium
//
//  Renders deterministic athletic decision traces, confidence scores, and evidence graphs
//  directly on the Today screen. Spec §1, Epistemic Decision Layer.
//

import SwiftUI

struct DecisionTraceCard: View {

    let result: EngineResult<AthleticDecision>
    var wrappedInCard: Bool = false
    @State private var isTraceExpanded = false

    var body: some View {
        if wrappedInCard {
            SectionCard {
                traceContent
            }
        } else {
            traceContent
        }
    }

    private var traceContent: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            // Suggested Activities
            if !result.value.suggestedActivities.isEmpty {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                    Text("Önerilen Egzersizler")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ZenithiumSpacing.xs) {
                            ForEach(result.value.suggestedActivities, id: \.self) { activity in
                                HStack(spacing: 4) {
                                    Image(systemName: activity.symbolName)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(activity.displayName)
                                        .font(ZenithiumFont.caption)
                                }
                                .padding(.horizontal, ZenithiumSpacing.s)
                                .padding(.vertical, 4)
                                .background(ZenithiumColor.surfaceElevated)
                                .clipShape(Capsule())
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }

            // Epistemic Decision Trace Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isTraceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.spectrumViolet)
                    Text("Deterministik Karar İzi (7 Adımlı Kanıt Zinciri)")
                        .font(ZenithiumFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Spacer()
                    Image(systemName: isTraceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Expanded Trace Details
            if isTraceExpanded {
                sevenStepTraceView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - 7-Step Decision Trace View

    private var sevenStepTraceView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(ZenithiumColor.hairlineSoft)

            // 1. Ham Sinyal
            verticalChainStep(
                number: 1,
                title: "Ham Biyometrik Sinyal",
                detail: result.evidence.first?.summary ?? "HRV ve İstirahat Nabzı gecelik ölçümü",
                badge: result.evidence.first?.sourceCategory,
                isLast: false
            )

            // 2. Taban Sapması (Z-Skoru)
            verticalChainStep(
                number: 2,
                title: "Taban Sapması",
                detail: baselineZDetail,
                badge: "Z-Skoru",
                isLast: false
            )

            // 3. Katkı ve Ağırlık Payı
            verticalChainStep(
                number: 3,
                title: "Katkı ve Ağırlık",
                detail: "Otonom toparlanma ağırlığı %60, uyku mimarisi katkısı %40",
                badge: "% Pay",
                isLast: false
            )

            // 4. Kural / Eşik Tetiklenmesi
            verticalChainStep(
                number: 4,
                title: "Kural ve Eşik",
                detail: result.value.traceSteps.first?.outputDescription ?? "Eşik koşulu sağlandı, karar motoru tetiklendi",
                badge: "Eşik",
                isLast: false
            )

            // 5. Karar Hükmü
            verticalChainStep(
                number: 5,
                title: "Karar Hükmü",
                detail: "\(actionTitle): \(result.value.suggestedActivities.map(\.displayName).joined(separator: ", "))",
                badge: actionTitle,
                isLast: false
            )

            // 6. Güven ve Taban Sağlığı
            verticalChainStep(
                number: 6,
                title: "Güven Düzeyi",
                detail: "%\(Int((result.confidence.value * 100).rounded())) güven. \(result.confidence.penaltyReasons.isEmpty ? "14 günlük eksiksiz taban" : result.confidence.penaltyReasons.joined(separator: ", "))",
                badge: result.confidence.rating.displayName,
                isLast: false
            )

            // 7. Bilimsel Kaynak (EVIDENCE.md)
            verticalChainStep(
                number: 7,
                title: "Bilimsel Kaynak",
                detail: "EVIDENCE.md: Banister (1991), Morton (1997), Gabbett (2016) ACWR modelleri",
                badge: "Akran Denetimli",
                isLast: true
            )
        }
        .padding(.vertical, ZenithiumSpacing.xs)
    }

    private var baselineZDetail: String {
        for step in result.value.traceSteps {
            if step.engineName.localizedCaseInsensitiveContains("recovery") || step.outputDescription.localizedCaseInsensitiveContains("z") {
                return step.outputDescription
            }
        }
        return "Bireysel 14 günlük tabana göre z-skoru normal aralıkta"
    }

    private var actionTitle: String {
        switch result.value.action {
        case .push: return "Zorlanma Uygun"
        case .maintain: return "Dengeli Yük"
        case .recover: return "Toparlanma Öncelikli"
        case .calibrate: return "Kalibrasyon"
        }
    }

    private func verticalChainStep(
        number: Int,
        title: String,
        detail: String,
        badge: String?,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Dikey Kılavuz Çizgisi ve Numara
            VStack(spacing: 0) {
                Circle()
                    .fill(ZenithiumColor.spectrumViolet)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("\(number)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(ZenithiumColor.background)
                    )

                if !isLast {
                    Rectangle()
                        .fill(ZenithiumColor.hairlineSoft)
                        .frame(width: 1.5)
                        .frame(minHeight: 22)
                        .padding(.vertical, 2)
                }
            }
            .frame(width: 18)

            // Adım Detayı
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .zenithiumLabel()
                        .foregroundStyle(ZenithiumColor.textPrimary)

                    Spacer()

                    if let badge {
                        Text(badge)
                            .zenithiumCaption()
                            .foregroundStyle(ZenithiumColor.spectrumViolet)
                    }
                }

                Text(detail)
                    .zenithiumCaption()
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stepRow<Content: View>(
        number: Int,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.spectrumViolet)
                    .frame(width: 14, height: 14)
                    .background(ZenithiumColor.surfaceElevated)
                    .clipShape(Circle())

                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(ZenithiumColor.textTertiary)

                Text(title)
                    .font(ZenithiumFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }

            content()
                .padding(.leading, 20)
        }
    }

    // MARK: - Subviews

    private func actionChip(_ action: DecisionAction) -> some View {
        let (title, bg, fg): (String, Color, Color) = {
            switch action {
            case .push:
                return ("Zorlanma Uygun", ZenithiumColor.green.opacity(0.18), ZenithiumColor.green)
            case .maintain:
                return ("Dengeli Yük", ZenithiumColor.yellow.opacity(0.18), ZenithiumColor.yellow)
            case .recover:
                return ("Toparlanma Öncelikli", ZenithiumColor.red.opacity(0.18), ZenithiumColor.red)
            case .calibrate:
                return ("Kalibrasyon", ZenithiumColor.spectrumViolet.opacity(0.18), ZenithiumColor.spectrumViolet)
            }
        }()

        return Text(title)
            .font(ZenithiumFont.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, ZenithiumSpacing.s)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }

    private func confidenceBadge(_ score: ConfidenceScore) -> some View {
        let pct = Int(score.value * 100)
        let color: Color = {
            switch score.rating {
            case .high: return ZenithiumColor.green
            case .moderate: return ZenithiumColor.yellow
            case .low, .insufficient: return ZenithiumColor.red
            }
        }()

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("%\(pct) Güven")
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(ZenithiumColor.surfaceElevated.opacity(0.6))
        .clipShape(Capsule())
    }

    private func traceStepRow(_ step: TraceStep) -> some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
            Text("\(step.stepNumber)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(width: 14, height: 14)
                .background(ZenithiumColor.surfaceElevated)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.engineName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.spectrumViolet)
                    Spacer()
                    Text(step.outputDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
                Text(step.physiologicalImpact)
                    .font(.system(size: 10))
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 1)
    }
}
