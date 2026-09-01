//
//  MetricTile.swift
//  Zenithium
//
//  A labelled value. Spec §10: monospaced digits, and an accessibility label and value on
//  every element that carries a number.
//

import SwiftUI

struct MetricTile: View {

    let label: String
    let value: String
    var unit: String?
    var caption: String?
    var tint: Color = ZenithiumColor.textPrimary

    /// Spoken label, when the visible one is an abbreviation like "HRV".
    var accessibilityLabelText: String?

    /// Spoken value, when the visible one is not a sentence, e.g. "62 milliseconds".
    var accessibilityValueText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            Text(label)
                .font(ZenithiumFont.label)
                .foregroundStyle(ZenithiumColor.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.xs) {
                Text(value)
                    .font(ZenithiumFont.metricValue)
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(ZenithiumFont.unit)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            if let caption {
                Text(caption)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText ?? label)
        .accessibilityValue(accessibilityValueText ?? [value, unit].compactMap { $0 }.joined(separator: " "))
    }
}

/// A row of tiles that reflows into a grid, so AX5 wraps instead of clipping (§10).
struct MetricTileGrid<Content: View>: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: () -> Content

    private var columns: [GridItem] {
        // At accessibility sizes a two-up row cannot hold a label and a value without
        // truncating, so the grid drops to one column rather than shrinking text further.
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: ZenithiumSpacing.l, alignment: .topLeading), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ZenithiumSpacing.l) {
            content()
        }
    }
}
