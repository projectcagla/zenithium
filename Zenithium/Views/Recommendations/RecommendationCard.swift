//
//  RecommendationCard.swift
//  Zenithium
//
//  Renders a single evidence-backed recommendation with 7-step traceable chain.
//  Faz 34 Bölüm B.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RecommendationCard: View {

    let recommendation: Recommendation
    @State private var isTraceExpanded = false
    @State private var copiedLocator: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            // Header: Domain, Strength Badge & Confidence
            headerSection

            // Headline & Body
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.headline)
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.body)
                    .font(ZenithiumFont.body)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Confidence meter bar
            confidenceMeter

            // Contradiction or unverified callout (if any)
            contradictionAndVerificationBanners

            // Expandable 7-Step Evidence Trace Button
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isTraceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.accent)
                    Text("Bilimsel Kanıt ve Karar Zinciri (7 Adım)")
                        .font(ZenithiumFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Spacer()
                    Image(systemName: isTraceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Expanded 7-Step Chain
            if isTraceExpanded {
                traceChainView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Disclaimer Footer (if tier != .none)
            if let disclaimer = SafetyCopy.disclaimer(for: recommendation.disclaimerTier) {
                Divider().overlay(ZenithiumColor.hairlineSoft)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(ZenithiumColor.textTertiary)
                    Text(disclaimer)
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(ZenithiumSpacing.l)
        .background(ZenithiumColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ZenithiumColor.hairline, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: ZenithiumSpacing.s) {
            Label(recommendation.domain.displayName, systemImage: recommendation.domain.symbolName)
                .font(ZenithiumFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(ZenithiumColor.textTertiary)

            Spacer()

            strengthBadge(recommendation.strength)
        }
    }

    private func strengthBadge(_ strength: ClaimStrength) -> some View {
        let (title, fg, bg): (String, Color, Color) = {
            switch strength {
            case .recommendation:
                return ("TAVSİYE", ZenithiumColor.green, ZenithiumColor.green.opacity(0.15))
            case .suggestion:
                return ("ÖNERİ", ZenithiumColor.yellow, ZenithiumColor.yellow.opacity(0.15))
            case .observation:
                return ("GÖZLEM", ZenithiumColor.textSecondary, ZenithiumColor.surfaceElevated)
            }
        }()

        return Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }

    // MARK: - Confidence Meter

    private var confidenceMeter: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenithiumColor.hairline)
                        .frame(height: 4)

                    Capsule()
                        .fill(confidenceFillColor)
                        .frame(width: max(4, geometry.size.width * CGFloat(recommendation.confidence.value)), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Kanıt ve Ölçüm Güveni")
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                Spacer()
                Text("%\(Int((recommendation.confidence.value * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
        }
    }

    private var confidenceFillColor: Color {
        if recommendation.confidence.value >= 0.70 {
            return ZenithiumColor.green
        } else if recommendation.confidence.value >= 0.45 {
            return ZenithiumColor.yellow
        } else {
            return ZenithiumColor.red
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var contradictionAndVerificationBanners: some View {
        if !recommendation.contradictions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recommendation.contradictions, id: \.0.id) { pair in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ZenithiumColor.yellow)
                        Text("Literatürde Görüş Ayrılığı: \(pair.0.authors.components(separatedBy: ",").first ?? pair.0.id) (\(pair.0.year)) ile \(pair.1.authors.components(separatedBy: ",").first ?? pair.1.id) (\(pair.1.year)) farklı sonuçlara varıyor. İddia zayıflatıldı.")
                            .font(ZenithiumFont.caption2)
                            .foregroundStyle(ZenithiumColor.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(ZenithiumSpacing.s)
            .background(ZenithiumColor.yellow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        let unverified = recommendation.references.filter(\.needsVerification)
        if !unverified.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(unverified) { ref in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ZenithiumColor.yellow)
                        Text("\(ref.id) kaynağının tam künyesi doğrulama bekliyor; bu nedenle öneri seviyesinde tutuldu.")
                            .font(ZenithiumFont.caption2)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(ZenithiumSpacing.s)
            .background(ZenithiumColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - 7-Step Evidence Trace Chain

    private var traceChainView: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Divider().overlay(ZenithiumColor.hairlineSoft)

            // Adım 1: İddia Gücü ve Dil Sözleşmesi
            traceStep(
                number: 1,
                title: "İddia Gücü & Dil Sözleşmesi",
                systemImage: "character.bubble"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    let permits = recommendation.strength.permitsImperative ? "var" : "yok"
                    Text("Derece: \(recommendation.strength.displayName) (Emir kipi izni: \(permits))")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    Text("Cümle yapısı ve dil tonu, dayandığı bilimsel kanıt tasarımının taşıyabileceği güç seviyesine kısıtlanmıştır.")
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                }
            }

            // Adım 2: Kullanıcı Verisi Kanıtları
            if !recommendation.evidence.isEmpty {
                traceStep(
                    number: 2,
                    title: "Kullanıcı Biyometrik Kanıtı",
                    systemImage: "waveform.path.ecg"
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recommendation.evidence) { node in
                            HStack(alignment: .firstTextBaseline) {
                                Text("• \(node.sourceCategory):")
                                    .font(ZenithiumFont.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(ZenithiumColor.textPrimary)
                                Text(node.summary)
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                    }
                }
            }

            // Adım 3: Sınırlılıklar ve Kapsam Kısıtları
            if !recommendation.limitations.isEmpty {
                traceStep(
                    number: 3,
                    title: "Metodolojik Sınırlar",
                    systemImage: "exclamationmark.shield"
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recommendation.limitations) { lim in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(lim.code)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(lim.isBlocking ? ZenithiumColor.red : ZenithiumColor.yellow)
                                Text(lim.explanation)
                                    .font(ZenithiumFont.caption2)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Adım 4: Bilimsel Literatür Kaynakları
            if !recommendation.references.isEmpty {
                traceStep(
                    number: 4,
                    title: "Akademik Literatür & Ne Göstermiyor",
                    systemImage: "books.vertical.fill"
                ) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        ForEach(recommendation.references) { ref in
                            referenceBlock(ref)
                        }
                    }
                }
            }

            // Adım 5: Popülasyon Transferi
            if let popNote = recommendation.populationNote {
                traceStep(
                    number: 5,
                    title: "Popülasyon Uyumu (Transfer)",
                    systemImage: "person.2"
                ) {
                    Text(popNote)
                        .font(ZenithiumFont.caption2)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Adım 6: Güven Skoru & Ceza Kırılımı
            traceStep(
                number: 6,
                title: "Güven Kırılımı & Cezalar",
                systemImage: "chart.bar.xaxis"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nihai Güven: %\(Int((recommendation.confidence.value * 100).rounded())) (\(recommendation.confidence.rating.displayName))")
                        .font(ZenithiumFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(ZenithiumColor.textPrimary)

                    if recommendation.confidence.penaltyReasons.isEmpty {
                        Text("Herhangi bir veri kalitesi veya popülasyon cezası uygulanmadı.")
                            .font(ZenithiumFont.caption2)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    } else {
                        ForEach(recommendation.confidence.penaltyReasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 4) {
                                Text("−")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ZenithiumColor.yellow)
                                Text(reason)
                                    .font(ZenithiumFont.caption2)
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                    }
                }
            }

            // Adım 7: Fikrini Ne Değiştirir? (Falsifiability)
            traceStep(
                number: 7,
                title: "Fikrini Ne Değiştirir? (Yanlışlanabilirlik)",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.wouldChangeIf, id: \.self) { condition in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.accent)
                            Text(condition)
                                .font(ZenithiumFont.caption2)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func traceStep<Content: View>(
        number: Int,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.accent)
                    .frame(width: 16, height: 16)
                    .background(ZenithiumColor.surfaceElevated)
                    .clipShape(Circle())

                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenithiumColor.textTertiary)

                Text(title)
                    .font(ZenithiumFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(ZenithiumColor.textPrimary)
            }

            content()
                .padding(.leading, 22)
        }
    }

    private func referenceBlock(_ ref: Reference) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("[\(ref.id)]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.accent)

                Text(ref.grade.displayName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(ZenithiumColor.surfaceElevated)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .clipShape(Capsule())

                Spacer()

                if let loc = ref.locator {
                    Button {
                        UIPasteboard.general.string = loc
                        copiedLocator = ref.id
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if copiedLocator == ref.id { copiedLocator = nil }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(copiedLocator == ref.id ? "Kopyalandı" : loc)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                            Image(systemName: copiedLocator == ref.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(copiedLocator == ref.id ? ZenithiumColor.green : ZenithiumColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(ref.authors) (\(ref.year)). \(ref.title). \(ref.venue).")
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // "Ne göstermiyor" kutusu
            HStack(alignment: .top, spacing: 4) {
                Text("NE GÖSTERMİYOR:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.textTertiary)
                Text(ref.doesNotShow)
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .background(ZenithiumColor.surfaceElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(8)
        .background(ZenithiumColor.surfaceElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
