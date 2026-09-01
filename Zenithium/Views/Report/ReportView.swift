//
//  ReportView.swift
//  Zenithium
//
//  The clinician report. Faz 27.
//
//  Shows exactly what the PDF will contain, then offers to export it. Showing first matters:
//  this is health data about to leave the device by the user's own hand, and they should see
//  every line before they decide to share it.
//

import SwiftUI

// `UIActivityViewController` and the representable below are UIKit's, and SwiftUI does not
// re-export them. The file compiled only as long as something else in the module happened to
// pull UIKit in — which is not a dependency, it is a coincidence. ASSUMPTION REPORT-2
// explains why the bridge is here at all.
import UIKit

struct ReportView: View {

    @State var viewModel: ReportViewModel
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Rapor hazırlanıyor",
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
            .navigationTitle("Hekim raporu")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.28)
        .task { await viewModel.onAppear() }
        .sheet(isPresented: $isSharing) {
            if let url = viewModel.documentURL {
                ShareLinkSheet(url: url)
            }
        }
    }

    @ViewBuilder
    private func loadedBody(_ content: ReportViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            headerCard(content.report)
            ForEach(content.report.sections) { section in
                sectionCard(section)
            }
            exportButton
        }
    }

    private func headerCard(_ report: ClinicianReport) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                Text("\(report.start.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted))")
                    .font(ZenithiumFont.sectionTitle)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(report.disclaimer)
                    .font(ZenithiumFont.footnote)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionCard(_ section: ReportSection) -> some View {
        SectionCard(title: section.title, subtitle: section.caption) {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                ForEach(section.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(ZenithiumFont.callout)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                            Text(row.mean)
                                .font(ZenithiumFont.callout.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text("\(row.range) · \(row.sampleCount) gün")
                                .font(ZenithiumFont.caption.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textTertiary)
                            if let trend = row.trend {
                                Text(trend)
                                    .font(ZenithiumFont.caption)
                                    .foregroundStyle(ZenithiumColor.textTertiary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(ZenithiumFont.footnote.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var exportButton: some View {
        VStack(spacing: ZenithiumSpacing.s) {
            Button {
                Task {
                    await viewModel.export()
                    if viewModel.documentURL != nil { isSharing = true }
                }
            } label: {
                Label(
                    viewModel.isExporting ? "Hazırlanıyor…" : "PDF olarak dışa aktar",
                    systemImage: "square.and.arrow.up"
                )
                .font(ZenithiumFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ZenithiumSpacing.m)
            }
            .buttonStyle(.borderedProminent)
            .tint(ZenithiumColor.accent)
            .disabled(viewModel.isExporting)

            if let error = viewModel.exportError {
                Text(error)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.red)
            }

            Text("Belge cihazında oluşturulur ve hiçbir yere yüklenmez. Nereye gideceğine sen karar verirsin.")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The system share sheet, wrapped.
///
/// ASSUMPTION REPORT-2: `UIActivityViewController` via `UIViewControllerRepresentable`.
///
/// `ArchiveShareSheet` in `DataTransferView` uses `ShareLink` from inside a sheet and works
/// fine, so the bridge is not about nesting being forbidden — the earlier comment here said
/// it was, and that was wrong. The difference is what the sheet contains: the archive sheet
/// is a screen, with a summary and a button, so a `ShareLink` on it is one control among
/// several. This sheet has nothing on it but the share UI, so a `ShareLink` would mean
/// opening a sheet in order to tap the one thing on it and open a second sheet.
///
/// Reversal: replace this with `ShareLink` and drop the enclosing sheet, presenting from the
/// export button directly.
private struct ShareLinkSheet: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
