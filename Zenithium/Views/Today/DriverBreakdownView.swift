//
//  DriverBreakdownView.swift
//  Zenithium
//
//  The driver breakdown. Spec §5.1 makes this a required UI output: each term's contribution
//  `c_i = w_i·Z_i`, its share of `|Z_total|`, and the top positive and negative drivers as
//  plain-language strings.
//
//  Nothing here computes anything — every number arrives on `DriverContribution` (§9).
//

import SwiftUI

struct DriverBreakdownView: View {

    let drivers: [DriverContribution]
    let missing: [RecoveryDriver]
    let weightsWereRenormalized: Bool
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            ForEach(drivers) { driver in
                DriverRow(contribution: driver, unitPreference: unitPreference)
            }

            if !missing.isEmpty {
                Divider().overlay(ZenithiumColor.hairline)
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                    Text(missingHeadline)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    if weightsWereRenormalized {
                        // §4.3 — say that the weights moved, rather than letting the user
                        // wonder why a four-term score still adds up.
                        Text("Kalan belirleyiciler yeniden ağırlıklandırıldı; toplamları hâlâ %100.")
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var missingHeadline: String {
        // No singular/plural split: Turkish does not inflect the verb for a plural subject
        // here, so the two branches the English copy needed produce one sentence.
        let names = missing.map(\.displayName).joined(separator: ", ")
        return "\(names) dün gece yoktu."
    }
}

/// One driver: name, observed value, signed contribution, and a bar showing its share.
private struct DriverRow: View {

    let contribution: DriverContribution
    let unitPreference: UnitPreference

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color {
        contribution.isPositive ? ZenithiumColor.green : ZenithiumColor.red
    }

    /// The glyph carries the direction without colour (ASSUMPTION UI-2).
    private var directionSymbol: String {
        contribution.isPositive ? "arrow.up" : "arrow.down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: ZenithiumSpacing.s) {
                Image(systemName: directionSymbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(contribution.driver.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            ShareBar(share: contribution.share, tint: tint)

            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the inline percentage would be squeezed out of the
                // row above, so it becomes its own line instead of being dropped.
                Text("bugünkü sapmanın \(ZenithiumFormat.percent(contribution.share)) kadarı")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contribution.driver.accessibilityName)
        .accessibilityValue(accessibilityValue)
    }

    /// The observed value in the driver's own unit — a temperature driver shows its delta,
    /// converted for display only (§2.8).
    private var valueText: String {
        switch contribution.driver {
        case .temperature:
            let delta = unitPreference.temperatureDelta(fromCelsius: contribution.observedValue)
            return "\(ZenithiumFormat.signed(delta, digits: 2)) \(unitPreference.temperatureDeltaSymbol)"
        case .heartRateVariability:
            return "\(ZenithiumFormat.metric(contribution.observedValue, digits: 0)) ms"
        case .restingHeartRate:
            return "\(ZenithiumFormat.metric(contribution.observedValue, digits: 0)) bpm"
        case .respiratory:
            return "\(ZenithiumFormat.metric(contribution.observedValue, digits: 1)) br/min"
        case .sleep:
            return ZenithiumFormat.score(contribution.observedValue)
        }
    }

    private var accessibilityValue: String {
        let direction = contribution.isPositive ? "yukarı çekiyor" : "aşağı çekiyor"
        return "\(valueText), toparlanmayı \(direction), bugünkü sapmanın \(ZenithiumFormat.percent(contribution.share)) kadarı"
    }
}

/// A bar whose width is the driver's share of the total magnitude.
private struct ShareBar: View {

    let share: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ZenithiumColor.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * MathSupport.clamp(share, 0, 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
