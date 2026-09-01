//
//  BloodworkViewModel.swift
//  Zenithium
//
//  The Bloodwork screen. Spec §7 for the data, §12 for the hard rule that governs everything
//  built on it: reference ranges and trends only — no interpretation, no flagging, no
//  treatment suggestion anywhere in this file or the views that read it.
//

import Foundation
import Observation

@MainActor
@Observable
final class BloodworkViewModel {

    /// One marker's history, newest first.
    struct MarkerSeries: Sendable, Equatable, Identifiable {
        let marker: BloodMarkerKind
        let entries: [BloodMarkerSnapshot]

        var id: String { marker.storageKey }
        var latest: BloodMarkerSnapshot? { entries.first }

        /// The change between the two most recent draws, in the marker's unit.
        ///
        /// A number, not a judgement: §12 forbids Zenithium saying whether a direction is
        /// good. The view renders it as "+4 mg/dL since March", never as "improving".
        var changeSincePrevious: Double? {
            guard entries.count >= 2 else { return nil }
            return entries[0].value - entries[1].value
        }

        /// How fast the marker is moving, in its own unit per year.
        ///
        /// A least-squares slope over every draw, reported and never judged: §12 forbids
        /// Zenithium saying whether a direction is good, so the view renders "yılda +12
        /// mg/dL" and stops there. Yol haritası v4, C3.
        ///
        /// `nil` below three draws or under six months of span. Two points always define a
        /// line, and a line through two draws six weeks apart says more about which morning
        /// the blood was taken than about anything happening in the body.
        var annualRate: Double? {
            guard entries.count >= Self.minimumDrawsForRate else { return nil }
            let ordered = entries.sorted { $0.drawnAt < $1.drawnAt }
            guard let origin = ordered.first?.drawnAt,
                  let last = ordered.last?.drawnAt else { return nil }

            let spanDays = last.timeIntervalSince(origin) / 86_400
            guard spanDays >= Self.minimumSpanDaysForRate else { return nil }

            return MathSupport.leastSquaresSlope(
                xs: ordered.map { $0.drawnAt.timeIntervalSince(origin) / (365.25 * 86_400) },
                ys: ordered.map(\.value)
            )
        }

        /// Below this many draws a rate is arithmetic rather than a trend.
        static let minimumDrawsForRate = 3

        /// Below this span a rate is dominated by when the blood was taken.
        static let minimumSpanDaysForRate: Double = 180

        /// The axis range for the sparkline: the reference band widened to hold every value.
        var axisRange: ClosedRange<Double>? {
            let values = entries.map(\.value)
            guard let dataMin = values.min(), let dataMax = values.max() else { return nil }
            let reference = entries.first?.referenceRange
            let lower = min(dataMin, reference?.minimum ?? dataMin)
            let upper = max(dataMax, reference?.maximum ?? dataMax)
            guard upper > lower else { return (lower - 1)...(upper + 1) }
            let padding = (upper - lower) * 0.1
            return (lower - padding)...(upper + padding)
        }
    }

    /// One panel and the markers recorded under it.
    struct PanelGroup: Sendable, Equatable, Identifiable {
        let panel: BiomarkerPanel
        let series: [MarkerSeries]
        var id: String { panel.rawValue }
    }

    struct Content: Sendable, Equatable {
        let series: [MarkerSeries]

        /// The same markers grouped by panel, in panel order. Yol haritası v4, C3.
        ///
        /// A flat list ordered by draw date answers "what came back most recently"; a
        /// clinician's own report is organised by panel, and so is the question a person
        /// actually asks — "how is my iron", not "what did I measure on the ninth".
        /// Markers the catalogue does not recognise keep their place in `series` and are
        /// simply absent here rather than being filed under a guess.
        let panels: [PanelGroup]
        /// §12 — shown above the list, never omitted.
        let disclaimer: String

        /// Observations from `LabInsightEngine`, strongest first. Anything with
        /// `requiresClinician` set is rendered with the clinician prompt attached.
        let observations: [LabObservation]
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let repository: any BloodMarkerRepository

    /// Read only for biological sex, which decides which reference band applies.
    private let profile: (any ProfileRepository)?

    /// Handed to the import sheet so it can write the rows the user approves.
    var markerRepository: any BloodMarkerRepository { repository }

    init(repository: any BloodMarkerRepository, profile: (any ProfileRepository)? = nil) {
        self.repository = repository
        self.profile = profile
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        do {
            let markers = try await repository.bloodMarkers()
            guard !markers.isEmpty else {
                state = .noData(reason: .nothingLogged(what: "results"))
                return
            }
            // A missing profile is not an error here — it only means the sex-agnostic
            // band is used, which is the wider one.
            var sex = BiologicalSexValue.notSet
            if let profile, let snapshot = try? await profile.profile() {
                sex = snapshot.biologicalSex
            }
            let series = Self.group(markers)
            state = .loaded(
                Content(
                    series: series,
                    panels: Self.groupByPanel(series),
                    disclaimer: SafetyCopy.bloodworkDisclaimer,
                    observations: LabInsightEngine.observations(markers: markers, sex: sex)
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Saves a draw. Ranges default to the marker's built-in ones when the user does not
    /// enter their own lab's.
    func save(
        id: UUID = UUID(),
        marker: BloodMarkerKind,
        value: Double,
        unitSymbol: String,
        referenceRange: MarkerRange?,
        optimalRange: MarkerRange?,
        drawnAt: Date,
        note: String
    ) async {
        guard value.isFinite else {
            saveError = .invalidEngineInput(reason: "Sayısal bir değer gir.")
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            _ = try await repository.saveBloodMarker(
                id: id,
                marker: marker,
                value: value,
                unitSymbol: unitSymbol.isEmpty ? marker.defaultUnitSymbol : unitSymbol,
                referenceRange: referenceRange ?? marker.referenceRange,
                optimalRange: optimalRange ?? marker.optimalRange,
                drawnAt: drawnAt,
                note: note
            )
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    func delete(id: UUID) async {
        do {
            try await repository.deleteBloodMarker(id: id)
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    /// Groups marker series by panel, panels in their catalogue order.
    nonisolated static func groupByPanel(_ series: [MarkerSeries]) -> [PanelGroup] {
        var buckets: [BiomarkerPanel: [MarkerSeries]] = [:]
        for entry in series {
            guard let panel = entry.marker.panel else { continue }
            buckets[panel, default: []].append(entry)
        }
        return BiomarkerPanel.allCases
            .sorted { $0.order < $1.order }
            .compactMap { panel in
                guard let markers = buckets[panel], !markers.isEmpty else { return nil }
                return PanelGroup(
                    panel: panel,
                    series: markers.sorted { $0.marker.displayName < $1.marker.displayName }
                )
            }
    }

    /// Groups draws by marker, each series newest first, series ordered by most recent draw.
    static func group(_ markers: [BloodMarkerSnapshot]) -> [MarkerSeries] {
        var buckets: [String: [BloodMarkerSnapshot]] = [:]
        var kinds: [String: BloodMarkerKind] = [:]
        for marker in markers {
            let key = marker.marker.storageKey
            buckets[key, default: []].append(marker)
            kinds[key] = marker.marker
        }
        return buckets.compactMap { key, entries -> MarkerSeries? in
            guard let kind = kinds[key] else { return nil }
            return MarkerSeries(
                marker: kind,
                entries: entries.sorted { $0.drawnAt > $1.drawnAt }
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.latest?.drawnAt ?? .distantPast
            let right = rhs.latest?.drawnAt ?? .distantPast
            if left == right { return lhs.marker.displayName < rhs.marker.displayName }
            return left > right
        }
    }
}
