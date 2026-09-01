//
//  PlanViewModel.swift
//  Zenithium
//
//  The plan screen. Faz 20.
//

import Foundation
import Observation

@MainActor
@Observable
final class PlanViewModel {

    struct Content: Sendable, Equatable {
        let events: [GoalEvent]

        /// Where today sits relative to the next event.
        let position: PlanPosition?

        /// What the recommended taper does to form, when the plan is in one.
        let taperProjection: FitnessFatigue?

        let taperSummary: String?
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let goals: any GoalEventRepository
    private let records: any BiometricDayRepository
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        goals: any GoalEventRepository,
        records: any BiometricDayRepository,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.goals = goals
        self.records = records
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        let now = nowProvider()
        let calendar = calendarProvider()

        do {
            let events = try await goals.goalEvents()
            let today = calendar.startOfDay(for: now)
            let lookup = try await goals.nextGoalEvent(onOrAfter: today)

            let position = lookup.map {
                PlanEngine.position(on: today, event: $0.event, planStart: $0.planStart, calendar: calendar)
            }

            // The taper projection needs a load history. Without one the phase still shows;
            // only the "form on the day" figure is missing, which is the right thing to lose.
            var projection: FitnessFatigue?
            if let position, position.phase == .taper,
               let days = try? await records.dayRecords(
                   from: now.addingTimeInterval(-120 * 86_400),
                   through: now
               ) {
                let loads = days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) }
                let output = TrainingLoadEngine.analyse(
                    TrainingLoadInput(days: loads, referenceDay: now, calendar: calendar)
                )
                projection = PlanEngine.taperProjection(
                    currentFitness: output.fitnessFatigue.fitness,
                    currentFatigue: output.fitnessFatigue.fatigue,
                    usualDailyLoad: output.weekLoad / 7,
                    days: max(0, position.daysRemaining)
                )
            }

            state = .loaded(
                Content(
                    events: events,
                    position: position,
                    taperProjection: projection,
                    taperSummary: position.flatMap {
                        PlanEngine.taperSummary(for: $0, projection: projection)
                    }
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    func save(kind: GoalEventKind, name: String, date: Date, planStart: Date?) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            saveError = .invalidEngineInput(reason: "Etkinliğe bir ad ver.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await goals.saveGoalEvent(
                GoalEvent(kind: kind, name: trimmed, date: date),
                planStart: planStart
            )
            saveError = nil
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    func delete(id: UUID) async {
        do {
            try await goals.deleteGoalEvent(id: id)
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }
}
