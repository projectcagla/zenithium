//
//  BandChip.swift
//  Zenithium
//
//  A band label. ASSUMPTION UI-2 and the §10 accessibility gate: a band is never encoded by
//  colour alone. This chip always carries the colour, a glyph and the band's name, so it
//  survives greyscale, colour blindness and a screenshot printed in black and white.
//

import SwiftUI

struct BandChip: View {

    let band: RecoveryBand

    /// An optional trailing detail, e.g. "72%".
    var detail: String?

    var body: some View {
        HStack(spacing: ZenithiumSpacing.s) {
            Image(systemName: band.symbolName)
                .imageScale(.small)
            Text(band.displayName)
                .font(ZenithiumFont.label)
            if let detail {
                Text(detail)
                    .font(ZenithiumFont.label.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }
        }
        .foregroundStyle(ZenithiumColor.color(for: band))
        .padding(.horizontal, ZenithiumSpacing.m)
        .padding(.vertical, ZenithiumSpacing.s)
        .background {
            Capsule(style: .continuous)
                .fill(ZenithiumColor.color(for: band).opacity(0.14))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ZenithiumColor.color(for: band).opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(band.displayName) bandı")
        .accessibilityValue(detail ?? "")
    }
}

/// A small badge for the data-quality state of a record (§7).
struct QualityChip: View {

    let quality: DataQuality
    let reasons: [DataQualityReason]

    private var tint: Color {
        switch quality {
        case .good: return ZenithiumColor.textSecondary
        case .partial: return ZenithiumColor.yellow
        case .suspect: return ZenithiumColor.red
        }
    }

    private var symbolName: String {
        switch quality {
        case .good: return "checkmark.circle"
        case .partial: return "exclamationmark.circle"
        case .suspect: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: ZenithiumSpacing.s) {
            Image(systemName: symbolName)
                .imageScale(.small)
            Text(quality.displayName)
                .font(ZenithiumFont.caption)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Veri kalitesi")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard !reasons.isEmpty else { return quality.displayName }
        let list = reasons.map(\.displayName).joined(separator: ", ")
        return "\(quality.displayName). \(list)"
    }
}
