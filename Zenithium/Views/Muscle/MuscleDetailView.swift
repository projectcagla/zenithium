//
//  MuscleDetailView.swift
//  Zenithium
//
//  One muscle: readiness now, the decay curve ahead, and what put load on it. Spec §5.4, §10.
//
//  The curve is projected by `FatigueEngine.projectedReadiness`, so the view plots a function
//  it did not derive (§9).
//

import SwiftUI

struct MuscleDetailView: View {

    let readiness: MuscleReadiness
    let sessions: [StrengthSessionSnapshot]

    /// Hours plotted ahead — three days, which is past full recovery at every half-life.
    private static let projectionHours: Double = 72

    private var curve: [(hours: Double, readiness: Double)] {
        stride(from: 0.0, through: Self.projectionHours, by: 2.0).map { hour in
            (hour, FatigueEngine.projectedReadiness(for: readiness.muscle, from: readiness, hoursAhead: hour))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.l) {
                headline
                recoverySection
                mechanicsSection
                contributorSection
            }
            .padding(.horizontal, ZenithiumSpacing.l)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle(readiness.muscle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
    }

    private var headline: some View {
        VStack(spacing: ZenithiumSpacing.m) {
            ScoreArc(
                score: readiness.readiness,
                gradient: ZenithiumColor.arcGradient(for: readiness.band),
                tint: ZenithiumColor.color(for: readiness.band),
                caption: "%",
                accessibilityLabel: "\(readiness.muscle.displayName) hazırlığı",
                accessibilityValue: "yüzde \(ZenithiumFormat.score(readiness.readiness)), \(readiness.trainingLabel)"
            )
            BandChip(band: readiness.band, detail: readiness.trainingLabel)
            Text(SafetyCopy.muscleGuidance(for: readiness))
                .font(ZenithiumFont.body)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var recoverySection: some View {
        SectionCard(
            title: "Toparlanıyor",
            subtitle: "Kaydedilmiş seanslardan yansıtıldı"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                DecayCurve(points: curve)
                    .frame(height: 110)

                if let hours = readiness.hoursUntilReadiness(90) {
                    Text("Başka yük binmezse %90 hazır olmasına yaklaşık \(ZenithiumFormat.metric(hours, digits: 0)) saat var.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if readiness.readiness >= 90 {
                    Text("Tamamen toparlanmış.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }
        }
    }

    private var mechanicsSection: some View {
        SectionCard(title: "Bu nasıl azalıyor") {
            MetricTileGrid {
                MetricTile(
                    label: "Yarı ömür",
                    value: ZenithiumFormat.metric(readiness.halfLifeHours, digits: 1),
                    unit: "h",
                    caption: "\(readiness.muscle.massClass.displayName) kas grubu",
                    accessibilityLabelText: "Yorgunluk yarı ömrü",
                    accessibilityValueText: "\(ZenithiumFormat.metric(readiness.halfLifeHours, digits: 1)) saat"
                )
                MetricTile(
                    label: "Yorgunluk",
                    value: ZenithiumFormat.score(readiness.fatigue),
                    caption: "olası 100 üzerinden",
                    accessibilityLabelText: "Güncel yorgunluk",
                    accessibilityValueText: "100 üzerinden \(ZenithiumFormat.score(readiness.fatigue))"
                )
                MetricTile(
                    label: "Seans",
                    value: "\(readiness.contributingSessionCount)",
                    caption: "hâlâ katkıda",
                    accessibilityLabelText: "Hâlâ katkıda olan seanslar",
                    accessibilityValueText: "\(readiness.contributingSessionCount)"
                )
            }
        }
    }

    private var contributorSection: some View {
        SectionCard(title: "Onu ne yükledi") {
            if let source = readiness.dominantSource, let timestamp = readiness.dominantSourceTimestamp {
                HStack(spacing: ZenithiumSpacing.m) {
                    Image(systemName: source.symbolName)
                        .foregroundStyle(ZenithiumColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text(source.displayName)
                            .font(ZenithiumFont.label)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                    Spacer(minLength: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("En büyük katkı")
            } else {
                Text("Son iki haftada bu gruba yük binmemiş.")
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The projected readiness curve.
private struct DecayCurve: View {

    let points: [(hours: Double, readiness: Double)]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard points.count >= 2, let last = points.last, last.hours > 0 else { return }

                func location(_ point: (hours: Double, readiness: Double)) -> CGPoint {
                    CGPoint(
                        x: point.hours / last.hours * size.width,
                        y: size.height - MathSupport.clamp(point.readiness / 100, 0, 1) * size.height
                    )
                }

                // The 90% line, so the curve has a reference rather than floating.
                var target = Path()
                let targetY = size.height - 0.9 * size.height
                target.move(to: CGPoint(x: 0, y: targetY))
                target.addLine(to: CGPoint(x: size.width, y: targetY))
                context.stroke(
                    target,
                    with: .color(ZenithiumColor.hairline),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                var line = Path()
                line.move(to: location(points[0]))
                for point in points.dropFirst() {
                    line.addLine(to: location(point))
                }
                context.stroke(
                    line,
                    with: .color(ZenithiumColor.accent),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Önümüzdeki üç günün yansıtılan toparlanması")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let first = points.first, let last = points.last else { return "" }
        return "Şu an %\(ZenithiumFormat.score(first.readiness))'ten \(Int(last.hours)) saat sonra %\(ZenithiumFormat.score(last.readiness))'e"
    }
}
