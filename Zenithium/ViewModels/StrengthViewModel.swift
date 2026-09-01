//
//  StrengthViewModel.swift
//  Zenithium
//
//  The strength screen. Faz 17.
//

import Foundation
import Observation

@MainActor
@Observable
final class StrengthViewModel {

    struct Content: Sendable, Equatable {
        let oneRepMaxes: [OneRepMaxEstimate]
        let weeklyVolume: [WeeklyVolume]
        let balance: StrengthBalance
        let deload: DeloadSignal

        /// How many logged sessions fell in the volume window, so an empty chart can say
        /// whether the week was quiet or the log is.
        let sessionsThisWeek: Int
    }

    private(set) var state: ViewState<Content> = .loading

    private let sessions: any StrengthSessionRepository
    private let records: any BiometricDayRepository
    private let muscles: any MuscleSnapshotRepository
    private let nowProvider: @Sendable () -> Date

    init(
        sessions: any StrengthSessionRepository,
        records: any BiometricDayRepository,
        muscles: any MuscleSnapshotRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessions = sessions
        self.records = records
        self.muscles = muscles
        self.nowProvider = nowProvider
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        let now = nowProvider()
        let start = now.addingTimeInterval(-Double(StrengthEngine.progressionWindowDays) * 86_400)

        do {
            let logged = try await sessions.strengthSessions(from: start, through: now)
            guard !logged.isEmpty else {
                state = .noData(reason: .nothingLogged(what: "kuvvet seansı"))
                return
            }

            let volume = StrengthEngine.weeklyVolume(from: logged, now: now)

            // The deload signal needs recovery and muscle state, but a missing one of those
            // should weaken the signal rather than blank the screen — so both are optional
            // reads and a failure simply contributes no reason.
            let weekStart = now.addingTimeInterval(-7 * 86_400)
            let recoveryScores = (try? await records.dayRecords(from: weekStart, through: now))?
                .compactMap(\.recoveryScore) ?? []
            let snapshot = try? await muscles.latestMuscleSnapshot()
            let readiness = snapshot.map { record in
                MuscleGroup.allCases.map { record.readiness(for: $0) }
            } ?? []
            let loadRatio = (try? await records.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now))
                .map { days -> Double? in
                    let loads = days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) }
                    return TrainingLoadEngine.analyse(
                        TrainingLoadInput(days: loads, referenceDay: now)
                    ).ratio
                } ?? nil

            state = .loaded(
                Content(
                    oneRepMaxes: StrengthEngine.oneRepMaxes(from: logged, now: now),
                    weeklyVolume: volume,
                    balance: StrengthEngine.balance(from: logged, now: now),
                    deload: StrengthEngine.deloadSignal(
                        volume: volume,
                        recoveryScores: recoveryScores,
                        muscleReadiness: readiness,
                        loadRatio: loadRatio
                    ),
                    sessionsThisWeek: logged.filter { $0.performedAt >= weekStart }.count
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }
}
