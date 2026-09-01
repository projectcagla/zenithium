//
//  JournalViewModel.swift
//  Zenithium
//
//  Günlük ekranı ve içgörüler. Spec §10.
//

import Foundation
import Observation

@MainActor
@Observable
final class JournalViewModel {

    struct Content: Sendable, Equatable {
        /// Bugünün kaydı — hiç kaydedilmemişse boş.
        var today: JournalDay

        /// Son 30 günde kaç gün kayıt tutulmuş. Korelasyonun ne zaman konuşabileceğini
        /// kullanıcıya göstermek için.
        let loggedDaysInWindow: Int
        let windowDays: Int

        /// Toplanan içgörüler, etkiye göre sıralı.
        let insights: [CorrelationResult]

        /// Kayıtlı takviye kürleri, en yenisi önce. Yol haritası v4, C5.
        var supplements: [SupplementCourse] = []

        /// Motor daha konuşamıyorsa, kaç gün daha gerektiği.
        var needsMoreDays: Int {
            max(0, CorrelationEngine.minimumSamplesPerGroup * 2 - loggedDaysInWindow)
        }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    /// Hangi ölçüme göre bakıldığı. Kullanıcı değiştirebilir.
    private(set) var outcome: CorrelationOutcome = .recovery

    private let journal: any JournalRepository
    private let records: any BiometricDayRepository

    /// Optional so previews and the briefing path can leave it out.
    private let supplements: (any SupplementRepository)?

    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    /// İçgörü penceresi. 90 gün, çünkü haftada iki kez kaydeden biri bile bu pencerede
    /// gruplara yeterli gece toplayabilir.
    private static let windowDays = 90

    init(
        journal: any JournalRepository,
        records: any BiometricDayRepository,
        supplements: (any SupplementRepository)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.journal = journal
        self.records = records
        self.supplements = supplements
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        await load()
    }

    func select(outcome newOutcome: CorrelationOutcome) {
        guard newOutcome != outcome else { return }
        outcome = newOutcome
        Task { await load() }
    }

    /// Bir davranışı bugünün kaydında açıp kapatır ve hemen kaydeder.
    ///
    /// Kaydet düğmesi yok: günlük tutmak zaten bir sürtünme, ikinci bir adım eklemek
    /// kullanıcıyı kaybetmenin en kolay yolu.
    func toggle(_ behavior: JournalBehavior) async {
        guard var content = state.value else { return }
        var behaviors = content.today.behaviors
        if behaviors.contains(behavior) {
            behaviors.remove(behavior)
        } else {
            behaviors.insert(behavior)
        }
        content.today = JournalDay(
            dayStart: content.today.dayStart,
            behaviors: behaviors,
            mood: content.today.mood,
            note: content.today.note
        )
        state = .loaded(content)
        await persist(content.today)
    }

    func setMood(_ mood: MoodRating?) async {
        guard var content = state.value else { return }
        content.today = JournalDay(
            dayStart: content.today.dayStart,
            behaviors: content.today.behaviors,
            mood: content.today.mood == mood ? nil : mood,
            note: content.today.note
        )
        state = .loaded(content)
        await persist(content.today)
    }

    func setNote(_ note: String) async {
        guard var content = state.value else { return }
        content.today = JournalDay(
            dayStart: content.today.dayStart,
            behaviors: content.today.behaviors,
            mood: content.today.mood,
            note: note
        )
        state = .loaded(content)
        await persist(content.today)
    }

    // MARK: - Yükleme

    func load() async {
        let calendar = calendarProvider()
        let now = nowProvider()
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -Self.windowDays, to: today) else {
            state = .failed(.invalidEngineInput(reason: "Tarih aralığı çözülemedi."))
            return
        }

        do {
            let todayLog = try await journal.journalDay(for: today) ?? .empty(dayStart: today)
            let logs = try await journal.journalDays(from: windowStart, through: today)
            let dayRecords = try await records.dayRecords(from: windowStart, through: today)
            // A missing supplement list is not an error — it only means this screen shows
            // behaviours and no courses.
            var courses: [SupplementCourse] = []
            if let supplements {
                courses = (try? await supplements.supplementCourses()) ?? []
            }

            state = .loaded(
                Content(
                    today: todayLog,
                    loggedDaysInWindow: logs.filter { !$0.isEmpty }.count,
                    windowDays: Self.windowDays,
                    insights: Self.buildInsights(
                        outcome: outcome,
                        logs: logs,
                        records: dayRecords,
                        calendar: calendar,
                        supplements: courses
                    ),
                    supplements: courses
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    // MARK: - Supplement courses (Yol haritası v4, C5)

    /// Start a course today.
    func startSupplement(named name: String, note: String = "") async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let supplements else { return }
        let today = calendarProvider().startOfDay(for: nowProvider())
        await write(to: supplements) {
            try await $0.saveSupplementCourse(
                SupplementCourse(name: trimmed, startedAt: today, note: note)
            )
        }
    }

    /// Close a course as of today, keeping its history.
    ///
    /// Ending rather than deleting: the whole point of the record is the comparison between
    /// the window it covered and the days either side, and deleting it would throw that away
    /// to tidy a list.
    func endSupplement(_ course: SupplementCourse) async {
        guard let supplements, course.isOngoing else { return }
        let today = calendarProvider().startOfDay(for: nowProvider())
        await write(to: supplements) {
            try await $0.saveSupplementCourse(
                SupplementCourse(
                    id: course.id,
                    name: course.name,
                    startedAt: course.startedAt,
                    endedAt: max(today, course.startedAt),
                    note: course.note
                )
            )
        }
    }

    func deleteSupplement(_ course: SupplementCourse) async {
        guard let supplements else { return }
        await write(to: supplements) { try await $0.deleteSupplementCourse(id: course.id) }
    }

    private func write(
        to repository: any SupplementRepository,
        _ work: (any SupplementRepository) async throws -> Void
    ) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await work(repository)
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    private func persist(_ day: JournalDay) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await journal.saveJournalDay(day)
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    // MARK: - İçgörü kurulumu

    /// Günlük kayıtlarını *ertesi sabahın* ölçümüyle eşleştirir.
    ///
    /// Eşleştirmenin yönü kritik: bir davranış o geceyi etkiler, o yüzden kaydın günü ile
    /// karşılaştırılacak ölçümün günü **aynı** gündür — Zenithium'un günlük kaydı zaten
    /// sabah hesaplanan ve o geceyi özetleyen kayıttır. Bir gün kaydırmak, dün akşamki
    /// alkolü bu geceyle değil öbür geceyle karşılaştırmak olurdu.
    nonisolated static func buildInsights(
        outcome: CorrelationOutcome,
        logs: [JournalDay],
        records: [BiometricDaySnapshot],
        calendar: Calendar,
        supplements: [SupplementCourse] = []
    ) -> [CorrelationResult] {

        let loggedDays = logs.filter { !$0.isEmpty }
        guard loggedDays.count >= CorrelationEngine.minimumSamplesPerGroup * 2 else { return [] }

        let behaviorsByDay = Dictionary(
            loggedDays.map { ($0.dayStart, $0.behaviors) },
            uniquingKeysWith: { first, _ in first }
        )

        // Yalnızca günlüğün tutulduğu günler gözlem sayılır. Hiç kayıt olmayan bir gün
        // "davranış yoktu" değil, "bilmiyoruz" demektir; onu kontrol grubuna koymak
        // sonuçları sessizce çarpıtırdı.
        var observationsByBehavior: [JournalBehavior: [CorrelationObservation]] = [:]

        for record in records {
            guard let behaviors = behaviorsByDay[record.dayStart] else { continue }
            guard let value = value(of: outcome, in: record) else { continue }
            for behavior in JournalBehavior.allCases {
                observationsByBehavior[behavior, default: []].append(
                    CorrelationObservation(
                        behaviorLogged: behaviors.contains(behavior),
                        value: value
                    )
                )
            }
        }

        var observationsBySubject: [CorrelationSubject: [CorrelationObservation]] = [:]
        for (behavior, observations) in observationsByBehavior {
            observationsBySubject[.behavior(behavior)] = observations
        }

        // Supplement courses join the same comparison. A course is a window rather than a
        // nightly tap, so its "logged" days are the days it covers — and unlike a behaviour,
        // every day with a reading counts, because a course that was running was running
        // whether or not the journal was opened. Yol haritası v4, C5.
        for course in supplements {
            var observations: [CorrelationObservation] = []
            for record in records {
                guard let value = value(of: outcome, in: record) else { continue }
                observations.append(
                    CorrelationObservation(
                        behaviorLogged: course.covers(record.dayStart),
                        value: value
                    )
                )
            }
            observationsBySubject[course.correlationSubject] = observations
        }

        return CorrelationEngine.rank(
            outcome: outcome,
            observationsBySubject: observationsBySubject
        )
    }

    private nonisolated static func value(
        of outcome: CorrelationOutcome,
        in record: BiometricDaySnapshot
    ) -> Double? {
        switch outcome {
        case .recovery: return record.recoveryScore
        case .sleepScore: return record.sleepScore
        case .sleepDuration:
            guard record.sleepDurationSeconds > 0 else { return nil }
            return TimeConversion.hours(fromSeconds: record.sleepDurationSeconds)
        case .restingHeartRate: return record.restingHeartRate
        case .heartRateVariability: return record.heartRateVariability
        }
    }
}
