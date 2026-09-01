//
//  BloodMarkerKind.swift
//  Zenithium
//
//  The identity of a tracked blood marker. Spec §7 (extensible marker set), §12 (reference
//  ranges and trends only — no diagnostic interpretation anywhere downstream of this file).
//
//  Faz 23 turned this from a five-case enum carrying its own data into a two-case identity
//  that reads everything from `BiomarkerCatalog`. The persisted `storageKey` format did not
//  change, so records written by earlier builds still resolve.
//

import Foundation

/// A tracked blood marker: either one Zenithium knows, or one the user named themselves.
///
/// `.custom` keeps the set open without a schema change; custom markers carry no reference
/// range unless the user enters one from their own report.
enum BloodMarkerKind: Sendable, Equatable, Hashable, Codable {

    /// A marker in `BiomarkerCatalog`, held by its stable key.
    case standard(String)

    /// A marker the user named.
    case custom(String)

    // MARK: - Named markers
    //
    // The five that shipped before the catalogue existed, kept as spellings so older call
    // sites and `case .apoB` patterns still read the same. Everything else is reached
    // through `BiomarkerCatalog`.

    static let apoB = BloodMarkerKind.standard("apoB")
    static let highSensitivityCRP = BloodMarkerKind.standard("highSensitivityCRP")
    static let vitaminD = BloodMarkerKind.standard("vitaminD")
    static let ferritin = BloodMarkerKind.standard("ferritin")
    static let fastingGlucose = BloodMarkerKind.standard("fastingGlucose")

    /// Every catalogued marker, in panel order. `.custom` is offered separately.
    static let standardCases: [BloodMarkerKind] = BiomarkerCatalog.all.map { .standard($0.key) }

    /// The catalogue entry behind this marker, or `nil` for a custom one.
    var definition: BiomarkerDefinition? {
        switch self {
        case .standard(let key): return BiomarkerCatalog.definition(forKey: key)
        case .custom: return nil
        }
    }

    /// The stable string persisted on `BloodMarker`. Custom markers are prefixed so a future
    /// catalogue key can never collide with a user-entered name.
    var storageKey: String {
        switch self {
        case .standard(let key): return key
        case .custom(let name): return "custom:\(name)"
        }
    }

    /// The inverse of `storageKey`.
    ///
    /// An unknown non-custom key is resolved as a custom marker under its own name rather
    /// than dropped, so a record written by a newer build never disappears from an older one.
    static func kind(forStorageKey key: String) -> BloodMarkerKind? {
        let prefix = "custom:"
        if key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            return name.isEmpty ? nil : .custom(name)
        }
        guard !key.isEmpty else { return nil }
        if BiomarkerCatalog.definition(forKey: key) != nil {
            return .standard(key)
        }
        return .custom(key)
    }

    var displayName: String {
        switch self {
        case .standard(let key): return BiomarkerCatalog.definition(forKey: key)?.displayName ?? key
        case .custom(let name): return name
        }
    }

    var accessibilityName: String {
        switch self {
        case .standard(let key): return BiomarkerCatalog.definition(forKey: key)?.accessibilityName ?? key
        case .custom(let name): return name
        }
    }

    /// Which panel this marker is grouped under. Custom markers group last.
    var panel: BiomarkerPanel? {
        definition?.panel
    }

    /// The unit the marker is entered in by default. The user can override per entry.
    var defaultUnitSymbol: String {
        definition?.canonicalUnit.symbol ?? ""
    }

    /// Every unit the marker is accepted in, canonical first.
    var acceptedUnits: [BiomarkerUnit] {
        definition?.units ?? []
    }

    /// The common laboratory reference range for a given user (§12 — shown for orientation
    /// only; nothing in Zenithium interprets, flags, or advises on a value).
    func referenceRange(for sex: BiologicalSexValue) -> MarkerRange {
        definition?.referenceRange.range(for: sex) ?? .unbounded
    }

    /// A narrower band commonly cited in sports and longevity literature, drawn as a second
    /// band on the same axis. Context, never a target and never a recommendation.
    func optimalRange(for sex: BiologicalSexValue) -> MarkerRange {
        definition?.optimalRange.range(for: sex) ?? .unbounded
    }

    /// The sex-agnostic reference range, for call sites that have no user characteristics to
    /// hand. Resolves to the wider band when the marker is sex-specific.
    var referenceRange: MarkerRange {
        referenceRange(for: .notSet)
    }

    /// The sex-agnostic optimal band. Same caveat as `referenceRange`.
    var optimalRange: MarkerRange {
        optimalRange(for: .notSet)
    }

    /// Whether the two sexes are given different reference bands — the flag the detail view
    /// uses to say which band is being drawn.
    var hasSexSpecificRanges: Bool {
        definition?.referenceRange.isSexSpecific ?? false
    }

    /// How many fraction digits the value is rendered with.
    var fractionDigits: Int {
        definition?.fractionDigits ?? 2
    }

    /// Whether the marker ships with ranges, which decides whether the axis draws bands.
    var hasBuiltInRanges: Bool {
        definition?.referenceRange.exists ?? false
    }

    /// How the marker behaves in a training context, when there is something true to say.
    /// Descriptive only — never advice (§12).
    var contextNote: String? {
        definition?.contextNote
    }

    /// How many months before a value is old enough to be worth mentioning.
    var retestMonths: Int {
        definition?.retestMonths ?? 12
    }
}
