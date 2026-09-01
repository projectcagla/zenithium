//
//  SectionCard.swift
//  Zenithium
//
//  The card every section sits in. Spec §10: surface `#0B0F14` with a hairline border.
//

import SwiftUI

struct SectionCard<Content: View>: View {

    var title: String?
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                    if let title {
                        Text(title)
                            .font(ZenithiumFont.sectionTitle)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }
                // One heading per card, so VoiceOver's rotor lists the sections.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZenithiumSpacing.l)
        .background {
            // İki duraklı dikey gradyan: kart üstten hafifçe aydınlanır, altta zemine
            // karışır. Düz bir yüzeyden daha az yassı, bir malzemeden daha az gürültülü.
            RoundedRectangle(cornerRadius: ZenithiumRadius.xLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ZenithiumColor.surfaceElevated, ZenithiumColor.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenithiumRadius.xLarge, style: .continuous)
                .strokeBorder(ZenithiumColor.hairline, lineWidth: 1)
        }
    }
}
