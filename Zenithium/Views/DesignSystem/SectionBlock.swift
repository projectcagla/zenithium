//
//  SectionBlock.swift
//  Zenithium
//
//  L1 Bölüm Kabı — Şartname Yasa 2 (Yükselti Modeli).
//  Dolgu YOK, kenarlık YOK, köşe yarıçapı YOK.
//  Ayrımı yalnızca 32pt boşluk ve gerektiğinde tek bir saç çizgisi yapar.
//  Varsayılan kap budur.
//

import SwiftUI

struct SectionBlock<Content: View>: View {

    var title: String?
    var subtitle: String?
    var showTopDivider: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.sectionHeaderToContent) {
            if showTopDivider {
                Divider().overlay(ZenithiumColor.hairlineSoft)
                    .padding(.bottom, ZenithiumSpacing.xs)
            }

            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                    if let title {
                        Text(title)
                            .sectionTitle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .zenithiumCaption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
