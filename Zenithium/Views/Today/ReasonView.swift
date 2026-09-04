//
//  ReasonView.swift
//  Zenithium
//
//  Şartname: "Neden?" Ekranı.
//  Ritim: Tek iddia → yedi eşit adım. Kart YOK (tamamen kartsız L1 akış).
//  Adımlar:
//    1 Senin verin
//    2 Hesap
//    3 Literatür
//    4 Ne göstermiyor
//    5 Uygulanabilirlik
//    6 Güven
//    7 Ne değişirse
//

import SwiftUI

struct ReasonView: View {

    let recommendation: Recommendation?
    let state: ViewState<Recommendation>
    var namespace: Namespace.ID? = nil
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var embedInNavigation: Bool = true

    init(
        recommendation: Recommendation,
        embedInNavigation: Bool = true,
        namespace: Namespace.ID? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.recommendation = recommendation
        self.state = .loaded(recommendation)
        self.embedInNavigation = embedInNavigation
        self.namespace = namespace
        self.onDismiss = onDismiss
    }

    init(
        state: ViewState<Recommendation>,
        embedInNavigation: Bool = true,
        namespace: Namespace.ID? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.state = state
        self.recommendation = state.value
        self.embedInNavigation = embedInNavigation
        self.namespace = namespace
        self.onDismiss = onDismiss
    }

    var body: some View {
        if embedInNavigation {
            NavigationStack {
                scrollContent
                    .navigationTitle("Neden?")
                    .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                if let onDismiss {
                                    onDismiss()
                                } else {
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ZenithiumColor.textSecondary)
                            }
                        }
                    }
            }
        } else {
            VStack(spacing: 0) {
                if onDismiss != nil {
                    HStack {
                        Button {
                            onDismiss?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("Neden?")
                            .font(ZenithiumFont.sectionTitle)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Spacer()
                        Color.clear.frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, ZenithiumSpacing.screenEdge)
                    .padding(.top, ZenithiumSpacing.m)
                }
                scrollContent
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            ViewStateContainer(
                state: state,
                loadingLabel: "Kanıt zinciri çözümleniyor",
                loadingLayout: .cards,
                retry: nil,
                requestAccess: nil
            ) { item in
                loadedContent(item)
            }
            .padding(.horizontal, ZenithiumSpacing.screenEdge)
            .padding(.bottom, ZenithiumSpacing.xxl)
            .padding(.top, ZenithiumSpacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func loadedContent(_ item: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // [L1] KAHRAMAN — iddianın kendisi (sectionTitle) + güç rozeti
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.headline)
                        .sectionTitle()
                        .foregroundStyle(ZenithiumColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if let namespace {
                        strengthBadge(item.strength)
                            .matchedGeometryEffect(id: "today-reason-hero", in: namespace)
                    } else {
                        strengthBadge(item.strength)
                    }
                }

                Text(item.body)
                    .zenithiumSecondary()
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // [L1] Yedi adım, hepsi L1, aralarında hairlineSoft çizgi
            VStack(alignment: .leading, spacing: 16) {
                if let namespace {
                    stepRow(
                        number: 1,
                        title: "Senin verin",
                        content: userEvidenceText(item)
                    )
                    .matchedGeometryEffect(id: "today-reason-score", in: namespace)
                } else {
                    stepRow(
                        number: 1,
                        title: "Senin verin",
                        content: userEvidenceText(item)
                    )
                }

                stepDivider

                stepRow(
                    number: 2,
                    title: "Hesap",
                    content: "Biyometrik modeller ve taban sapma eşikleri analiz edilerek deterministik olarak üretildi."
                )

                stepDivider

                stepRow(
                    number: 3,
                    title: "Literatür",
                    content: literatureText(item)
                )

                stepDivider

                stepRow(
                    number: 4,
                    title: "Ne göstermiyor",
                    content: limitationsText(item)
                )

                stepDivider

                stepRow(
                    number: 5,
                    title: "Uygulanabilirlik",
                    content: item.populationNote ?? "Çalışma kohortu genel sporcu ve bireysel fizyoloji popülasyonu ile uyumludur."
                )

                stepDivider

                stepRow(
                    number: 6,
                    title: "Güven",
                    content: "Ölçüm ve kanıt güveni: %\(Int((item.confidence.value * 100).rounded()))"
                )

                stepDivider

                stepRow(
                    number: 7,
                    title: "Ne değişirse",
                    content: item.wouldChangeIf.joined(separator: " • ")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepDivider: some View {
        Rectangle()
            .fill(ZenithiumColor.hairlineSoft)
            .frame(height: 1)
    }

    private func stepRow(number: Int, title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenithiumColor.accent)

                Text(title)
                    .zenithiumLabel()
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .textCase(.uppercase)
            }

            Text(content)
                .zenithiumSecondary()
                .foregroundStyle(ZenithiumColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func strengthBadge(_ strength: ClaimStrength) -> some View {
        let title: String = {
            switch strength {
            case .recommendation: return "TAVSİYE"
            case .suggestion: return "ÖNERİ"
            case .observation: return "GÖZLEM"
            }
        }()

        return Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ZenithiumColor.accent.opacity(0.15))
            .foregroundStyle(ZenithiumColor.accent)
            .clipShape(Capsule())
    }

    private func userEvidenceText(_ item: Recommendation) -> String {
        if item.evidence.isEmpty {
            return "Kişisel toparlanma ve uyku tabanı ölçümleri."
        }
        return item.evidence.map { "\($0.sourceCategory): \($0.summary)" }.joined(separator: " • ")
    }

    private func literatureText(_ item: Recommendation) -> String {
        if item.references.isEmpty {
            return "Hakemli spor bilimleri literatürü ve konsensüs kılavuzları."
        }
        return item.references.map { "\($0.authors) (\($0.year))" }.joined(separator: "; ")
    }

    private func limitationsText(_ item: Recommendation) -> String {
        if item.limitations.isEmpty {
            return "Optik fotopletismografi ve tek eksenli ivmeölçer hassasiyet kısıtları geçerlidir."
        }
        return item.limitations.map { "[\($0.code)] \($0.explanation)" }.joined(separator: " ")
    }
}

#Preview("Neden · dolu") {
    ReasonView(state: .loaded(PreviewFixtures.sampleRecommendation))
}

#Preview("Neden · kalibrasyon") {
    ReasonView(state: .calibrating(progress: 0.35, daysCollected: 5, daysRequired: 14))
}

#Preview("Neden · veri yok") {
    ReasonView(state: .noData(reason: .notEnoughHistory(daysAvailable: 0, daysRequired: 14)))
}
