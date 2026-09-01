//
//  LabImportView.swift
//  Zenithium
//
//  The review screen for an imported laboratory PDF. Faz 23.
//
//  This screen is the safety mechanism, not a convenience. Optical recognition misreads
//  digits, and a misread digit in a medical number is not an acceptable failure — so every
//  row shows the line it came from, says how sure the parser was, and can be edited or
//  switched off. Low-confidence rows arrive switched off: the user opts in to a guess
//  rather than having to notice and opt out of one.
//

import SwiftUI
import UniformTypeIdentifiers

struct LabImportView: View {

    @State private var model: LabImportViewModel
    @State private var isPickingFile = false
    @Environment(\.dismiss) private var dismiss

    /// Called once rows have been written, so the bloodwork screen can reload.
    let onFinish: () -> Void

    init(repository: any BloodMarkerRepository, onFinish: @escaping () -> Void) {
        _model = State(initialValue: LabImportViewModel(repository: repository))
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            content
                .background(ZenithiumColor.background.ignoresSafeArea())
                .navigationTitle("Tahlil içe aktar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .fileImporter(
                    isPresented: $isPickingFile,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    handle(result)
                }
                // Writing values into the record is the one commit in this flow, and it
                // happens behind a sheet that is about to close — so it says so.
                .sensoryFeedback(trigger: model.phase) { _, phase in
                    switch phase {
                    case .finished: return .success
                    case .failed: return .error
                    default: return nil
                    }
                }
        }
        .tint(ZenithiumColor.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            introduction
        case .reading:
            progress("Belge okunuyor…")
        case .reviewing:
            review
        case .saving:
            progress("Kaydediliyor…")
        case .finished(let count):
            finished(count: count)
        case .failed(let message):
            failure(message)
        }
    }

    // MARK: - Introduction

    private var introduction: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.xl) {
                SectionCard(title: "Nasıl çalışır") {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                        step(number: 1, text: "Hastaneden aldığın PDF tahlil sonucunu seç.")
                        step(number: 2, text: "Zenithium belgeyi cihazında okur. Hiçbir yere gönderilmez.")
                        step(number: 3, text: "Bulduğu her satırı sana gösterir; sen onaylarsın.")
                    }
                }

                SectionCard {
                    Label {
                        Text(SafetyCopy.bloodworkRangeCaption)
                            .font(ZenithiumFont.footnote)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                }

                Button {
                    isPickingFile = true
                } label: {
                    Label("PDF seç", systemImage: "doc.badge.plus")
                        .font(ZenithiumFont.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZenithiumSpacing.l)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZenithiumColor.accent)
            }
            .padding(ZenithiumSpacing.xl)
        }
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
            Text("\(number)")
                .font(ZenithiumFont.caption.monospacedDigit())
                .foregroundStyle(ZenithiumColor.background)
                .frame(width: 22, height: 22)
                .background(Circle().fill(ZenithiumColor.accent))
            Text(text)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Review

    private var review: some View {
        List {
            Section {
                LabeledContent("Belge") {
                    Text(model.fileName)
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Kaynak") {
                    Text(model.source.displayName)
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
                DatePicker("Alınma tarihi", selection: $model.drawDate, displayedComponents: .date)
            } header: {
                Text("Belge")
            } footer: {
                Text(dateFooter)
            }

            Section {
                ForEach($model.rows) { $row in
                    LabImportRow(row: $row)
                }
            } header: {
                HStack {
                    Text("Bulunan değerler")
                    Spacer()
                    Button(model.selectedCount == model.rows.count ? "Hiçbiri" : "Tümü") {
                        if model.selectedCount == model.rows.count {
                            model.deselectAll()
                        } else {
                            model.selectAll()
                        }
                    }
                    .font(ZenithiumFont.caption)
                    .textCase(nil)
                }
            } footer: {
                Text(reviewFooter)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ZenithiumColor.background.ignoresSafeArea())
    }

    private var dateFooter: String {
        model.dateWasDetected
            ? "Tarihi belgeden okudum. Yanlışsa değiştir."
            : "Belgede tarih bulamadım — bugünü koydum, doğrusunu sen seç."
    }

    private var reviewFooter: String {
        var parts: [String] = []
        if model.lowConfidenceCount > 0 {
            parts.append("\(model.lowConfidenceCount) satırdan emin değilim; onları kapalı bıraktım.")
        }
        if model.unreadableLineCount > 0 {
            parts.append("\(model.unreadableLineCount) satırda bir belirteç adı gördüm ama sayıyı okuyamadım.")
        }
        parts.append("Kaydetmeden önce her değeri kendi raporunla karşılaştır.")
        return parts.joined(separator: " ")
    }

    // MARK: - Other phases

    private func progress(_ label: String) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            ProgressView()
                .controlSize(.large)
            Text(label)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finished(count: Int) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(ZenithiumColor.green)
            Text("\(count) değer kaydedildi")
                .font(ZenithiumFont.title)
                .foregroundStyle(ZenithiumColor.textPrimary)
            Button("Bitti") {
                onFinish()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(ZenithiumColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ZenithiumSpacing.xl)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(ZenithiumColor.textTertiary)
            Text(message)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Başka bir dosya seç") { isPickingFile = true }
                .buttonStyle(.bordered)
                .tint(ZenithiumColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ZenithiumSpacing.xl)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Kapat") { dismiss() }
        }
        if model.phase == .reviewing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet (\(model.selectedCount))") {
                    Task { await model.save() }
                }
                .disabled(!model.canSave)
            }
        }
    }

    private func handle(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.load(fileURL: url) }
        case .failure:
            break
        }
    }
}

/// One reviewable row.
private struct LabImportRow: View {

    @Binding var row: LabImportViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(spacing: ZenithiumSpacing.m) {
                Button {
                    row.isSelected.toggle()
                } label: {
                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundStyle(row.isSelected ? ZenithiumColor.accent : ZenithiumColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.isSelected ? "Bu değeri kaydetme dışı bırak" : "Bu değeri kaydet")
                // Every row here is a decision the person is making about their own blood
                // results, so each one gets an acknowledgement.
                .sensoryFeedback(.selection, trigger: row.isSelected)

                VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                    Text(row.marker.displayName)
                        .font(ZenithiumFont.headline)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    ConfidenceBadge(confidence: row.confidence, unitIsRecognised: row.unitIsRecognised)
                }

                Spacer(minLength: 8)

                TextField("Değer", text: $row.valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(ZenithiumFont.body.monospacedDigit())
                    .frame(maxWidth: 84)
                    .foregroundStyle(row.isValid ? ZenithiumColor.textPrimary : ZenithiumColor.red)

                TextField("Birim", text: $row.unitSymbol)
                    .multilineTextAlignment(.trailing)
                    .font(ZenithiumFont.caption)
                    .frame(maxWidth: 62)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            // The line the value came from, verbatim. This is what makes the review real
            // rather than ceremonial — the user can check the parse without opening the PDF.
            Text(row.sourceLine)
                .font(ZenithiumFont.caption2.monospaced())
                .foregroundStyle(ZenithiumColor.textTertiary)
                .lineLimit(2)
                .truncationMode(.tail)
                .accessibilityLabel("Kaynak satır: \(row.sourceLine)")
        }
        .padding(.vertical, ZenithiumSpacing.xs)
        .opacity(row.isSelected ? 1 : 0.55)
    }
}

/// How sure the parser was, and why it might not be.
private struct ConfidenceBadge: View {

    let confidence: ParseConfidence
    let unitIsRecognised: Bool

    var body: some View {
        HStack(spacing: ZenithiumSpacing.s) {
            Text(confidence.displayName)
                .font(ZenithiumFont.caption2)
                .padding(.horizontal, ZenithiumSpacing.s)
                .padding(.vertical, ZenithiumSpacing.xxs)
                .background(Capsule().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
            if !unitIsRecognised {
                Text("birim tanınmadı")
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Güven: \(confidence.displayName)\(unitIsRecognised ? "" : ", birim tanınmadı")")
    }

    private var tint: Color {
        switch confidence {
        case .high: return ZenithiumColor.green
        case .medium: return ZenithiumColor.yellow
        case .low: return ZenithiumColor.red
        }
    }
}
