//
//  PrescriptionCard.swift
//  Zenithium
//
//  Today's suggestion. Faz 19, Faz 20.
//
//  The card leads with the session and keeps the reasoning one tap away. Both halves matter:
//  a suggestion nobody can interrogate is a horoscope, and a suggestion buried under its own
//  justification is not a suggestion.
//

import SwiftUI

struct PrescriptionCard: View {

    let prescription: Prescription
    var plan: PlanPosition?
    var wrappedInCard: Bool = false

    @State private var showsRationale = false
    @State private var selected: PrescribedSession?

    private var current: PrescribedSession {
        selected ?? prescription.primary
    }

    var body: some View {
        if wrappedInCard {
            SectionCard {
                prescriptionContent
            }
        } else {
            prescriptionContent
        }
    }

    private var prescriptionContent: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            if let plan {
                planRow(plan)
                Divider().overlay(ZenithiumColor.hairlineSoft)
            }

                sessionRow(current)

                if !prescription.alternatives.isEmpty {
                    alternativesRow
                }

                footer

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showsRationale.toggle() }
                } label: {
                    HStack(spacing: ZenithiumSpacing.xs) {
                        Text(showsRationale ? "Gerekçeyi gizle" : "Neden bu?")
                        Image(systemName: showsRationale ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.accent)
                }
                .buttonStyle(.plain)

                if showsRationale {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        ForEach(Array(prescription.rationale.enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
                                Circle()
                                    .fill(ZenithiumColor.textTertiary)
                                    .frame(width: 3, height: 3)
                                    .padding(.top, ZenithiumSpacing.s)
                                    .accessibilityHidden(true)
                                Text(reason)
                                    .font(ZenithiumFont.footnote)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bugünün önerisi")
    }

    // MARK: - Plan

    private func planRow(_ plan: PlanPosition) -> some View {
        HStack(spacing: ZenithiumSpacing.s) {
            Image(systemName: plan.event.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(ZenithiumColor.spectrumAmber)
                .accessibilityHidden(true)
            Text(PlanEngine.summary(for: plan))
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Session

    private func sessionRow(_ session: PrescribedSession) -> some View {
        HStack(alignment: .center, spacing: ZenithiumSpacing.l) {
            Image(systemName: session.kind.symbolName)
                .font(.system(size: 19))
                .foregroundStyle(ZenithiumColor.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: ZenithiumRadius.large, style: .continuous)
                        .fill(ZenithiumColor.accent.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                Text(headline(for: session))
                    .font(ZenithiumFont.verdict)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let band = session.paceBand {
                    Text("\(ZenithiumFormat.pace(secondsPerKilometre: band.fastPace)) – \(ZenithiumFormat.pace(secondsPerKilometre: band.slowPace))")
                        .font(ZenithiumFont.callout.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func headline(for session: PrescribedSession) -> String {
        guard session.kind != .rest else { return "Bugün dinlenme" }
        return "\(session.minutes) dk \(session.kind.displayName.lowercased())"
    }

    // MARK: - Alternatives

    private var alternativesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ZenithiumSpacing.s) {
                ForEach(prescription.everySession) { session in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selected = session
                        }
                    } label: {
                        Text(chipLabel(for: session))
                            .font(ZenithiumFont.caption)
                            .padding(.horizontal, ZenithiumSpacing.m)
                            .padding(.vertical, ZenithiumSpacing.s)
                            .background(
                                Capsule().fill(
                                    session.id == current.id
                                        ? ZenithiumColor.accent.opacity(0.20)
                                        : ZenithiumColor.hairlineSoft
                                )
                            )
                            .foregroundStyle(
                                session.id == current.id
                                    ? ZenithiumColor.accent
                                    : ZenithiumColor.textSecondary
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chipLabel(for: session))
                    .accessibilityAddTraits(session.id == current.id ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, ZenithiumSpacing.xxs)
        }
    }

    private func chipLabel(for session: PrescribedSession) -> String {
        session.kind == .rest
            ? session.kind.displayName
            : "\(session.kind.displayName) · \(session.minutes) dk"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: ZenithiumSpacing.l) {
            if current.forecastStrain > 0 {
                labelled("Öngörülen", ZenithiumFormat.strain(current.forecastStrain))
            }
            if let ceiling = prescription.ceiling {
                labelled("Tavan", ZenithiumFormat.strain(ceiling))
            }
            if let ratio = prescription.projectedRatio {
                labelled("Yük oranı", ZenithiumFormat.metric(ratio, digits: 2))
            }
            if let window = prescription.suggestedWindow {
                labelled("En iyi saat", window.start.formatted(date: .omitted, time: .shortened))
            }
            Spacer(minLength: 0)
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
            Text(label)
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textTertiary)
            Text(value)
                .font(ZenithiumFont.caption.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
