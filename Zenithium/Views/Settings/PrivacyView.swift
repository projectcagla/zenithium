//
//  PrivacyView.swift
//  Zenithium
//
//  The §12 privacy statement: data never leaves the device, no account, no network entitlement.
//

import SwiftUI

struct PrivacyView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(ZenithiumColor.green)
                    .accessibilityHidden(true)

                Text(SafetyCopy.privacyTitle)
                    .font(ZenithiumFont.title)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                Text(SafetyCopy.privacyBody)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SectionCard {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                        ForEach(SafetyCopy.privacyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ZenithiumColor.green)
                                    .accessibilityHidden(true)
                                Text(point)
                                    .font(ZenithiumFont.callout)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if let privacyURL = SystemURL.privacyPolicy {
                    Link(destination: privacyURL) {
                        HStack {
                            Text("Web Gizlilik Politikası")
                                .font(ZenithiumFont.body)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(ZenithiumColor.accent)
                        .padding(.vertical, ZenithiumSpacing.s)
                    }
                }
            }
            .padding(.horizontal, ZenithiumSpacing.l)
            .padding(.vertical, ZenithiumSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Gizlilik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
    }
}
