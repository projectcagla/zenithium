import Foundation

/// Receipt only follows a durable store write. Re-delivery is idempotent by session UUID
/// and by timestamp for each explicitly changed journal field.
actor WatchLogCoordinator {
    private let sessions: any StrengthSessionRepository
    private let journal: any JournalRepository
    private let root: URL?
    init(sessions: any StrengthSessionRepository, journal: any JournalRepository, root: URL? = AppGroup.containerURL) {
        self.sessions = sessions
        self.journal = journal
        self.root = root
    }

    private var isPaused = false
    func resume() { isPaused = false }
    private var lastWrite: Task<Void, any Error>?

    func receive(_ message: WatchLogMessage, now: Date = Date()) async throws {
        guard !isPaused else { throw ZenithiumError.cancelled }
        let previous = lastWrite
        let task = Task {
            _ = try? await previous?.value
            try await self.apply(message, now: now)
        }
        lastWrite = task
        try await task.value
    }

    private func apply(_ message: WatchLogMessage, now: Date) async throws {
        guard !isPaused else { throw ZenithiumError.cancelled }
        guard message.isValid(now: now) else { throw ZenithiumError.invalidEngineInput(reason: "Saat kaydı geçerli değil.") }
        guard let root else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        switch message.payload {
        case .strength(let pattern, let entries):
            _ = try await sessions.saveStrengthSession(id: message.id, performedAt: message.createdAt,
                timeZoneIdentifier: message.timeZoneIdentifier, pattern: pattern, entries: entries,
                sessionLoad: StrainEngine.sessionLoad(forVolumeLoad: entries.totalVolumeLoad), note: "Apple Watch kaydı")
        case .journal(let behavior, let enabled):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: message.timeZoneIdentifier) ?? .current
            let day = calendar.startOfDay(for: message.createdAt)
            let url = root.appendingPathComponent("watch-journal-receipts.json")
            var receipts: [String: Date] = [:]
            if FileManager.default.fileExists(atPath: url.path) {
                receipts = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: url))
            }
            let key = "\(day.timeIntervalSince1970):\(behavior.rawValue)"
            if let newer = receipts[key], newer >= message.createdAt { return }
            let existing = try await journal.journalDay(for: day)
            var behaviors = existing?.behaviors ?? []
            if enabled { behaviors.insert(behavior) } else { behaviors.remove(behavior) }
            try await journal.saveJournalDay(JournalDay(dayStart: day, behaviors: behaviors,
                mood: existing?.mood, note: existing?.note ?? ""))
            receipts[key] = message.createdAt
            try JSONEncoder().encode(receipts).write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    func clear() async throws {
        isPaused = true
        _ = try? await lastWrite?.value
        lastWrite = nil
        guard let root else { return }
        let url = root.appendingPathComponent("watch-journal-receipts.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
