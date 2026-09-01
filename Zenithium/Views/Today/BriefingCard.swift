//
//  BriefingCard.swift
//  Zenithium
//
//  The narrated briefing at the top of Today. Faz 24.
//
//  This card is the answer to "so what?". The arc says 61; this says why it is 61 and what
//  that changes. It sits above the numbers on purpose — the sentence is what a person acts
//  on, and the numbers are there to be checked against it.
//

import SwiftUI

struct BriefingCard: View {

    let briefing: Briefing

    /// Whether to show which layer wrote it. Off by default: the user cares what it says,
    /// not which code path produced it. Settings turns it on for the curious.
    var showsSource = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text(briefing.headline)
                    .font(ZenithiumFont.verdict)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if !briefing.body.isEmpty {
                    Text(briefing.body)
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !briefing.points.isEmpty {
                    Divider().overlay(ZenithiumColor.hairline)
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                        ForEach(Array(briefing.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
                                Circle()
                                    .fill(ZenithiumColor.accent.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, ZenithiumSpacing.s)
                                    .accessibilityHidden(true)
                                Text(point)
                                    .font(ZenithiumFont.footnote)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // §12 — when any point came from a value outside its reference band, the
                // clinician prompt travels with it. It is never a dismissible footer.
                if briefing.requiresClinicianPrompt {
                    Text(SafetyCopy.clinicianPrompt)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsSource {
                    Text(briefing.source.displayName)
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bugünün özeti")
    }
}
