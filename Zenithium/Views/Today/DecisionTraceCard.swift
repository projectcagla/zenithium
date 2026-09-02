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
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Divider().overlay(ZenithiumColor.hairlineSoft)

            // 1. Karar Hükmü ve Aksiyon
            stepRow(number: 1, title: "Karar ve Eylem Tipi", icon: "flag.checkered") {
                HStack(spacing: ZenithiumSpacing.s) {
                    actionChip(result.value.action)
                    confidenceBadge(result.confidence)
                }
            }

            // 2. Kullanıcı Verisi Kanıtları (Evidence Nodes)
            if !result.evidence.isEmpty {
                stepRow(number: 2, title: "Kullanıcı Biyometrik Kanıtları", icon: "waveform.path.ecg") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(result.evidence) { node in
                            HStack(alignment: .firstTextBaseline) {
                                Text("• \(node.sourceCategory):")
                                    .font(ZenithiumFont.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                Text(node.summary)
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                    }
                }
            }

            // 3. Hesaplama Adımları (Trace Steps)
            stepRow(number: 3, title: "Hesaplama ve Kural Zinciri", icon: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                    ForEach(result.value.traceSteps) { step in
                        traceStepRow(step)
                    }
                }
            }

            // 4. Bilimsel Sınırlar & Literatür Dayanağı
            stepRow(number: 4, title: "Bilimsel Sınırlar & Modeller", icon: "books.vertical.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Karar; RecoveryEngine, TrainingLoadEngine (Banister/ACWR) ve SleepScoreEngine modellerinin akran denetimli sınırları dahilinde sentezlenmiştir.")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            }

            // 5. Metodolojik Sınırlılıklar
            if !result.limitations.isEmpty {
                stepRow(number: 5, title: "Kapsam ve Kısıtlar", icon: "exclamationmark.shield") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.limitations) { limitation in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: limitation.isBlocking ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(limitation.isBlocking ? ZenithiumColor.red : ZenithiumColor.yellow)
                                Text("[\(limitation.code)] \(limitation.explanation)")
                                    .font(ZenithiumFont.caption2)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // 6. Güven Skoru & Ceza Kırılımı
            stepRow(number: 6, title: "Güven Düzeyi ve Ceza Kırılımı", icon: "chart.bar.xaxis") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nihai Güven: %\(Int((result.confidence.value * 100).rounded())) (\(result.confidence.rating.displayName))")
                        .font(ZenithiumFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(ZenithiumColor.textPrimary)

                    if result.confidence.penaltyReasons.isEmpty {
                        Text("Herhangi bir veri kalitesi veya taban çizgisi cezası bulunmuyor.")
                            .font(ZenithiumFont.caption2)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    } else {
                        ForEach(result.confidence.penaltyReasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 4) {
                                Text("−")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ZenithiumColor.yellow)
                                Text(reason)
                                    .font(ZenithiumFont.caption2)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                    }
                }
            }

            // 7. Fikrini Ne Değiştirir? (Falsifiability)
            stepRow(number: 7, title: "Fikrini Ne Değiştirir?", icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("• Yeni antrenman seansları kaydedildiğinde veya gece biyometrisi güncellendiğinde bu karar yeniden hesaplanır.")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    Text("• Otonom sinir sistemi dengesi (HRV z-skoru) taban çizgisine döndüğünde önerilen yük seviyesi normale döner.")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            }
        }
        .padding(.leading, ZenithiumSpacing.xs)
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
