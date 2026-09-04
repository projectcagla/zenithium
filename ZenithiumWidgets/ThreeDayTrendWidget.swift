//
//  ThreeDayTrendWidget.swift
//  ZenithiumWidgets
//
//  Home Screen medium — a three-day trend. Spec §10.
//

import WidgetKit
import SwiftUI

struct ThreeDayTrendWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.zenithium.widget.trend.threeday",
            provider: ZenithiumTimelineProvider()
        ) { entry in
            ThreeDayTrendView(snapshot: entry.snapshot)
                .containerBackground(ZenithiumColor.background, for: .widget)
        }
        .configurationDisplayName("Üç günlük trend")
        .description("Son üç günün toparlanma, zorlanma ve uykusu.")
        .supportedFamilies([.systemMedium])
    }
}

struct ThreeDayTrendView: View {

    let snapshot: WidgetSnapshot

    /// Oldest first, so the row reads left to right in time order.
    private var days: [WidgetTrendPoint] {
        snapshot.trend.sorted { $0.dayStart < $1.dayStart }.suffix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                Text("Zenithium")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(ZenithiumColor.textSecondary)
                Spacer(minLength: 4)
                if let band = snapshot.recoveryBand {
                    HStack(spacing: ZenithiumSpacing.xs) {
                        Image(systemName: band.symbolName).imageScale(.small)
                        Text(band.displayName)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                    }
                    .foregroundStyle(WidgetStyle.bandColor(snapshot))
                }
            }

            if days.isEmpty {
                Text("Henüz geçmiş yok. Saatini gece tak, burası dolsun.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                    ForEach(days, id: \.dayStart) { day in
                        DayColumn(day: day)
                    }
                }

                BaselineBand(
                    values: days.compactMap(\.recoveryScore),
                    baseline: 65.0,
                    sigma: 12.0,
                    unit: "%",
                    style: .inline
                )
            }

            Spacer(minLength: 0)
        }
        .padding(ZenithiumSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Üç günlük trend")
    }
}

/// One day's three numbers.
private struct DayColumn: View {

    let day: WidgetTrendPoint

    private var band: RecoveryBand? {
        day.recoveryScore.map(RecoveryBand.band(forScore:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            Text(day.dayStart, format: .dateTime.weekday(.abbreviated))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(ZenithiumColor.textTertiary)

            HStack(spacing: ZenithiumSpacing.xs) {
                if let band {
                    Image(systemName: band.symbolName)
                        .imageScale(.small)
                        .foregroundStyle(ZenithiumColor.color(for: band))
                }
                Text(day.recoveryScore.map { ZenithiumFormat.score($0) } ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }

            Text("Zorlanma \(ZenithiumFormat.strain(day.dayStrain))")
                .font(.system(.caption2, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZenithiumColor.textSecondary)

            Text(day.sleepScore.map { "Uyku \(ZenithiumFormat.score($0))" } ?? "Uyku —")
                .font(.system(.caption2, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.dayStart.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let score = day.recoveryScore, let band {
            parts.append("toparlanma yüzde \(ZenithiumFormat.score(score)), \(band.displayName)")
        } else {
            parts.append("toparlanma puanı yok")
        }
        parts.append("zorlanma \(ZenithiumFormat.strain(day.dayStrain))")
        if let sleep = day.sleepScore {
            parts.append("sleep \(ZenithiumFormat.score(sleep))")
        }
        return parts.joined(separator: ", ")
    }
}
