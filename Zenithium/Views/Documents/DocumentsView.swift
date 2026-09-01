//
//  DocumentsView.swift
//  Zenithium
//
//  The health document vault. Faz 26.
//
//  A timeline and a search field. Zenithium reads and stores these; it does not interpret
//  them, and the screen says so once rather than on every row.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentsView: View {

    @State var viewModel: DocumentsViewModel
    @State private var isPickingFile = false
    @State private var pendingURL: URL?
    @State private var newKind: HealthDocumentKind = .labReport
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Belgeler yükleniyor",
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
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Belgeler")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .searchable(text: $viewModel.query, prompt: "Belgelerde ara")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPickingFile = true } label: {
                        Label("Belge ekle", systemImage: "plus")
                    }
                    .accessibilityLabel("Belge ekle")
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingURL = url
                    newTitle = url.deletingPathExtension().lastPathComponent
                }
            }
            .sheet(item: $pendingURL) { url in
                importSheet(url: url)
            }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.26)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: DocumentsViewModel.Content) -> some View {
        let groups = viewModel.filtered(content)
        VStack(spacing: ZenithiumSpacing.l) {
            if content.documents.isEmpty {
                emptyCard
            } else if groups.isEmpty {
                SectionCard {
                    Text("Aramanla eşleşen belge yok.")
                        .font(ZenithiumFont.callout)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
            } else {
                ForEach(groups, id: \.year) { group in
                    SectionCard(title: "\(group.year)") {
                        VStack(spacing: ZenithiumSpacing.none) {
                            ForEach(group.documents) { document in
                                DocumentRow(document: document) {
                                    Task { await viewModel.delete(document) }
                                }
                                if document.id != group.documents.last?.id {
                                    Divider().overlay(ZenithiumColor.hairlineSoft)
                                }
                            }
                        }
                    }
                }
            }

            Text("Zenithium bu belgeleri okur ve cihazında saklar. İçeriklerini yorumlamaz.")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyCard: some View {
        SectionCard(title: "Henüz belge yok") {
            Text("EKG raporu, görüntüleme sonucu, hekim notu, aşı kartı — hepsini buraya ekleyebilirsin. Metni cihazında okunur, tarihi bulunur ve aranabilir olur.")
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importSheet(url: URL) -> some View {
        NavigationStack {
            Form {
                Section("Belge") {
                    Picker("Tür", selection: $newKind) {
                        ForEach(HealthDocumentKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    TextField("Başlık", text: $newTitle)
                }
                if let error = viewModel.importError {
                    Section {
                        Text(error)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Belge ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { pendingURL = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isImporting ? "Ekleniyor…" : "Ekle") {
                        Task {
                            await viewModel.import(url: url, kind: newKind, title: newTitle)
                            if viewModel.importError == nil { pendingURL = nil }
                        }
                    }
                    .disabled(viewModel.isImporting)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }
}

/// One stored document.
private struct DocumentRow: View {

    let document: HealthDocument
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: ZenithiumSpacing.m) {
            Image(systemName: document.kind.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(ZenithiumColor.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(document.title)
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    // A document's title is how the person finds it again, so it wraps
                    // rather than truncating at the larger type sizes. Yol haritası v4, B7.
                    .lineLimit(2)
                HStack(spacing: ZenithiumSpacing.s) {
                    Text(document.documentDate.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(document.kind.displayName)
                    if document.extractedText.isEmpty {
                        Text("· metin okunamadı")
                    }
                }
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
            }

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(document.title) belgesini sil")
        }
        .padding(.vertical, ZenithiumSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// `URL` is not `Identifiable`, and `sheet(item:)` needs it to be.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
