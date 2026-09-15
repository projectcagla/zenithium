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
        var hasReference: Bool
        var referenceMinText: String
        var referenceMaxText: String
        var printedRange: MarkerRange? {
            guard hasReference else { return nil }
            return MarkerRange(minimum: Self.number(referenceMinText), maximum: Self.number(referenceMaxText))
        }
        private static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
        var referenceIsValid: Bool {
            guard hasReference else { return true }
            guard !referenceMinText.isEmpty || !referenceMaxText.isEmpty else { return false }
            for text in [referenceMinText, referenceMaxText] where !text.isEmpty {
                guard let n = Self.number(text), n.isFinite, n >= 0 else { return false }
            }
            if let low = Self.number(referenceMinText), let high = Self.number(referenceMaxText), low > high { return false }
            return true
        }
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
            return value.isFinite && value >= 0 && !marker.displayName.isEmpty && referenceIsValid && !isThreshold
                && (try? LabRecording.prepare(marker: marker, value: value, unit: unitSymbol, reference: printedRange ?? .unbounded)) != nil
        }

        init(parsed: ParsedLabValue) {
            self.id = parsed.id
            self.isSelected = false
            self.marker = parsed.marker
            self.unitSymbol = parsed.unitSymbol
            self.confidence = parsed.confidence
            self.unitIsRecognised = parsed.unitIsRecognised
            self.isThreshold = parsed.isThreshold
            self.hasReference = parsed.printedRange?.isBounded == true
            self.referenceMinText = parsed.printedRange?.minimum.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? ""
            self.referenceMaxText = parsed.printedRange?.maximum.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? ""
            self.sourceLine = parsed.sourceLine
            self.pageNumber = parsed.pageNumber

            self.valueText = String(parsed.value).replacingOccurrences(of: ".", with: ",")
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

    private let coordinator: LabImportCoordinator
    private(set) var savedIDs: Set<UUID> = []
    private(set) var saveFailure: String?
    private(set) var canKeepOriginal = false
    private let nowProvider: @Sendable () -> Date

    init(
        repository: any BloodMarkerRepository,
        documents: (any HealthDocumentRepository)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = LabImportCoordinator(repository: repository, documents: documents)
        self.nowProvider = nowProvider
        self.drawDate = nowProvider()
    }

    var selectedCount: Int {
        rows.filter { $0.isSelected && $0.isValid && !savedIDs.contains($0.id) }.count
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
        guard phase != .reading && phase != .saving else { return }
        canKeepOriginal = false
        phase = .reading
        do {
            apply(try await coordinator.read(fileURL: fileURL))
            canKeepOriginal = true
        } catch let failure as LabImportFailure {
            phase = .failed(failure.message)
        } catch {
            phase = .failed(LabImportFailure.unreadableDocument.message)
        }
    }

    /// Apply an already-parsed draft. Kept separate from `load` so tests can drive the
    /// review screen without a PDF.
    func apply(_ draft: LabReportDraft) {
        savedIDs = []
        saveFailure = nil
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

    func load(data: Data, fileName: String) async {
        guard phase != .reading && phase != .saving else { return }
        canKeepOriginal = false
        phase = .reading
        do { apply(try await coordinator.read(data: data, fileName: fileName)); canKeepOriginal = true }
        catch { phase = .failed(error.localizedDescription) }
    }

    func invalidateApprovals() {
        for index in rows.indices where !savedIDs.contains(rows[index].id) { rows[index].isSelected = false }
    }

    func keepOriginal() async {
        guard canKeepOriginal, phase != .saving else { return }
        phase = .saving
        do {
            try await coordinator.saveOriginal(drawnAt: drawDate)
            phase = .finished(savedCount: savedIDs.count)
        } catch { phase = .failed("Belge saklanamadı: \(error.localizedDescription)") }
    }

    func reportFailure(_ message: String) { phase = .failed(message) }

    // MARK: - Saving

    /// Write the approved rows.
    ///
    /// The laboratory's own printed band wins over the catalogue's when the report carried
    /// one: it is the band that lab actually used, and the one printed next to the value the
    /// user is looking at.
    func save() async {
        guard canSave else { return }
        phase = .saving

        saveFailure = nil
        let approved = rows.filter { $0.isSelected && $0.isValid && !savedIDs.contains($0.id) }.compactMap { row -> LabApprovedRow? in
            guard let value = row.value else { return nil }
            return LabApprovedRow(id: row.id, marker: row.marker, value: value, unit: row.unitSymbol,
                                  reference: row.printedRange ?? .unbounded, note: importNote(for: row))
        }
        let outcome = await coordinator.save(approved, drawnAt: drawDate)
        savedIDs.formUnion(outcome.savedIDs)
        if let failure = outcome.failure {
            saveFailure = "\(savedIDs.count) satır kaydedildi. \(failure) Kalanları kontrol edip yeniden deneyebilirsin."
            phase = .reviewing
        } else {
            phase = .finished(savedCount: savedIDs.count)
        }
    }

    /// The provenance note stored with each imported value, so a number can always be traced
    /// back to the document it came from.
    private func importNote(for row: Row) -> String {
        var parts = [fileName.isEmpty ? "PDF içe aktarım" : fileName]
        parts.append("s.\(row.pageNumber)")
        parts.append("Kaynak satır: \(row.sourceLine)")
        parts.append("Okuma güveni: \(row.confidence.displayName)")
        if source == .opticalRecognition { parts.append("görüntüden okundu") }
        if row.isThreshold { parts.append("eşik değer olarak basılmış") }
        return parts.joined(separator: " · ")
    }
}
