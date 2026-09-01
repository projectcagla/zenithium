//
//  LabImportViewModel.swift
//  Zenithium
//
//  Drives the laboratory PDF import. Faz 23.
//
//  The one rule this screen exists to enforce: nothing the parser produced is written until
//  a person has approved it row by row. The view model therefore holds *editable* rows, not
//  parsed values — the user can change the marker, the number, the unit and the date, and
//  what gets saved is what they left on screen.
//

import Foundation
import Observation

@MainActor
@Observable
final class LabImportViewModel {

    /// One reviewable row. Everything on it is editable, because everything on it is a guess.
    struct Row: Identifiable, Equatable {

        let id: UUID

        /// Whether this row will be saved. Low-confidence rows start off.
        var isSelected: Bool

        var marker: BloodMarkerKind
        var valueText: String
        var unitSymbol: String

        let confidence: ParseConfidence
        let unitIsRecognised: Bool
        let isThreshold: Bool
        let printedRange: MarkerRange?
        let sourceLine: String
        let pageNumber: Int

        /// The parsed number, or `nil` when the user has edited it into something unreadable.
        var value: Double? {
            LabReportParser.decimalValue(
                of: valueText.trimmingCharacters(in: .whitespaces),
                sawDot: valueText.contains("."),
                sawComma: valueText.contains(",")
            )
        }

        var isValid: Bool {
            guard let value else { return false }
            return value.isFinite && !marker.displayName.isEmpty
        }

        init(parsed: ParsedLabValue) {
            self.id = parsed.id
            self.isSelected = parsed.confidence.isPreselected
            self.marker = parsed.marker
            self.unitSymbol = parsed.unitSymbol
            self.confidence = parsed.confidence
            self.unitIsRecognised = parsed.unitIsRecognised
            self.isThreshold = parsed.isThreshold
            self.printedRange = parsed.printedRange
            self.sourceLine = parsed.sourceLine
            self.pageNumber = parsed.pageNumber

            let digits = parsed.marker.fractionDigits
            self.valueText = ZenithiumFormat.metric(parsed.value, digits: digits)
        }
    }

    /// Where the import has got to.
    enum Phase: Equatable {
        case idle
        case reading
        case reviewing
        case saving
        case finished(savedCount: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var fileName: String = ""
    private(set) var source: LabTextSource = .textLayer
    private(set) var unreadableLineCount = 0

    /// Rows the user is reviewing.
    var rows: [Row] = []

    /// The draw date every saved row is stamped with.
    var drawDate: Date = Date()

    /// Whether the parser found the date itself, which the screen says out loud so the user
    /// knows whether to check it.
    private(set) var dateWasDetected = false

    private let reader = LabDocumentReader()
    private let repository: any BloodMarkerRepository
    private let nowProvider: @Sendable () -> Date

    init(
        repository: any BloodMarkerRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.nowProvider = nowProvider
        self.drawDate = nowProvider()
    }

    var selectedCount: Int {
        rows.filter { $0.isSelected && $0.isValid }.count
    }

    var canSave: Bool {
        selectedCount > 0 && phase == .reviewing
    }

    /// How many rows the parser was unsure about — the number the header leads with, because
    /// it tells the user how much of this screen actually needs their attention.
    var lowConfidenceCount: Int {
        rows.filter { $0.confidence == .low }.count
    }

    // MARK: - Import

    func load(fileURL: URL) async {
        phase = .reading
        do {
            let document = try await reader.read(fileURL: fileURL)
            apply(LabReportParser.parse(document, referenceDate: nowProvider()))
        } catch let failure as LabImportFailure {
            phase = .failed(failure.message)
        } catch {
            phase = .failed(LabImportFailure.unreadableDocument.message)
        }
    }

    /// Apply an already-parsed draft. Kept separate from `load` so tests can drive the
    /// review screen without a PDF.
    func apply(_ draft: LabReportDraft) {
        fileName = draft.fileName
        source = draft.source
        unreadableLineCount = draft.unreadableLineCount
        rows = draft.values.map(Row.init(parsed:))

        if let detected = draft.detectedDrawDate {
            drawDate = detected
            dateWasDetected = true
        } else {
            drawDate = nowProvider()
            dateWasDetected = false
        }

        phase = rows.isEmpty ? .failed(LabImportFailure.noRecognisableMarkers.message) : .reviewing
    }

    func selectAll() {
        for index in rows.indices where rows[index].isValid {
            rows[index].isSelected = true
        }
    }

    func deselectAll() {
        for index in rows.indices {
            rows[index].isSelected = false
        }
    }

    // MARK: - Saving

    /// Write the approved rows.
    ///
    /// The laboratory's own printed band wins over the catalogue's when the report carried
    /// one: it is the band that lab actually used, and the one printed next to the value the
    /// user is looking at.
    func save() async {
        guard canSave else { return }
        phase = .saving

        let approved = rows.filter { $0.isSelected && $0.isValid }
        var saved = 0
        do {
            for row in approved {
                guard let value = row.value else { continue }
                let reference = row.printedRange ?? row.marker.referenceRange
                try await repository.saveBloodMarker(
                    id: UUID(),
                    marker: row.marker,
                    value: value,
                    unitSymbol: row.unitSymbol,
                    referenceRange: reference,
                    optimalRange: row.marker.optimalRange,
                    drawnAt: drawDate,
                    note: importNote(for: row)
                )
                saved += 1
            }
            phase = .finished(savedCount: saved)
        } catch {
            // Partial success is still success for the rows that landed, so the count is
            // reported rather than swallowed.
            phase = saved > 0
                ? .finished(savedCount: saved)
                : .failed("Kaydedilemedi: \(error.localizedDescription)")
        }
    }

    /// The provenance note stored with each imported value, so a number can always be traced
    /// back to the document it came from.
    private func importNote(for row: Row) -> String {
        var parts = [fileName.isEmpty ? "PDF içe aktarım" : fileName]
        parts.append("s.\(row.pageNumber)")
        if source == .opticalRecognition { parts.append("görüntüden okundu") }
        if row.isThreshold { parts.append("eşik değer olarak basılmış") }
        return parts.joined(separator: " · ")
    }
}
