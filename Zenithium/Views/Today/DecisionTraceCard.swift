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
    @State private var isTraceExpanded = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                // Header: Action Chip + Confidence Badge
                HStack(alignment: .center) {
                    actionChip(result.value.action)
                    Spacer()
                    confidenceBadge(result.confidence)
                }

                // Headline
                Text(result.value.headline)
                    .font(ZenithiumFont.sectionTitle)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                // Rationale
                Text(result.value.primaryRationale)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

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

                Divider()
                    .background(ZenithiumColor.hairline)

                // Epistemic Decision Trace Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTraceExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ZenithiumColor.spectrumViolet)
                        Text("Deterministik Karar İzi (Decision Trace)")
                            .font(ZenithiumFont.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Spacer()
                        Image(systemName: isTraceExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                // Expanded Trace Details
                if isTraceExpanded {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        ForEach(result.value.traceSteps) { step in
                            traceStepRow(step)
                        }

                        if !result.limitations.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(result.limitations) { limitation in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: limitation.isBlocking ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(limitation.isBlocking ? ZenithiumColor.red : ZenithiumColor.yellow)
                                        Text("[\(limitation.code)] \(limitation.explanation)")
                                            .font(ZenithiumFont.caption)
                                            .foregroundStyle(ZenithiumColor.textSecondary)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.leading, ZenithiumSpacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
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
            .font(ZenithiumFont.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, ZenithiumSpacing.s)
            .padding(.vertical, 4)
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
                .font(ZenithiumFont.caption)
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
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ZenithiumColor.textTertiary)
                .frame(width: 14, height: 14)
                .background(ZenithiumColor.surfaceElevated)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.engineName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.spectrumViolet)
                    Spacer()
                    Text(step.outputDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
                Text(step.physiologicalImpact)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
