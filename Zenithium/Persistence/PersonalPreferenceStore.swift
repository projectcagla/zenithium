import Foundation

actor PersonalPreferenceStore: PersonalPreferenceRepository {
    private let url: URL?
    private let isInMemory: Bool
    private var memory = PersonalPreferences()

    init(url: URL? = AppGroup.containerURL?.appending(path: "personal-preferences.json"), inMemory: Bool = false) {
        self.url = url
        self.isInMemory = inMemory
    }

    func load() throws -> PersonalPreferences {
        if isInMemory { return memory }
        guard let url else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            var initial = PersonalPreferences()
            initial.disabledClinicalModifierIDs = ClinicalPreferences.disabledModifierIDs()
            return initial
        }
        return try JSONDecoder().decode(PersonalPreferences.self, from: Data(contentsOf: url)).validated()
    }

    func save(_ preferences: PersonalPreferences) throws {
        let value = try preferences.validated()
        if isInMemory { memory = value; return }
        guard let url else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtection])
        // Compatibility with existing decision readers; the portable file is authoritative.
        ClinicalPreferences.setDisabledModifierIDs(value.disabledClinicalModifierIDs)
    }

    func reset() throws {
        memory = PersonalPreferences()
        if isInMemory { return }
        guard let url else { throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        ClinicalPreferences.setDisabledModifierIDs([])
    }
}

/// Compatibility storage belongs to Persistence, never to the domain catalogue.
enum ClinicalPreferences {
    private static let key = "zenithium.clinical.disabledModifiers"
    private static var defaults: UserDefaults { AppGroup.defaults ?? .standard }
    static func disabledModifierIDs() -> Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }
    static func setDisabledModifierIDs(_ ids: Set<String>) { defaults.set(ids.sorted(), forKey: key) }
    static func setModifier(id: String, isEnabled: Bool) {
        var ids = disabledModifierIDs()
        if isEnabled { ids.remove(id) } else { ids.insert(id) }
        setDisabledModifierIDs(ids)
    }
}
