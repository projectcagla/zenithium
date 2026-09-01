//
//  DataTransferViewModel.swift
//  Zenithium
//
//  Export and import of the whole store. Yol haritası v4, C9.
//
//  Two flows, deliberately asymmetric. Export is one tap: write the file, hand it to the
//  share sheet, done — there is nothing to confirm because nothing changes. Import is two
//  steps: read the archive, show what is in it, and only write once the person has seen the
//  counts. Restoring is the only operation in the app that can put someone else's numbers
//  into their history, so it does not happen on a single tap.
//

import Foundation
import Observation

@MainActor
@Observable
final class DataTransferViewModel {

    /// Where the export flow has got to.
    enum ExportState: Equatable {
        case idle
        case working
        case ready(URL)
        case failed(String)
    }

    /// Where the import flow has got to.
    enum ImportState: Equatable {
        case idle
        case reading
        /// Read and understood, waiting for the person to confirm.
        case awaitingConfirmation(ArchiveCounts, omittedFiles: Bool)
        case restoring
        case finished(ArchiveCounts)
        case failed(String)
    }

    private(set) var exportState: ExportState = .idle
    private(set) var importState: ImportState = .idle

    private let service: ArchiveService
    private let nowProvider: @Sendable () -> Date

    /// The archive read but not yet applied. Held rather than re-read so the counts the
    /// person confirmed are the counts that get written.
    private var pending: ZenithiumArchive?

    init(service: ArchiveService, nowProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.nowProvider = nowProvider
    }

    // MARK: - Export

    func export() async {
        exportState = .working
        do {
            let archive = try await service.archive(now: nowProvider())
            let directory = FileManager.default.temporaryDirectory
            let url = try await service.write(archive, into: directory)
            exportState = .ready(url)
        } catch {
            exportState = .failed(message(for: error))
        }
    }

    /// Clear the export once the share sheet has closed, so the next tap writes a fresh file
    /// rather than sharing a stale one.
    func clearExport() {
        exportState = .idle
    }

    // MARK: - Import

    /// Read a picked archive and describe it. Nothing is written yet.
    func inspect(url: URL) async {
        importState = .reading
        do {
            let archive = try await service.read(from: url)
            pending = archive
            importState = .awaitingConfirmation(
                archive.counts,
                omittedFiles: archive.omittedDocumentFiles
            )
        } catch {
            pending = nil
            importState = .failed(message(for: error))
        }
    }

    /// Apply the archive the person just confirmed.
    func confirmRestore() async {
        guard let archive = pending else { return }
        importState = .restoring
        do {
            let written = try await service.restore(archive)
            pending = nil
            importState = .finished(written)
        } catch {
            importState = .failed(message(for: error))
        }
    }

    func cancelImport() {
        pending = nil
        importState = .idle
    }

    // MARK: - Errors

    private func message(for error: any Error) -> String {
        if let failure = error as? ArchiveFailure {
            return [failure.errorDescription, failure.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        if let zenithium = error as? ZenithiumError {
            return zenithium.errorDescription ?? "Bir şeyler ters gitti"
        }
        return "Bir şeyler ters gitti"
    }
}
