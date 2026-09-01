//
//  JournalView.swift
//  Zenithium
//
//  Günlük ve içgörüler.
//
//  §12 dili burada özellikle sıkı: motor "şunu kaydettiğin gecelerde ölçüm şu kadar
//  farklıydı" der. Ekranda "sebep", "zarar", "iyi", "kötü" kelimeleri geçmez ve her
//  içgörü kaç gözleme dayandığını söyler.
//

import SwiftUI

struct JournalView: View {

    @State var viewModel: JournalViewModel
    @State private var isAddingSupplement = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Günlük yükleniyor",
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Günlük")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $isAddingSupplement) {
                SupplementEditorView(viewModel: viewModel)
            }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.32)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: JournalViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            behaviorSection(content)
            moodSection(content)
            supplementSection(content)
            insightSection(content)
        }
    }

    // MARK: - Davranışlar

    private func behaviorSection(_ content: JournalViewModel.Content) -> some View {
        SectionCard(
            title: "Bugün",
            subtitle: "Geçerli olanlara dokun — kaydet düğmesi yok"
        ) {
            FlowLayout(spacing: ZenithiumSpacing.s) {
                ForEach(JournalBehavior.allCases) { behavior in
                    BehaviorChip(
                        behavior: behavior,
                        isSelected: content.today.behaviors.contains(behavior)
                    ) {
                        Task { await viewModel.toggle(behavior) }
                    }
                }
            }
        }
    }

    private func moodSection(_ content: JournalViewModel.Content) -> some View {
        SectionCard(title: "Nasıl hissediyorsun") {
            HStack(spacing: ZenithiumSpacing.m) {
                ForEach(MoodRating.allCases) { mood in
                    let isSelected = content.today.mood == mood
                    Button {
                        Task { await viewModel.setMood(mood) }
                    } label: {
                        VStack(spacing: ZenithiumSpacing.xs) {
                            Image(systemName: mood.symbolName)
                                .font(.system(size: 19))
                                .symbolVariant(isSelected ? .fill : .none)
                            Text(mood.displayName)
                                .font(ZenithiumFont.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZenithiumSpacing.m)
                        .background {
                            RoundedRectangle(cornerRadius: ZenithiumRadius.large, style: .continuous)
                                .fill(isSelected ? ZenithiumColor.accent.opacity(0.16) : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: ZenithiumRadius.large, style: .continuous)
                                .strokeBorder(
                                    isSelected ? ZenithiumColor.accent : ZenithiumColor.hairline,
                                    lineWidth: 1
                                )
                        }
                        .foregroundStyle(
                            isSelected ? ZenithiumColor.accent : ZenithiumColor.textSecondary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.displayName)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            // A mood is a selection, not a commit — the lightest feedback there is, and
            // only because the tile's own colour change can be missed mid-scroll.
            .sensoryFeedback(.selection, trigger: content.today.mood)
        }
    }

    // MARK: - Takviyeler

    /// Supplement courses, and the control to start one. Yol haritası v4, C5.
    ///
    /// A course is stated once and runs until it is ended, because nobody taps "creatine"
    /// every morning for four months. What it buys is the comparison below: the nights it
    /// covered against the nights it did not.
    private func supplementSection(_ content: JournalViewModel.Content) -> some View {
        SectionCard(
            title: "Takviyeler",
            subtitle: "Başlangıcını bir kez söyle, karşılaştırmayı motor yapsın"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                if content.supplements.isEmpty {
                    Text("Kayıtlı bir kür yok. Bir takviyeye başladığında ekle — birkaç hafta sonra ölçümlerinin o pencerede nasıl seyrettiğini burada görürsün.")
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: ZenithiumSpacing.none) {
                        ForEach(content.supplements) { course in
                            SupplementRow(course: course, viewModel: viewModel)
                            if course.id != content.supplements.last?.id {
                                Divider().overlay(ZenithiumColor.hairlineSoft)
                            }
                        }
                    }
                }

                Button {
                    isAddingSupplement = true
                } label: {
                    Label("Takviye ekle", systemImage: "plus")
                        .font(ZenithiumFont.label)
                }
                .buttonStyle(.bordered)
                .tint(ZenithiumColor.accent)
            }
        }
    }

    // MARK: - İçgörüler

    private func insightSection(_ content: JournalViewModel.Content) -> some View {
        SectionCard(
            title: "Örüntüler",
            subtitle: "Son \(content.windowDays) günden, \(content.loggedDaysInWindow) kayıtlı gün"
        ) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                outcomePicker

                if content.insights.isEmpty {
                    emptyInsightState(content)
                } else {
                    ForEach(content.insights) { insight in
                        InsightRow(result: insight)
                        if insight.id != content.insights.last?.id {
                            Divider().overlay(ZenithiumColor.hairlineSoft)
                        }
                    }

                    Text("Bunlar gözlem, sebep değil. Bir örüntünün arkasında kaydetmediğin başka bir şey de olabilir.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ZenithiumSpacing.xxs)
                }
            }
        }
    }

    private var outcomePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ZenithiumSpacing.s) {
                ForEach(CorrelationOutcome.allCases) { outcome in
                    let isSelected = outcome == viewModel.outcome
                    Button {
                        viewModel.select(outcome: outcome)
                    } label: {
                        Text(outcome.displayName)
                            .font(ZenithiumFont.caption)
                            .padding(.horizontal, ZenithiumSpacing.m)
                            .padding(.vertical, ZenithiumSpacing.s)
                            .background {
                                Capsule().fill(
                                    isSelected ? ZenithiumColor.accent.opacity(0.16) : Color.clear
                                )
                            }
                            .overlay {
                                Capsule().strokeBorder(
                                    isSelected ? ZenithiumColor.accent : ZenithiumColor.hairline,
                                    lineWidth: 1
                                )
                            }
                            .foregroundStyle(
                                isSelected ? ZenithiumColor.accent : ZenithiumColor.textSecondary
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, ZenithiumSpacing.xxs)
        }
        .sensoryFeedback(.selection, trigger: viewModel.outcome)
        .accessibilityLabel("Karşılaştırılacak ölçüm")
    }

    private func emptyInsightState(_ content: JournalViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            Text(
                content.needsMoreDays > 0
                    ? "Korelasyon analizleri için \(content.needsMoreDays) günlük ek kayıt gerekiyor."
                    : "Anlamlı bir karşılaştırma için yeterli veri çifti henüz oluşmadı."
            )
            .font(ZenithiumFont.callout)
            .foregroundStyle(ZenithiumColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Güvenilir bir korelasyon için her alışkanlıkta en az \(CorrelationEngine.minimumSamplesPerGroup) gün uygulanan ve \(CorrelationEngine.minimumSamplesPerGroup) gün uygulanmayan veri çifti gereklidir.")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Bir davranış rozeti.
private struct BehaviorChip: View {

    let behavior: JournalBehavior
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenithiumSpacing.s) {
                Image(systemName: behavior.symbolName)
                    .imageScale(.small)
                    .symbolVariant(isSelected ? .fill : .none)
                Text(behavior.displayName)
                    .font(ZenithiumFont.caption)
            }
            .padding(.horizontal, ZenithiumSpacing.m)
            .padding(.vertical, ZenithiumSpacing.s)
            .background {
                Capsule().fill(isSelected ? ZenithiumColor.accent.opacity(0.16) : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? ZenithiumColor.accent : ZenithiumColor.hairline,
                    lineWidth: 1
                )
            }
            .foregroundStyle(isSelected ? ZenithiumColor.accent : ZenithiumColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(behavior.accessibilityName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Tek bir örüntü satırı.
private struct InsightRow: View {

    let result: CorrelationResult

    /// Ok yalnızca yön gösterir. Renk semantiktir ama tek başına anlam taşımaz —
    /// cümle zaten yönü söylüyor.
    private var arrow: String {
        result.difference < 0 ? "arrow.down" : "arrow.up"
    }

    private var tint: Color {
        guard result.isConsistent else { return ZenithiumColor.textTertiary }
        return result.movesUpward ? ZenithiumColor.green : ZenithiumColor.yellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(spacing: ZenithiumSpacing.s) {
                Image(systemName: result.subject.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .accessibilityHidden(true)

                Text(result.subject.displayName)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)

                Spacer(minLength: 8)

                HStack(spacing: ZenithiumSpacing.xs) {
                    Image(systemName: arrow)
                        .font(.caption2.weight(.bold))
                    Text(ZenithiumFormat.metric(abs(result.difference), digits: result.outcome.fractionDigits))
                        .font(ZenithiumFont.dataValue)
                    Text(result.outcome.unitSymbol)
                        .font(ZenithiumFont.caption)
                }
                .foregroundStyle(tint)
            }

            Text(CorrelationEngine.summary(for: result))
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ZenithiumSpacing.s) {
                Text(result.isConsistent ? "Tutarlı" : "Henüz net değil")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(result.isConsistent ? tint : ZenithiumColor.textTertiary)
                Text("·")
                    .foregroundStyle(ZenithiumColor.textTertiary)
                Text("\(result.magnitude.displayName) etki")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
        }
        .padding(.vertical, ZenithiumSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.subject.accessibilityName)
        .accessibilityValue(CorrelationEngine.summary(for: result))
    }
}

/// Rozetleri satır satır saran basit bir yerleşim.
///
/// `LazyVGrid` sabit sütun ister; rozetler farklı genişlikte olduğu için sığdıkça yan yana,
/// sığmadıkça alt satıra geçmeleri gerekiyor.
struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: CGFloat = 1
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                rows += 1
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One course: its name, its window, and the control to close it.
private struct SupplementRow: View {

    let course: SupplementCourse
    let viewModel: JournalViewModel

    var body: some View {
        HStack(spacing: ZenithiumSpacing.m) {
            Image(systemName: "pills")
                .foregroundStyle(course.isOngoing ? ZenithiumColor.accent : ZenithiumColor.textTertiary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(course.name)
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .lineLimit(2)
                Text(window)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            Spacer(minLength: 0)

            if course.isOngoing {
                Button("Bitir") {
                    Task { await viewModel.endSupplement(course) }
                }
                .font(ZenithiumFont.caption)
                .buttonStyle(.bordered)
                .tint(ZenithiumColor.textSecondary)
            }
        }
        .padding(.vertical, ZenithiumSpacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(course.name)
        .accessibilityValue(window)
        .accessibilityAction(named: course.isOngoing ? "Kürü bitir" : "Sil") {
            Task {
                if course.isOngoing {
                    await viewModel.endSupplement(course)
                } else {
                    await viewModel.deleteSupplement(course)
                }
            }
        }
    }

    private var window: String {
        let start = course.startedAt.formatted(date: .abbreviated, time: .omitted)
        guard let endedAt = course.endedAt else {
            return "\(start)'ten beri · \(course.days(through: Date())) gün"
        }
        return "\(start) – \(endedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Starting a course. One field and a date, because that is all the comparison needs.
private struct SupplementEditorView: View {

    let viewModel: JournalViewModel

    @State private var name = ""
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Adı", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Not — doz, marka, neden", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("Bugünden başlar. Zenithium bunun bir şeye yol açtığını söylemez — yalnızca kürün kapsadığı gecelerle diğerlerinin nasıl farklılaştığını bildirir.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Takviye ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Başlat") {
                        Task {
                            await viewModel.startSupplement(named: name, note: note)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }
}
