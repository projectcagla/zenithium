//
//  LiveSessionActivity.swift
//  ZenithiumWidgets
//
//  The running session, on the Lock Screen and in the Dynamic Island. Yol haritası v4, C10.
//
//  Read at arm's length, mid-effort, often through a pocket's worth of motion. So the same
//  rule as the watch screen: one number large enough to read without stopping, one ring for
//  where the day sits against its ceiling, everything else small. No advice — a surface
//  glanced at while running is the worst possible place to tell somebody what to do (§1, §12).
//
//  The elapsed clock runs from the session's start rather than from a number in the payload.
//  Application context is coalesced and can arrive late, and a clock that jumps backwards
//  reads as a bug even when every number around it is right.
//

import WidgetKit
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit

struct LiveSessionActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            LockScreenSessionView(
                state: context.state,
                startedAt: context.attributes.startedAt
            )
            .containerBackground(ZenithiumColor.background.gradient, for: .widget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandStrain(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandCeiling(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: ZenithiumSpacing.s) {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(ZenithiumFont.dataValue.monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textSecondary)
                        Spacer(minLength: 0)
                        Text(context.state.band.summary)
                            .font(ZenithiumFont.caption2)
                            .foregroundStyle(tint(for: context.state.band))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(tint(for: context.state.band))
            } compactTrailing: {
                Text(ZenithiumFormat.strain(context.state.dayStrain))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: context.state.band))
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(tint(for: context.state.band))
            }
            .keylineTint(tint(for: context.state.band))
        }
    }

    fileprivate func tint(for band: LiveSessionBand) -> Color {
        LiveSessionStyle.tint(for: band)
    }
}

/// The colours the activity uses.
///
/// Forwards to `ZenithiumColor` rather than restating the mapping. This type used to own a
/// copy, described as "shared so the island and the Lock Screen agree" — which it was, and
/// the watch had a third copy that nothing kept in step with it.
enum LiveSessionStyle {

    static func tint(for band: LiveSessionBand) -> Color {
        ZenithiumColor.color(for: band)
    }
}

// MARK: - Lock Screen

private struct LockScreenSessionView: View {

    let state: LiveSessionAttributes.ContentState
    let startedAt: Date

    var body: some View {
        HStack(spacing: ZenithiumSpacing.l) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(ZenithiumFormat.strain(state.dayStrain))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text("gün zorlanması")
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                Text(startedAt, style: .timer)
                    .font(ZenithiumFont.dataValue.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .multilineTextAlignment(.trailing)
                if let heartRate = state.heartRate {
                    Text("\(Int(heartRate.rounded())) bpm")
                        .font(ZenithiumFont.caption2.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
                Text(state.band.summary)
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(LiveSessionStyle.tint(for: state.band))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if let progress = state.ceilingProgress {
                CeilingRing(progress: progress, band: state.band)
            }
        }
        .padding(.horizontal, ZenithiumSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Süren seans")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = ["gün zorlanması \(ZenithiumFormat.strain(state.dayStrain))"]
        if let progress = state.ceilingProgress {
            parts.append("tavanın yüzde \(Int((progress * 100).rounded()))'i")
        }
        parts.append(state.band.summary)
        return parts.joined(separator: ", ")
    }
}

/// Where the day sits against its ceiling.
private struct CeilingRing: View {

    let progress: Double
    let band: LiveSessionBand

    var body: some View {
        ZStack {
            Circle()
                .stroke(ZenithiumColor.hairline, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    LiveSessionStyle.tint(for: band),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("%\(Int((progress * 100).rounded()))")
                .font(ZenithiumFont.caption2.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textPrimary)
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: - Dynamic Island regions

private struct IslandStrain: View {

    let state: LiveSessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.none) {
            Text(ZenithiumFormat.strain(state.dayStrain))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(LiveSessionStyle.tint(for: state.band))
            Text("zorlanma")
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
    }
}

private struct IslandCeiling: View {

    let state: LiveSessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: ZenithiumSpacing.none) {
            if let ceiling = state.ceiling {
                Text(ZenithiumFormat.strain(ceiling))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text("tavan")
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            } else if let heartRate = state.heartRate {
                Text("\(Int(heartRate.rounded()))")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text("bpm")
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
        }
    }
}
#endif
