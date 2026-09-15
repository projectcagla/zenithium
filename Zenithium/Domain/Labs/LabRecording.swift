import Foundation

/// Validated, comparable storage values. A missing printed range stays missing.
struct LabRecording: Sendable {
    let value: Double
    let unit: String
    let reference: MarkerRange

    static func prepare(marker: BloodMarkerKind, value: Double, unit: String, reference: MarkerRange) throws -> LabRecording {
        guard value.isFinite, value >= 0, !unit.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ZenithiumError.invalidEngineInput(reason: "Değeri ve raporda yazan birimi kontrol et.")
        }
        let bounds = [reference.minimum, reference.maximum].compactMap { $0 }
        guard bounds.allSatisfy({ $0.isFinite && $0 >= 0 }),
              reference.minimum == nil || reference.maximum == nil || (reference.minimum ?? 0) <= (reference.maximum ?? 0) else {
            throw ZenithiumError.invalidEngineInput(reason: "Referans aralığının alt ve üst sınırını kontrol et.")
        }
        guard let definition = marker.definition else {
            return LabRecording(value: value, unit: unit, reference: reference)
        }
        guard let conversion = definition.unit(matching: unit) else {
            throw ZenithiumError.invalidEngineInput(reason: "Bu belirteç için birim tanınmadı. Raporundaki birimi kontrol et veya özel belirteç olarak gir.")
        }
        let factor = conversion.factorToCanonical
        guard factor.isFinite, factor > 0, (value * factor).isFinite,
              bounds.allSatisfy({ ($0 * factor).isFinite }) else {
            throw ZenithiumError.invalidEngineInput(reason: "Birim dönüşümü yapılamadı.")
        }
        return LabRecording(value: value * factor, unit: definition.canonicalUnit.symbol,
                            reference: MarkerRange(minimum: reference.minimum.map { $0 * factor }, maximum: reference.maximum.map { $0 * factor }))
    }
}

struct LabApprovedRow: Sendable {
    let id: UUID
    let marker: BloodMarkerKind
    let value: Double
    let unit: String
    let reference: MarkerRange
    let note: String
}

struct LabSaveOutcome: Sendable {
    let savedIDs: Set<UUID>
    let failure: String?
}
