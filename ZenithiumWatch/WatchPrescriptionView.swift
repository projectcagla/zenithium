//
//  WatchPrescriptionView.swift
//  ZenithiumWatch
//
//  The second page: what to do. Faz 21.
//
//  Reads the line the phone already decided. The watch does not run the prescription engine
//  — if it did, a wrist and a phone could suggest different sessions from the same morning.
//

import SwiftUI

struct WatchPrescriptionView: View {

    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: ZenithiumSpacing.s) {
            Image(systemName: "figure.run")
                .font(.system(size: 22))
                .foregroundStyle(ZenithiumColor.accent)

            if let line = snapshot.prescriptionLine {
                Text(line)
                    .font(.system(size: 19, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text("Bugünün önerisi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Bugün için öneri yok")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let ceiling = snapshot.targetCeiling {
                Divider()
                Text("Tavan \(ZenithiumFormat.strain(ceiling)) · şu an \(ZenithiumFormat.strain(snapshot.dayStrain))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ZenithiumSpacing.s)
        .containerBackground(ZenithiumColor.accent.gradient.opacity(0.22), for: .tabView)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bugünün önerisi")
        .accessibilityValue(snapshot.prescriptionLine ?? "Öneri yok")
    }
}
