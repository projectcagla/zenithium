//
//  DisclaimerView.swift
//  Zenithium
//
//  The §12 disclaimer, reachable from Settings and shown during onboarding.
//

import SwiftUI

struct DisclaimerView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                Image(systemName: "cross.case")
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(ZenithiumColor.accent)
                    .accessibilityHidden(true)

                Text(SafetyCopy.disclaimerTitle)
                    .font(ZenithiumFont.title)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                Text(SafetyCopy.disclaimerBody)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SectionCard(title: "Zenithium ne yapar") {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        bullet("Saatinin zaten kaydettiğini okur.")
                        bullet("Bugünü kendi taban çizginle karşılaştırır.")
                        bullet("Ne kadar sert ve neyi çalışacağını önerir.")
                    }
                }

                SectionCard(title: "Ne yapmaz") {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        bullet("Hiçbir şeye teşhis koymaz.")
                        bullet("Sağlığının yerinde olup olmadığını söylemez.")
                        bullet("Hekiminle yapacağın konuşmanın yerine geçmez.")
                        bullet("Hiçbir türde kalori ya da kilo hedefi koymaz.")
                    }
                }
            }
            .padding(.horizontal, ZenithiumSpacing.l)
            .padding(.vertical, ZenithiumSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Yasal uyarı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
            Text("•")
                .foregroundStyle(ZenithiumColor.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
