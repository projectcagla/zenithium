//
//  WatchRecoveryView.swift
//  ZenithiumWatch
//
//  The first page: where the body is. Faz 21.
//

import SwiftUI

struct WatchRecoveryView: View {

    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: ZenithiumSpacing.s) {
            if let score = snapshot.recoveryScore {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 46, weight: .bold).width(.expanded).monospacedDigit())
                    .foregroundStyle(tint)
                Text("Toparlanma")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let ceiling = snapshot.targetCeiling {
                    Divider()
                    HStack(spacing: ZenithiumSpacing.m) {
                        value(ZenithiumFormat.strain(snapshot.dayStrain), label: "Zorlanma")
                        value(ZenithiumFormat.strain(ceiling), label: "Tavan")
                    }
                }
            } else if snapshot.isCalibrating {
                Text("%\(Int((snapshot.calibrationProgress * 100).rounded()))")
                    .font(.system(size: 38, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Taban çizgin kuruluyor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("Henüz puan yok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ZenithiumSpacing.xs)
        .containerBackground(tint.gradient.opacity(0.28), for: .tabView)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Toparlanma")
        .accessibilityValue(spokenValue)
    }

    private func value(_ text: String, label: String) -> some View {
        VStack(spacing: ZenithiumSpacing.xxs) {
            Text(text)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(text)")
    }

    /// The band's colour, or a neutral one before there is a band.
    private var tint: Color {
        switch snapshot.recoveryBand {
        case .green: return ZenithiumColor.green
        case .yellow: return ZenithiumColor.yellow
        case .red: return ZenithiumColor.red
        case nil: return ZenithiumColor.accent
        }
    }

    private var spokenValue: String {
        guard let score = snapshot.recoveryScore else {
            return snapshot.isCalibrating ? "Taban çizgisi kuruluyor" : "Puan yok"
        }
        var spoken = "\(Int(score.rounded()))"
        if let ceiling = snapshot.targetCeiling {
            spoken += ", zorlanma \(ZenithiumFormat.strain(snapshot.dayStrain)), tavan \(ZenithiumFormat.strain(ceiling))"
        }
        return spoken
    }
}
