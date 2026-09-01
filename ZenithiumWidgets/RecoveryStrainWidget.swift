//
//  RecoveryStrainWidget.swift
//  ZenithiumWidgets
//
//  Home Screen small — recovery plus strain against its ceiling. Spec §10.
//

import WidgetKit
import SwiftUI

struct RecoveryStrainWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.zenithium.widget.recovery.strain",
            provider: ZenithiumTimelineProvider()
        ) { entry in
            RecoveryStrainView(snapshot: entry.snapshot)
                .containerBackground(ZenithiumColor.background, for: .widget)
        }
        .configurationDisplayName("Toparlanma ve Zorlanma")
        .description("Bugünün toparlanması ve hedefine göre aldığın yük.")
        .supportedFamilies([.systemSmall])
    }
}

struct RecoveryStrainView: View {

    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xs) {
                Text(WidgetStyle.recoveryText(snapshot))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.bandColor(snapshot))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if snapshot.recoveryScore != nil {
                    Text("%")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            }

            if let band = snapshot.recoveryBand {
                HStack(spacing: ZenithiumSpacing.xs) {
                    Image(systemName: band.symbolName)
                        .imageScale(.small)
                    Text(band.displayName)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                }
                .foregroundStyle(WidgetStyle.bandColor(snapshot))
            } else if snapshot.isCalibrating {
                Text("Kalibrasyon")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xs) {
                    Text("Zorlanma")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    Spacer(minLength: 4)
                    Text(ZenithiumFormat.strain(snapshot.dayStrain))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    if let ceiling = snapshot.targetCeiling {
                        Text("/ \(ZenithiumFormat.strain(ceiling))")
                            .font(.system(.caption2, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ZenithiumColor.hairline)
                        Capsule()
                            .fill(ZenithiumColor.accent)
                            .frame(width: proxy.size.width * (snapshot.ceilingProgress ?? 0))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(ZenithiumSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toparlanma ve zorlanma")
        .accessibilityValue(
            "\(WidgetStyle.recoveryAccessibilityValue(snapshot)). Zorlanma \(WidgetStyle.strainAccessibilityValue(snapshot))"
        )
    }
}
