//
//  HybridViewModel.swift
//  Zenithium
//
//  Hibrit mercek: Hyrox seansları ve kompanse koşu.
//

import Foundation
import Observation

@MainActor
@Observable
final class HybridViewModel {

    struct Content: Sendable, Equatable {
        let sessions: [HybridSessionSnapshot]

        /// En son seansın tam çözümlemesi.
        let latestAnalysis: HybridSessionOutput?
        let latestSession: HybridSessionSnapshot?

        /// Seanslar arası kompanse koşu cezasının seyri, eskiden yeniye.
        let penaltyTrend: [PenaltyPoint]

        /// §12 dilinde tek cümlelik yön.
        let guidance: String?

        var hasHistory: Bool { !sessions.isEmpty }
    }

    struct PenaltyPoint: Sendable, Equatable, Hashable, Identifiable {
        let date: Date
        let penalty: Double
        var id: Date { date }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let repository: any HybridSessionRepository
    private let profiles: any ProfileRepository
    private let baselines: any BaselineRepository
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        repository: any HybridSessionRepository,
        profiles: any ProfileRepository,
        baselines: any BaselineRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.repository = repository
        self.profiles = profiles
        self.baselines = baselines
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        do {
            let sessions = try await repository.recentHybridSessions(limit: 40)
            guard let latest = sessions.first else {
                state = .noData(reason: .nothingLogged(what: "hibrit seans"))
                return
            }

            let context = try await heartRateContext()
            let analysis = HybridEngine.analyse(
                latest.input(
                    restingHeartRate: context.resting,
                    maxHeartRate: context.maximum
                )
            )

            let trend = sessions
                .compactMap { session -> PenaltyPoint? in
                    guard let penalty = session.compromisedPenalty else { return nil }
                    return PenaltyPoint(date: session.performedAt, penalty: penalty)
                }
                .sorted { $0.date < $1.date }

            state = .loaded(
                Content(
                    sessions: sessions,
                    latestAnalysis: analysis,
                    latestSession: latest,
                    penaltyTrend: trend,
                    guidance: HybridEngine.guidance(for: analysis)
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Bir seansı kaydeder. Motor kayıt anında bir kez çalışır ve özet değerler saklanır;
    /// tam çözümleme her zaman yeniden üretilebilir.
    func save(
        id: UUID = UUID(),
        kind: HybridSessionKind,
        performedAt: Date,
        segments: [HybridSegment],
        note: String
    ) async {
        guard !segments.isEmpty else {
            saveError = .invalidEngineInput(reason: "En az bir koşu veya istasyon ekleyin.")
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let context = try await heartRateContext()
            let freshPace = try await freshPaceReference()
            let output = HybridEngine.analyse(
                HybridSessionInput(
                    segments: segments,
                    freshPaceSecondsPerKilometre: freshPace,
                    restingHeartRate: context.resting,
                    maxHeartRate: context.maximum,
                    performedAt: performedAt
                )
            )

            _ = try await repository.saveHybridSession(
                HybridSessionSnapshot(
                    id: id,
                    performedAt: performedAt,
                    timeZoneIdentifier: calendarProvider().timeZone.identifier,
                    kind: kind,
                    segments: segments,
                    freshPaceSecondsPerKilometre: freshPace,
                    totalDurationSeconds: output.totalDurationSeconds,
                    roxzoneSeconds: output.roxzoneSeconds,
                    compromisedPenalty: output.compromisedRunning?.penalty,
                    sessionLoad: sessionLoad(for: output),
                    note: note
                )
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
            try await repository.deleteHybridSession(id: id)
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    // MARK: - Yardımcılar

    /// Seansın 0–100 ölçeğindeki yükü.
    ///
    /// Süreye dayanıyor: hibrit bir seansın kalp atışı verisi zaten günlük zorlanmaya
    /// giriyor, o yüzden buradaki yük kas modeline beslenecek olan — ve orada önemli olan
    /// istasyonda geçirilen süredir.
    private func sessionLoad(for output: HybridSessionOutput) -> Double {
        let minutes = output.totalStationSeconds / TimeConversion.secondsPerMinute
        // 60 dakikalık istasyon süresi tam yükü verir; bir tam yarışta istasyon süresi
        // tipik olarak 30–40 dakikadır, yani tam yarış 55–70 bandına oturur.
        return MathSupport.clamp(minutes / 60 * 100, to: EngineConstants.Fatigue.sessionLoadRange)
    }

    private func heartRateContext() async throws -> (resting: Double, maximum: Double) {
        let profile = try await profiles.profile()
        let states = try await baselines.baselines()
        let resting = states[.restingHeartRate]?.mean ?? MetricKind.restingHeartRate.prior.mean
        let age = profile.characteristics.age(at: nowProvider(), calendar: calendarProvider())
        let resolved = StrainEngine.resolveMaxHeartRate(
            override: profile.maxHeartRateOverride,
            observed: nil,
            age: age
        )
        return (resting, resolved.value)
    }

    /// Taze tempo referansı.
    ///
    /// ASSUMPTION HYROX-3: şimdilik yok — dayanıklılık merceği (Faz 15) koşu temposunu
    /// okumaya başlayana kadar motor ilk turu referans alacak ve arayüz bunu söyleyecek.
    /// Uydurma bir referans koymak, cezayı sistematik olarak yanlış hesaplardı.
    private func freshPaceReference() async throws -> Double? {
        nil
    }
}
