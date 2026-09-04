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
        VStack(spacing: ZenithiumSpacing.xs) {
            if let score = snapshot.recoveryScore {
                ZStack {
                    Circle()
                        .trim(from: 0.12, to: 0.68)
                        .stroke(
                            tint.opacity(0.18),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))

                    Circle()
                        .trim(from: 0.12, to: 0.12 + 0.56 * min(max(score / 100, 0), 1))
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))

                    VStack(spacing: ZenithiumSpacing.none) {
                        Text("\(Int(score.rounded()))")
                            .font(.system(size: 38, weight: .bold).width(.expanded).monospacedDigit())
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text("%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: 4)
                }
                .frame(width: 104, height: 104)

                if let ceiling = snapshot.targetCeiling {
                    HStack(spacing: ZenithiumSpacing.m) {
                        value(ZenithiumFormat.strain(snapshot.dayStrain), label: "Zorlanma")
                        value(ZenithiumFormat.strain(ceiling), label: "Tavan")
                    }
                    .padding(.top, 2)
                }

                BaselineBand(
                    values: [score],
                    baseline: 65.0,
                    sigma: 12.0,
                    unit: "%",
                    style: .micro
                )
                .frame(width: 80, height: 16)
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
        .containerBackground(Color.black, for: .tabView)
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
