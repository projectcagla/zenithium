import Foundation
import SwiftData
import Testing
@testable import Zenithium

@Suite("Watch delivery and exercise history")
struct WatchAndStrengthProgressTests {
    private let now = Date(timeIntervalSince1970: 1_780_300_800)

    @Test("Acknowledged set delivery is idempotent and feeds dated volume and 1RM history")
    func repeatedSetDelivery() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = WatchLogCoordinator(sessions: store, journal: store, root: root)
        let weighted = StrengthEntry(id: UUID(), exerciseName: "Squat", sets: 1, reps: 8, rpe: 7, weightKilograms: 40)
        let message = WatchLogMessage(id: UUID(), createdAt: now, timeZoneIdentifier: "UTC", payload: .strength(pattern: .squat, entries: [weighted]))
        try await coordinator.receive(message, now: now)
        try await coordinator.receive(message, now: now)
        let sessions = try await store.strengthSessions(from: now.addingTimeInterval(-1), through: now)
        #expect(sessions.count == 1)
        let history = StrengthEngine.exerciseProgress(from: sessions, now: now, calendar: TestCalendars.utc)
        #expect(history.count == 1)
        #expect(history.first?.points.first?.volumeKilograms == 320)
        #expect(history.first?.points.first?.estimatedMaximum != nil)
        let unweighted = StrengthEntry(id: UUID(), exerciseName: "Squat", sets: 1, reps: 8, rpe: 7)
        try await coordinator.receive(WatchLogMessage(id: UUID(), createdAt: now, timeZoneIdentifier: "UTC", payload: .strength(pattern: .squat, entries: [unweighted])), now: now)
        let all = try await store.strengthSessions(from: now.addingTimeInterval(-1), through: now)
        let incomplete = StrengthEngine.exerciseProgress(from: all, now: now, calendar: TestCalendars.utc)
        #expect(incomplete.first?.points.first?.volumeKilograms == nil)
        #expect(incomplete.first?.points.first?.sets == 2)
    }

    @Test("Late journal retransmission cannot restore an explicitly cleared habit")
    func journalOrderAndRestart() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let behavior = JournalBehaviorWidgetSet.featured[0]
        let earlier = WatchLogMessage(id: UUID(), createdAt: now.addingTimeInterval(-10), timeZoneIdentifier: "UTC", payload: .journal(behavior: behavior, enabled: true))
        let later = WatchLogMessage(id: UUID(), createdAt: now, timeZoneIdentifier: "UTC", payload: .journal(behavior: behavior, enabled: false))
        let coordinator = WatchLogCoordinator(sessions: store, journal: store, root: root)
        try await coordinator.receive(earlier, now: now)
        try await coordinator.receive(later, now: now)
        try await WatchLogCoordinator(sessions: store, journal: store, root: root).receive(earlier, now: now)
        let day = try await store.journalDay(for: TestCalendars.utc.startOfDay(for: now))
        #expect(day?.behaviors.contains(behavior) != true)
    }

    @Test("Erasure pauses Watch writes until the lifecycle explicitly resumes")
    func erasurePausesDelivery() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = WatchLogCoordinator(sessions: store, journal: store, root: root)
        let message = WatchLogMessage(id: UUID(), createdAt: now, timeZoneIdentifier: "UTC",
            payload: .journal(behavior: JournalBehaviorWidgetSet.featured[0], enabled: true))
        try await coordinator.clear()
        await #expect(throws: ZenithiumError.self) { try await coordinator.receive(message, now: now) }
        #expect(try await store.journalDay(for: TestCalendars.utc.startOfDay(for: now)) == nil)
        await coordinator.resume()
        try await coordinator.receive(message, now: now)
        #expect(try await store.journalDay(for: TestCalendars.utc.startOfDay(for: now)) != nil)
    }

    @Test("Race details survive preference persistence and reject impossible fields")
    func raceTargetPersistence() async throws {
        let preferences = PersonalPreferenceStore(inMemory: true)
        let id = UUID().uuidString
        var value = PersonalPreferences()
        value.raceGoals = [id: RaceGoalTarget(distanceMetres: 10_000, finishSeconds: 2700)]
        try await preferences.save(value)
        let encoded = try JSONEncoder().encode(try await preferences.load())
        #expect(try JSONDecoder().decode(PersonalPreferences.self, from: encoded).raceGoals == value.raceGoals)
        value.raceGoals = [id: RaceGoalTarget(distanceMetres: .nan, finishSeconds: 2700)]
        await #expect(throws: ZenithiumError.self) { try await preferences.save(value) }
    }
}
