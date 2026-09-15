import Foundation

enum DecisionPreference: String, CaseIterable, Codable, Sendable {
    case cautious, progressive
    var title: String { self == .cautious ? "İhtiyatlı" : "Gelişim odaklı" }
    /// Planning policies, not thresholds validated as injury predictors.
    var pushThreshold: Double { self == .cautious ? 80 : 67 }
}

enum SleepTimingPreference: String, CaseIterable, Codable, Sendable {
    case early, intermediate, late, custom
    var title: String {
        switch self {
        case .early: return "Erken saatler"
        case .intermediate: return "Orta saatler"
        case .late: return "Geç saatler"
        case .custom: return "Kendi saatim"
        }
    }
    var suggestedWakeMinute: Int? {
        switch self {
        case .early: return 360
        case .intermediate: return 420
        case .late: return 540
        case .custom: return nil
        }
    }
}

enum PersonalContextKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case illness, travel, altitude, shiftWork
    var id: String { rawValue }
    var title: String {
        switch self {
        case .illness: return "Kendimi hasta hissediyorum"
        case .travel: return "Seyahat dönemi"
        case .altitude: return "Alışık olmadığım rakım"
        case .shiftWork: return "Vardiya değişikliği"
        }
    }
}

struct PersonalContextEntry: Sendable, Codable, Equatable, Identifiable {
    var kind: PersonalContextKind
    var through: Date
    var note: String
    var id: String { kind.rawValue }
    func isActive(at date: Date) -> Bool { through >= date }
}

/// Explicit user choices. Kept separate from observed physiology and scoring baselines.
struct PersonalPreferences: Sendable, Codable, Equatable {
    var decision: DecisionPreference = .cautious
    var sleepTiming: SleepTimingPreference = .intermediate
    var wakeMinute: Int = 420
    var morningReminder = false
    var missingNightReminder = false
    var weeklyReminder = false
    var baselineStart: Date?
    var contexts: [PersonalContextEntry] = []
    var disabledClinicalModifierIDs: Set<String> = []

    func bedtimeMinute(needHours: Double) -> Int? {
        guard needHours.isFinite, (0...24).contains(needHours), (0..<1440).contains(wakeMinute) else { return nil }
        return (wakeMinute - Int((needHours * 60).rounded()) + 1440) % 1440
    }

    func validated() throws -> PersonalPreferences {
        guard (0..<1440).contains(wakeMinute), contexts.count <= PersonalContextKind.allCases.count,
              baselineStart.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              Set(contexts.map(\.kind)).count == contexts.count,
              contexts.allSatisfy({ $0.note.count <= 500 && $0.through.timeIntervalSince1970.isFinite }) else {
            throw ZenithiumError.invalidEngineInput(reason: "Tercih saatini ve bağlam kayıtlarını kontrol et.")
        }
        return self
    }
}

protocol PersonalPreferenceRepository: Sendable {
    func load() async throws -> PersonalPreferences
    func save(_ preferences: PersonalPreferences) async throws
    func reset() async throws
}
