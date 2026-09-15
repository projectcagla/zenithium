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
import PhotosUI

struct LabImportView: View {

    @State private var model: LabImportViewModel
    @State private var isPickingFile = false
    @State private var selectedPhoto: PhotosPickerItem?
    let onManualEntry: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Called once rows have been written, so the bloodwork screen can reload.
    let onFinish: () -> Void

    init(repository: any BloodMarkerRepository, documents: (any HealthDocumentRepository)? = nil, onManualEntry: @escaping () -> Void = {}, onFinish: @escaping () -> Void) {
        _model = State(initialValue: LabImportViewModel(repository: repository, documents: documents))
        self.onFinish = onFinish
        self.onManualEntry = onManualEntry
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
                    allowedContentTypes: [.pdf, .image],
                    allowsMultipleSelection: false
                ) { result in
                    handle(result)
                }
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else {
                                model.reportFailure("Fotoğraf okunamadı.")
                                return
                            }
                            await model.load(data: data, fileName: "Fotoğraf")
                        } catch { model.reportFailure("Fotoğraf okunamadı: \(error.localizedDescription)") }
                    }
                }
                .interactiveDismissDisabled(model.phase == .saving)
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
                        step(number: 1, text: "PDF tahlil sonucunu veya net bir fotoğrafını seç.")
                        step(number: 2, text: "Zenithium belgeyi cihazında okur. Hiçbir yere gönderilmez.")
                        step(number: 3, text: "Her satırı ayrı onaylarsın. Kaydettiğinde kaynak belge de Belgeler içinde tutulur.")
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
                    Label("Dosyalardan seç", systemImage: "doc.badge.plus")
                        .font(ZenithiumFont.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZenithiumSpacing.l)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZenithiumColor.accent)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Fotoğraflardan seç", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button("Elle değer gir") { dismiss(); onManualEntry() }
                Text(SafetyCopy.clinicianPrompt).zenithiumCaption()
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
                DatePicker("Alınma tarihi", selection: $model.drawDate, in: ...Date(), displayedComponents: .date)
                    .disabled(!model.savedIDs.isEmpty)
                    .onChange(of: model.drawDate) { _, _ in model.invalidateApprovals() }
            } header: {
                Text("Belge")
            } footer: {
                Text(dateFooter)
            }

            if let failure = model.saveFailure {
                Section("Kaydetme sonucu") { Text(failure).foregroundStyle(ZenithiumColor.yellow) }
            }
            Section {
                ForEach($model.rows) { $row in
                    if model.savedIDs.contains(row.id) {
                        Label("\(row.marker.displayName) kaydedildi", systemImage: "checkmark.circle")
                    } else { LabImportRow(row: $row) }
                }
            } header: { Text("Her satırı kontrol edip ayrı ayrı onayla") }
            footer: { Text(reviewFooter) }
            if model.canKeepOriginal {
                Section {
                    Button("Yalnızca kaynak belgeyi sakla") { Task { await model.keepOriginal() } }
                } footer: {
                    Text("Eşikle verilen veya okunamayan sonuçları kesin bir sayıya çevirmeden, belgenin tamamını Belgeler içinde saklayabilirsin.")
                }
            }
            Section { Text(SafetyCopy.clinicianPrompt).zenithiumCaption() }
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
            parts.append("\(model.lowConfidenceCount) satırın okuma güveni düşük.")
        }
        if model.unreadableLineCount > 0 {
            parts.append("\(model.unreadableLineCount) satırda bir belirteç adı gördüm ama sayıyı okuyamadım.")
        }
        parts.append("Hiçbir satır önceden onaylı değildir. Kaydetmeden önce değeri, birimi ve referans aralığını kendi raporunla karşılaştır.")
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
            Text(count == 0 ? "Kaynak belge saklandı" : "\(count) değer kaydedildi")
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
            Button("Elle değer gir") { dismiss(); onManualEntry() }
                .buttonStyle(.borderedProminent)
            if model.canKeepOriginal {
                Button("Kaynak belgeyi sakla") { Task { await model.keepOriginal() } }
                    .buttonStyle(.bordered)
            }
            Text(SafetyCopy.clinicianPrompt).zenithiumCaption()
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
            Button("Kapat") { onFinish(); dismiss() }
                .disabled(model.phase == .saving)
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
        case .failure(let error):
            model.reportFailure("Dosya seçilemedi: \(error.localizedDescription)")
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
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!row.isValid)
                .accessibilityLabel(row.isSelected ? "Bu satırın onayını kaldır" : "Değer, birim ve aralığı kontrol ettim; bu satırı onayla")
                // Every row here is a decision the person is making about their own blood
                // results, so each one gets an acknowledgement.
                .sensoryFeedback(.selection, trigger: row.isSelected)

                VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                    Picker("Belirteç", selection: $row.marker) {
                        ForEach(BiomarkerCatalog.byPanel, id: \.panel) { group in
                            Section(group.panel.displayName) {
                                ForEach(group.markers) { definition in
                                    Text(definition.displayName).tag(BloodMarkerKind.standard(definition.key))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    ConfidenceBadge(confidence: row.confidence, unitIsRecognised: row.unitIsRecognised)
                }

            }
            HStack(spacing: ZenithiumSpacing.m) {
                TextField("Değer", text: $row.valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(ZenithiumFont.body.monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(row.isValid ? ZenithiumColor.textPrimary : ZenithiumColor.red)

                TextField("Birim", text: $row.unitSymbol)
                    .multilineTextAlignment(.trailing)
                    .font(ZenithiumFont.caption)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }

            if row.isThreshold {
                Text("Bu sonuç eşik olarak verilmiş. Kesin ölçüm gibi kaydedilemez; raporunu sakla ve hekiminle değerlendir.").zenithiumCaption()
            }
            Toggle("Raporda referans aralığı var", isOn: $row.hasReference).font(ZenithiumFont.caption)
            if row.hasReference {
                HStack {
                    TextField("Alt sınır", text: $row.referenceMinText).keyboardType(.decimalPad)
                    Text("–")
                    TextField("Üst sınır", text: $row.referenceMaxText).keyboardType(.decimalPad)
                    Text(row.unitSymbol).zenithiumCaption()
                }
                if !row.referenceIsValid { Text("Rapordaki alt veya üst sınırı kontrol et.").zenithiumCaption() }
            } else { Text("Referans aralığı yok").zenithiumCaption() }
            // The line the value came from, verbatim. This is what makes the review real
            // rather than ceremonial — the user can check the parse without opening the PDF.
            Text(row.sourceLine)
                .font(ZenithiumFont.caption2.monospaced())
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Kaynak satır: \(row.sourceLine)")
        }
        .padding(.vertical, ZenithiumSpacing.xs)
        .onChange(of: row.valueText) { _, _ in row.isSelected = false }
        .onChange(of: row.unitSymbol) { _, _ in row.isSelected = false }
        .onChange(of: row.marker) { _, _ in row.isSelected = false }
        .onChange(of: row.hasReference) { _, _ in row.isSelected = false }
        .onChange(of: row.referenceMinText) { _, _ in row.isSelected = false }
        .onChange(of: row.referenceMaxText) { _, _ in row.isSelected = false }
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
