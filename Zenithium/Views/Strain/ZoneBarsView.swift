//
//  ZoneBarsView.swift
//  Zenithium
//
//  The six %HRR zone bars. ASSUMPTION ZONE-1 for the bands, §10 for the accessibility gate:
//  every bar carries its duration in words, and the zone is named as well as coloured.
//
//  Shares arrive pre-measured on `StrainViewModel.ZoneBar` (§9).
//

import SwiftUI

struct ZoneBarsView: View {

    let bars: [StrainViewModel.ZoneBar]

    /// Bars with no time in them are dropped, unless every bar is empty — in which case the
    /// caller is showing a day with no coverage and the empty state says so instead.
    private var visibleBars: [StrainViewModel.ZoneBar] {
        let occupied = bars.filter { $0.seconds > 0 }
        return occupied.isEmpty ? bars : occupied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            ForEach(visibleBars) { bar in
                ZoneBarRow(bar: bar)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Her nabız bölgesinde geçen süre")
    }
}

private struct ZoneBarRow: View {

    let bar: StrainViewModel.ZoneBar

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color { ZenithiumColor.color(for: bar.zone) }

    private var rangeText: String {
        let range = bar.zone.reserveRange
        return "\(Int(range.lower * 100))–\(Int(range.upper * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                Text(bar.zone.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                // The effort word is what makes the zone legible without the colour.
                Text(bar.zone.effortLabel)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(rangeText)
                        .font(ZenithiumFont.caption.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }

                Spacer(minLength: 8)

                Text(ZenithiumFormat.duration(seconds: bar.seconds))
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZenithiumColor.hairline)
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * MathSupport.clamp(bar.share, 0, 1))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.zone.displayName), \(bar.zone.effortLabel), \(rangeText) kalp atış rezervi")
        .accessibilityValue(
            "\(ZenithiumFormat.spokenDuration(seconds: bar.seconds)), \(ZenithiumFormat.percent(bar.share)) gününün"
        )
    }
}
