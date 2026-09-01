//
//  ReportViewModel.swift
//  Zenithium
//
//  The clinician report screen. Faz 27.
//

import Foundation
import Observation

@MainActor
@Observable
final class ReportViewModel {

    struct Content: Sendable, Equatable {
        let report: ClinicianReport
    }

    private(set) var state: ViewState<Content> = .loading

    /// The rendered document, once the user has asked for it. Held so the share sheet has
    /// something to hand over, and cleared when the window changes.
    private(set) var documentURL: URL?
    private(set) var isExporting = false
    private(set) var exportError: String?

    private let records: any BiometricDayRepository
    private let markers: any BloodMarkerRepository
    private let profile: any ProfileRepository
    private let vitals: (any VitalsProviding)?
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        records: any BiometricDayRepository,
        markers: any BloodMarkerRepository,
        profile: any ProfileRepository,
        vitals: (any VitalsProviding)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.records = records
        self.markers = markers
        self.profile = profile
        self.vitals = vitals
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        let now = nowProvider()
        let calendar = calendarProvider()
        let start = now.addingTimeInterval(-Double(ClinicianReportBuilder.windowDays) * 86_400)

        do {
            let days = try await records.dayRecords(from: start, through: now)
            let bloodMarkers = (try? await markers.bloodMarkers()) ?? []
            let sex = (try? await profile.profile())?.biologicalSex ?? .notSet

            // Only the signals a clinician would recognise. Sending eighteen rows including
            // audio exposure would bury the four that matter.
            var readings: [VitalReading] = []
            if let vitals {
                for sign in Self.reportedVitals {
                    if let samples = try? await vitals.fetchVitalSamples(
                        sign: sign,
                        days: ClinicianReportBuilder.windowDays,
                        now: now,
                        calendar: calendar
                    ), !samples.isEmpty {
                        readings.append(VitalsEngine.reading(for: sign, samples: samples))
                    }
                }
            }

            let report = ClinicianReportBuilder.build(
                days: days,
                vitals: readings,
                markers: bloodMarkers,
                sex: sex,
                now: now,
                calendar: calendar
            )
            guard !report.isEmpty else {
                state = .noData(reason: .notEnoughHistory(daysAvailable: days.count, daysRequired: ClinicianReportBuilder.minimumSamplesForRow))
                return
            }
            documentURL = nil
            state = .loaded(Content(report: report))
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// The vital signs worth putting in front of a clinician.
    static let reportedVitals: [VitalSign] = [
        .vo2Max, .heartRateRecovery, .walkingHeartRate, .walkingSpeed, .walkingSteadiness
    ]

    /// Render the PDF and keep it for the share sheet.
    ///
    /// Written to the caches directory, not documents: this is a derived artefact the user
    /// is about to hand somewhere else, and it should not persist as though it were data.
    func export() async {
        guard case .loaded(let content) = state else { return }
        isExporting = true
        defer { isExporting = false }

        let report = content.report
        let data = await Task.detached(priority: .userInitiated) {
            ReportDocumentRenderer.render(report)
        }.value

        do {
            let directory = FileManager.default.temporaryDirectory
            let stamp = ISO8601DateFormatter.reportStamp.string(from: nowProvider())
            let url = directory.appendingPathComponent("Zenithium-\(stamp).pdf")
            try data.write(to: url, options: .completeFileProtection)
            documentURL = url
            exportError = nil
        } catch {
            exportError = "Belge oluşturulamadı."
        }
    }
}

@MainActor
private extension ISO8601DateFormatter {
    /// Date only, for a filename somebody will see in a share sheet.
    static let reportStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        return formatter
    }()
}
