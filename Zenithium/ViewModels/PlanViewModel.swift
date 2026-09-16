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
        var targetSummary: String?
        var weeklyLoad: Double?
        var weeklyLoadNote: String?
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let preferences: (any PersonalPreferenceRepository)?
    private let health: (any HealthDataProviding)?
    private let goals: any GoalEventRepository
    private let records: any BiometricDayRepository
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        goals: any GoalEventRepository,
        records: any BiometricDayRepository,
        preferences: (any PersonalPreferenceRepository)? = nil,
        health: (any HealthDataProviding)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.goals = goals
        self.preferences = preferences
        self.health = health
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
            let choices = try await preferences?.load() ?? PersonalPreferences()
            let records = try await self.records.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now)
            let output = TrainingLoadEngine.analyse(TrainingLoadInput(days: records.compactMap(\.recordedTrainingLoad), referenceDay: now, calendar: calendar))
            let usualWeek = output.hasEnoughHistory ? output.chronicLoad * 7 : nil
            let weeklyLoad = position.flatMap { position in usualWeek.map { $0 * position.phase.volumeMultiplier } }
            let targetSummary = await targetSummary(for: position?.event, preferences: choices, now: now)
            var projection: FitnessFatigue?
            if let position, position.phase == .taper, output.hasEnoughHistory {
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
                    }, targetSummary: targetSummary,
                    weeklyLoad: choices.contexts.contains(where: { $0.isActive(at: now) }) ? nil : weeklyLoad,
                    weeklyLoadNote: "Haftalık yük, uzun dönem günlük TRIMP × 7 × faz katsayısıdır. Bir planlama senaryosudur; yarış hedefine ulaşmak için gereken veya güvenli olduğu kanıtlanmış bir yük değildir. Geçici bağlam etkinse ya da 28 ardışık kayıt günü yoksa hedef verilmez."
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    func save(kind: GoalEventKind, name: String, date: Date, planStart: Date?, raceTarget: RaceGoalTarget? = nil) async {
        guard raceTarget?.isValid ?? true else { saveError = .invalidEngineInput(reason: "Mesafe veya hedef süre geçerli değil."); return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            saveError = .invalidEngineInput(reason: "Etkinliğe bir ad ver.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let event = GoalEvent(kind: kind, name: trimmed, date: date)
            if let raceTarget {
                guard let preferences else { throw ZenithiumError.persistenceWriteFailed(detail: "Hedef tercihleri kaydedilemiyor.") }
                let old = try await preferences.load()
                var updated = old
                var targets = updated.raceGoals ?? [:]
                targets[event.id.uuidString] = raceTarget
                updated.raceGoals = targets
                try await preferences.save(updated)
                do { _ = try await goals.saveGoalEvent(event, planStart: planStart) }
                catch { try await preferences.save(old); throw error }
            } else { _ = try await goals.saveGoalEvent(event, planStart: planStart) }
            saveError = nil
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    private func targetSummary(for event: GoalEvent?, preferences: PersonalPreferences, now: Date) async -> String? {
        guard let event, let target = preferences.raceGoals?[event.id.uuidString] else { return nil }
        let label = "Hedef: \(ZenithiumFormat.metric(target.distanceMetres / 1000, digits: 1)) km · \(ZenithiumFormat.longClock(seconds: target.finishSeconds)). "
        guard let health,
              let workouts = try? await health.fetchWorkouts(in: DateInterval(start: now.addingTimeInterval(-Double(EnduranceEngine.effortWindowDays) * 86_400), end: now)),
              let model = EnduranceEngine.fit(efforts: EnduranceViewModel.efforts(from: workouts.filter { $0.activity == .running }), now: now),
              model.isWellConditioned, let seconds = model.predictedTime(forDistance: target.distanceMetres) else {
            return label + "Hedefi değerlendirecek yeterli ve tutarlı koşu eforu yok. Ulaşılabilirlik tahmin edilmedi."
        }
        let factor = model.extrapolationFactor(forDistance: target.distanceMetres)
        guard factor <= 1.5 else {
            return label + "Mesafe, modelin ölçtüğü süre aralığının dışında. Kritik hızdan yarış başarısı sonucu çıkarılamaz."
        }
        return label + "Modelin nokta tahmini: \(ZenithiumFormat.longClock(seconds: seconds)) · \(model.effortCount) efor. "
            + (target.finishSeconds < seconds ? "Hedef mevcut model tahmininden daha hızlı. " : "Hedef mevcut model tahmininden daha yavaş veya eşit. ")
            + "Bu karşılaştırma başarının olasılığı veya garantisi değildir; hava, parkur ve antrenman yanıtını içermez."
    }

    func delete(id: UUID) async {
        do {
            try await goals.deleteGoalEvent(id: id)
            if let preferences {
                var saved = try await preferences.load()
                saved.raceGoals?.removeValue(forKey: id.uuidString)
                try await preferences.save(saved)
            }
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: error.localizedDescription)
        }
    }
}
