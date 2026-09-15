import SwiftUI

struct ReasonView: View {

    let recommendation: Recommendation?
    let state: ViewState<Recommendation>
    var calculationSteps: [String] = []
    var relatedRecommendations: [Recommendation] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID? = nil
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var embedInNavigation: Bool = true

    init(
        recommendation: Recommendation,
        embedInNavigation: Bool = true,
        namespace: Namespace.ID? = nil,
        calculationSteps: [String] = [],
        relatedRecommendations: [Recommendation] = [],
        onDismiss: (() -> Void)? = nil
    ) {
        self.recommendation = recommendation
        self.state = .loaded(recommendation)
        self.embedInNavigation = embedInNavigation
        self.namespace = namespace
        self.calculationSteps = calculationSteps
        self.relatedRecommendations = relatedRecommendations
        self.onDismiss = onDismiss
    }

    init(
        state: ViewState<Recommendation>,
        embedInNavigation: Bool = true,
        namespace: Namespace.ID? = nil,
        calculationSteps: [String] = [],
        relatedRecommendations: [Recommendation] = [],
        onDismiss: (() -> Void)? = nil
    ) {
        self.state = state
        self.recommendation = state.value
        self.embedInNavigation = embedInNavigation
        self.namespace = namespace
        self.calculationSteps = calculationSteps
        self.relatedRecommendations = relatedRecommendations
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
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Neden ekranını kapat")
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
                actionCallout: "Günün önerisi oluştuktan sonra karar gerekçesi burada incelenebilir.",
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
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func loadedContent(_ item: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.sectionSpacing) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                Text("KARARIN ARKASINDA").zenithiumEyebrow()
                Text(item.headline).screenTitle().fixedSize(horizontal: false, vertical: true)
                if let namespace {
                    confidenceRing(item)
                        .matchedGeometryEffect(id: "today-reason-score", in: namespace)
                        .frame(maxWidth: .infinity)
                    strengthBadge(item.strength)
                        .matchedGeometryEffect(id: "today-reason-hero", in: namespace)
                } else {
                    confidenceRing(item).frame(maxWidth: .infinity)
                    strengthBadge(item.strength)
                }
                Text(item.body).zenithiumSecondary()
            }
            SectionBlock(title: "01 · Senin verin") {
                if item.evidence.isEmpty {
                    Text("Bu karar için ayrıntılı ölçüm kanıtı sağlanmadı.").zenithiumSecondary()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(item.evidence) { node in
                            evidenceRow(node, isLast: node.id == item.evidence.last?.id)
                        }
                    }
                }
            }
            SectionBlock(title: "02 · Hesap") {
                if calculationSteps.isEmpty {
                    Text("Bu kayıtta ayrıntılı hesap adımları bulunmuyor.").zenithiumSecondary()
                } else {
                    ForEach(Array(calculationSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").zenithiumSecondary()
                    }
                }
            }
            SectionBlock(title: "03 · Bilimsel kaynaklar") {
                if item.references.isEmpty {
                    Text("Bu günlük karara tekil bir kaynak bağlanmamış.").zenithiumSecondary()
                    ForEach(relatedRecommendations.filter { !$0.references.isEmpty }) { related in
                        DisclosureGroup(related.headline) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(related.body).zenithiumSecondary()
                                ForEach(related.references) { reference in referenceRow(reference) }
                            }
                            .padding(.top, 12)
                        }
                        .font(ZenithiumFont.secondary)
                        .tint(ZenithiumColor.accent)
                    }
                } else {
                    ForEach(item.references) { reference in
                        referenceRow(reference)
                    }
                }
            }
            SectionBlock(title: "04 · Ne göstermiyor") {
                Text(limitationsText(item)).zenithiumSecondary()
            }
            SectionBlock(title: "05 · Sana uygulanabilirliği") {
                Text(item.populationNote ?? "Bu kayıt için kişiye uygulanabilirlik notu sağlanmadı.").zenithiumSecondary()
            }
            SectionBlock(title: "06 · Güven") {
                Text("Ölçüm ve kanıt güveni: \(ZenithiumFormat.percent(item.confidence.value)) · \(item.confidence.rating.displayName)").zenithiumSecondary()
                ForEach(item.confidence.penaltyReasons, id: \.self) { reason in
                    Text(reason).zenithiumCaption()
                }
                Text("Güven puanı, önerinin kesin gerçekleşme olasılığı değildir.").zenithiumCaption()
            }
            SectionBlock(title: "07 · Ne değişirse") {
                ForEach(item.wouldChangeIf, id: \.self) { condition in
                    Label(condition, systemImage: "arrow.triangle.2.circlepath").zenithiumSecondary()
                }
            }
            Text(SafetyCopy.disclaimer(for: item.disclaimerTier) ?? SafetyCopy.disclaimerFooter)
                .zenithiumCaption()
                .padding(.top, ZenithiumSpacing.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceRing(_ item: Recommendation) -> some View {
        ArcGauge(
            progress: item.confidence.value,
            gradient: Gradient(colors: [ZenithiumColor.spectrumIndigo, ZenithiumColor.accent]),
            trackColor: ZenithiumColor.accent.opacity(0.10),
            accessibilityLabel: "Karar güveni",
            accessibilityValue: ZenithiumFormat.percent(item.confidence.value)
        ) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("%").heroUnit()
                    Text(ZenithiumFormat.score(item.confidence.value * 100))
                        .heroNumeral().lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                Text("GÜVEN").zenithiumEyebrow()
            }
        }
    }

    private func evidenceRow(_ node: EvidenceNode, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: evidenceSymbol(node.sourceCategory))
                    .font(.system(size: 15))
                    .foregroundStyle(ZenithiumColor.accent)
                    .frame(width: 28, height: 28)
                Rectangle().fill(isLast ? Color.clear : ZenithiumColor.hairline).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(evidenceTitle(node.sourceCategory)).zenithiumEyebrow()
                Text(node.summary).zenithiumBody()
                Text("\(evidenceDate(node.timestamp)) · \(node.sampleCount) örnek")
                    .zenithiumCaption()
            }
            .padding(.bottom, 24)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func evidenceDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "tr_TR")))
    }

    private func evidenceSymbol(_ source: String) -> String {
        let key = source.lowercased()
        if key.contains("sleep") || key.contains("uyku") { return "moon" }
        if key.contains("load") || key.contains("yük") || key.contains("strain") { return "chart.bar" }
        if key.contains("lab") || key.contains("blood") { return "drop" }
        return "waveform.path.ecg"
    }

    private func evidenceTitle(_ source: String) -> String {
        let key = source.lowercased()
        if key.contains("sleep") { return "Uyku" }
        if key.contains("recovery") { return "Toparlanma" }
        if key.contains("load") || key.contains("strain") { return "Antrenman yükü" }
        if key.contains("lab") || key.contains("blood") { return "Laboratuvar" }
        return source
    }

    private func referenceRow(_ reference: Reference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reference.citation).zenithiumSecondary().textSelection(.enabled)
            Text(reference.grade.displayName).zenithiumCaption()
            if let doi = reference.doi, let url = URL(string: "https://doi.org/" + doi) {
                Link("DOI · " + doi, destination: url).font(ZenithiumFont.caption).tint(ZenithiumColor.accent)
            }
            if let pmid = reference.pmid, let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/" + pmid + "/") {
                Link("PubMed · " + pmid, destination: url).font(ZenithiumFont.caption).tint(ZenithiumColor.accent)
            }
            Text(reference.doesNotShow).zenithiumCaption()
            if reference.needsVerification {
                Label("Kaynak ayrıntıları doğrulanmayı bekliyor", systemImage: "exclamationmark.circle")
                    .zenithiumCaption()
            }
        }
        .padding(.bottom, 12)
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

    private func limitationsText(_ item: Recommendation) -> String {
        item.limitations.isEmpty
            ? "Bu kayıtta özel bir sınırlama belirtilmedi. Ölçümler ve modeller tıbbi tanı yerine geçmez."
            : item.limitations.map(\.explanation).joined(separator: "\n\n")
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
