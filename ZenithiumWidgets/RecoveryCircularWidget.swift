//
//  RecoveryCircularWidget.swift
//  ZenithiumWidgets
//
//  Lock Screen circular — recovery. Spec §10.
//
//  Accessory families render monochrome by default, so the band is carried by a glyph rather
//  than by colour here. That is the same rule as everywhere else (ASSUMPTION UI-2), just with
//  the colour channel removed by the platform instead of by a setting.
//

import WidgetKit
import SwiftUI

struct RecoveryCircularWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.zenithium.widget.recovery.circular",
            provider: ZenithiumTimelineProvider()
        ) { entry in
            RecoveryCircularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Toparlanma")
        .description("Bugünün toparlanması, kilit ekranında.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct RecoveryCircularView: View {

    let snapshot: WidgetSnapshot

    private var progress: Double {
        guard let score = snapshot.recoveryScore else { return 0 }
        return MathSupport.clamp(score / 100, 0, 1)
    }

    var body: some View {
        Gauge(value: progress) {
            Image(systemName: snapshot.recoveryBand?.symbolName ?? "heart")
        } currentValueLabel: {
            Text(WidgetStyle.recoveryText(snapshot))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toparlanma")
        .accessibilityValue(WidgetStyle.recoveryAccessibilityValue(snapshot))
    }
}
