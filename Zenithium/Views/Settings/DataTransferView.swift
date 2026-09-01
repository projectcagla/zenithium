//
//  DataTransferView.swift
//  Zenithium
//
//  Moving the whole store to another phone. Yol haritası v4, C9.
//

import SwiftUI
import UniformTypeIdentifiers

struct DataTransferView: View {

    @State private var viewModel: DataTransferViewModel
    @State private var isPickingArchive = false
    @State private var isSharing = false

    init(service: ArchiveService) {
        _viewModel = State(initialValue: DataTransferViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                explanation
                exportCard
                importCard
            }
            .padding(ZenithiumSpacing.l)
        }
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Veri taşıma")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingArchive,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await viewModel.inspect(url: url) }
        }
        .sheet(isPresented: $isSharing, onDismiss: { viewModel.clearExport() }) {
            if case .ready(let url) = viewModel.exportState {
                ArchiveShareSheet(url: url)
            }
        }
        .onChange(of: viewModel.exportState) { _, state in
            if case .ready = state { isSharing = true }
        }
    }

    // MARK: - Copy

    private var explanation: some View {
        SectionCard(title: "Neden burada", subtitle: "Zenithium'un sunucusu yok") {
            Text("""
            Verilerin yalnızca bu telefonda duruyor — hesap yok, bulut yok, hiçbir şey \
            dışarı gitmiyor. Bunun bedeli şu: yeni bir telefona geçtiğinde geçmişin \
            kendiliğinden gelmez. Buradan tek bir dosya yazıp yeni cihazda okutabilirsin.
            """)
            .font(ZenithiumFont.callout)
            .foregroundStyle(ZenithiumColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Export

    private var exportCard: some View {
        SectionCard(title: "Dışa aktar", subtitle: "Tek dosya, .zenithium") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text("Gün kayıtların, günlüğün, tahlillerin, seansların, ağrı geçmişin ve kasadaki belgeler tek dosyaya yazılır.")
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch viewModel.exportState {
                case .working:
                    HStack(spacing: ZenithiumSpacing.s) {
                        ProgressView().tint(ZenithiumColor.accent)
                        Text("Yazılıyor…")
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                case .failed(let message):
                    Text(message)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.red)
                        .fixedSize(horizontal: false, vertical: true)
                case .idle, .ready:
                    EmptyView()
                }

                Button {
                    Task { await viewModel.export() }
                } label: {
                    Text("Arşiv oluştur")
                        .font(ZenithiumFont.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZenithiumColor.accent)
                .disabled(viewModel.exportState == .working)
            }
        }
    }

    // MARK: - Import

    private var importCard: some View {
        SectionCard(title: "İçe aktar", subtitle: "Var olanın üstüne eklenir") {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text("""
                İçe aktarma hiçbir şeyi silmez — arşivdeki kayıtlar mevcutların üstüne \
                yazılır, eksikler eklenir. Aynı arşivi iki kez okutmak tek kez okutmakla \
                aynı sonucu verir.
                """)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                importBody
            }
        }
        .sensoryFeedback(trigger: viewModel.importState) { _, state in
            switch state {
            case .finished: return .success
            case .failed: return .error
            default: return nil
            }
        }
    }

    @ViewBuilder
    private var importBody: some View {
        switch viewModel.importState {
        case .idle:
            Button {
                isPickingArchive = true
            } label: {
                Text("Arşiv dosyası seç")
                    .font(ZenithiumFont.label)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(ZenithiumColor.accent)

        case .reading:
            labelledProgress("Arşiv okunuyor…")

        case .awaitingConfirmation(let counts, let omittedFiles):
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text(counts.summary)
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if omittedFiles {
                    Text("Bu arşiv belge dosyalarını içermiyor — kasadaki PDF'ler taşınmayacak, kayıtları taşınacak.")
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: ZenithiumSpacing.m) {
                    Button("Vazgeç") { viewModel.cancelImport() }
                        .buttonStyle(.bordered)
                        .tint(ZenithiumColor.textSecondary)
                    Button {
                        Task { await viewModel.confirmRestore() }
                    } label: {
                        Text("İçe aktar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZenithiumColor.accent)
                }
                .font(ZenithiumFont.label)
            }

        case .restoring:
            labelledProgress("İçe aktarılıyor…")

        case .finished(let counts):
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Label("İçe aktarıldı", systemImage: "checkmark.circle.fill")
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.green)
                Text(counts.summary)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Başka bir arşiv oku") { viewModel.cancelImport() }
                    .font(ZenithiumFont.label)
                    .buttonStyle(.bordered)
                    .tint(ZenithiumColor.accent)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text(message)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tekrar dene") { viewModel.cancelImport() }
                    .font(ZenithiumFont.label)
                    .buttonStyle(.bordered)
                    .tint(ZenithiumColor.accent)
            }
        }
    }

    private func labelledProgress(_ text: String) -> some View {
        HStack(spacing: ZenithiumSpacing.s) {
            ProgressView().tint(ZenithiumColor.accent)
            Text(text)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// The archive's share sheet, wrapping `ShareLink` so the file can be sent anywhere the
/// person keeps files.
///
/// Named apart from `ReportView`'s sheet deliberately. Both were called `ShareLinkSheet`;
/// `private` keeps that legal, but one is a UIKit bridge and this one is not, and a reader
/// who finds the wrong one draws the wrong conclusion about which bridges this app has.
private struct ArchiveShareSheet: View {

    let url: URL

    var body: some View {
        VStack(spacing: ZenithiumSpacing.xl) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 44, weight: .regular, design: .rounded))
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            Text("Arşiv hazır")
                .font(ZenithiumFont.sectionTitle)
                .foregroundStyle(ZenithiumColor.textPrimary)

            Text(url.lastPathComponent)
                .font(ZenithiumFont.caption.monospaced())
                .foregroundStyle(ZenithiumColor.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)

            ShareLink(item: url) {
                Text("Paylaş veya Dosyalar'a kaydet")
                    .font(ZenithiumFont.label)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ZenithiumColor.accent)
        }
        .padding(ZenithiumSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
