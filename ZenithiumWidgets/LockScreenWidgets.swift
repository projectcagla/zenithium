//
//  LockScreenWidgets.swift
//  ZenithiumWidgets
//
//  The other two Lock Screen families. Yol haritası v4, C10.
//
//  The circular accessory has been here since §10; these are the rectangular and inline ones
//  beside it. Each family answers a different question, which is why they are three widgets
//  and not one with a switch in it:
//
//  * **Circular** — one number at a glance. Already existed.
//  * **Rectangular** — the morning in a sentence: recovery, today's ceiling, and what the
//    prescription said, because there is room for it.
//  * **Inline** — a single line above the clock, so it has to survive being truncated to
//    almost nothing. It says the least and says it first.
//
//  Accessory families render monochrome, so no band is carried by colour alone
//  (ASSUMPTION UI-2). Here the platform removes the colour channel rather than a setting
//  doing it, which is the same constraint arriving by a different route.
//

import WidgetKit
import SwiftUI

// MARK: - Rectangular

struct RecoveryRectangularWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.zenithium.widget.recovery.rectangular",
            provider: ZenithiumTimelineProvider()
        ) { entry in
            RecoveryRectangularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Toparlanma ve bugün")
        .description("Toparlanma, günün tavanı ve önerilen seans.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RecoveryRectangularView: View {

    let snapshot: WidgetSnapshot

    var body: some View {
        // Off the app's spacing scale on purpose: a Lock Screen accessory is about sixty
        // points tall and the scale's smallest step would spend a tenth of it on a gap.
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.recoveryBand?.symbolName ?? "heart")
                    .imageScale(.small)
                Text(WidgetStyle.recoveryText(snapshot))
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                if let ceiling = snapshot.targetCeiling {
                    Text("· tavan \(ZenithiumFormat.strain(ceiling))")
                        .font(.system(.caption2, design: .rounded))
                }
            }
            .lineLimit(1)

            // The prescription's own line when there is one; otherwise the strain, because a
            // blank second row wastes the only extra space this family has over the circular.
            Text(secondLine)
                .font(.system(.caption, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toparlanma")
        .accessibilityValue("\(WidgetStyle.recoveryAccessibilityValue(snapshot)). \(secondLine)")
    }

    private var secondLine: String {
        if let line = snapshot.prescriptionLine, !line.isEmpty { return line }
        guard snapshot.hasData else { return "Henüz veri yok" }
        return "Zorlanma \(ZenithiumFormat.strain(snapshot.dayStrain))"
    }
}

// MARK: - Inline

struct RecoveryInlineWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.zenithium.widget.recovery.inline",
            provider: ZenithiumTimelineProvider()
        ) { entry in
            RecoveryInlineView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Toparlanma satırı")
        .description("Saatin üstünde tek satır.")
        .supportedFamilies([.accessoryInline])
    }
}

struct RecoveryInlineView: View {

    let snapshot: WidgetSnapshot

    var body: some View {
        // One line, and the system may truncate it hard, so the number comes first and the
        // band's name second — losing "yeşil bant" costs less than losing the score.
        Label {
            Text(text)
        } icon: {
            Image(systemName: snapshot.recoveryBand?.symbolName ?? "heart")
        }
        .accessibilityLabel("Toparlanma")
        .accessibilityValue(WidgetStyle.recoveryAccessibilityValue(snapshot))
    }

    private var text: String {
        guard snapshot.hasData else { return "Zenithium" }
        guard let band = snapshot.recoveryBand else {
            return WidgetStyle.recoveryText(snapshot)
        }
        return "\(WidgetStyle.recoveryText(snapshot)) · \(band.displayName.lowercased())"
    }
}
