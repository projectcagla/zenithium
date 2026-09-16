import Foundation

struct WatchLogMessage: Codable, Sendable, Equatable, Identifiable {
    enum Payload: Codable, Sendable, Equatable {
        case strength(pattern: MovementPattern, entries: [StrengthEntry])
        case journal(behavior: JournalBehavior, enabled: Bool)
    }
    let id: UUID
    let createdAt: Date
    let timeZoneIdentifier: String
    let payload: Payload

    func isValid(now: Date) -> Bool {
        guard createdAt.timeIntervalSince1970.isFinite, createdAt <= now.addingTimeInterval(300),
              TimeZone(identifier: timeZoneIdentifier) != nil else { return false }
        switch payload {
        case .strength(_, let entries):
            return !entries.isEmpty && entries.count <= 100 && entries.allSatisfy {
                $0.isValid && $0.exerciseName.count <= 120 && ($0.weightKilograms.map { $0.isFinite && (0...1000).contains($0) } ?? true)
            }
        case .journal: return true
        }
    }
}
