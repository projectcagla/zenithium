//
//  EvidenceChainView.swift
//  Zenithium
//
//  Şartname Detay / "Neden?" Kanıt Zinciri:
//  Tamamı L1. Tek bir kart bile yok.
//  Üstten alta tek bir dikey kanıt zinciri:
//    1. Ham sinyal (ör. HRV 42 ms)
//    2. Taban sapması (Z = −1.4)
//    3. Katkı (%38 pay)
//    4. Kural / eşik (Z < −1.0 tetiklendi)
//    5. Karar ("toparlanma önceliği")
//    6. Güven (%82, 14 günlük taban)
//    7. Kaynak (EVIDENCE.md'deki künye, DOI ile)
//  Aralarında yalnızca 12pt boşluk ve soluk dikey bağlantı çizgisi (kılavuz).
//

import SwiftUI

struct EvidenceChainItem: Identifiable, Sendable {
    let id = UUID()
    let stepNumber: Int
    let title: String
    let valueText: String
    let detailText: String?
    let statusColor: Color?
}

struct EvidenceChainView: View {

    let items: [EvidenceChainItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    // Dikey Kılavuz Çizgisi ve Adım Numarası
                    VStack(spacing: 0) {
                        Circle()
                            .fill(item.statusColor ?? ZenithiumColor.spectrumViolet)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(item.stepNumber)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ZenithiumColor.background)
                            )

                        if index < items.count - 1 {
                            Rectangle()
                                .fill(ZenithiumColor.hairlineSoft)
                                .frame(width: 1.5)
                                .frame(minHeight: 24)
                                .padding(.vertical, 2)
                        }
                    }
                    .frame(width: 20)

                    // İçerik
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title)
                                .zenithiumLabel()
                                .foregroundStyle(ZenithiumColor.textPrimary)

                            Spacer()

                            Text(item.valueText)
                                .sectionTitle()
                                .foregroundStyle(item.statusColor ?? ZenithiumColor.textPrimary)
                                .monospacedDigit()
                        }

                        if let detail = item.detailText {
                            Text(detail)
                                .zenithiumCaption()
                                .foregroundStyle(ZenithiumColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ZenithiumSpacing.s)
    }
}
