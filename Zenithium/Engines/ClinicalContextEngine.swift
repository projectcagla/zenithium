//
//  ClinicalContextEngine.swift
//  Zenithium
//
//  The pure, deterministic clinical context engine. Spec §12.
//  Translates recent lab biomarkers and ECG recordings into epistemic confidence modifiers.
//

import Foundation

enum ClinicalContextEngine {

    /// Minimum total confidence multiplier floor (confidence is trimmed, never wiped out).
    static let multiplierFloor: Double = 0.70

    // MARK: - Assessment

    /// Deterministically assesses blood markers and ECG records against the registered clinical modifiers.
    ///
    /// - Parameters:
    ///   - markers: All stored blood marker snapshots.
    ///   - ecgRecords: All imported ECG records.
    ///   - disabledModifierIDs: Set of modifier IDs explicitly disabled by the user in Settings.
    ///   - sex: Biological sex for marker reference range resolution.
    ///   - now: Evaluation timestamp.
    ///   - calendar: Calendar for staleness and interval math.
    /// - Returns: A calculated `ClinicalContext`.
    static func assess(
        markers: [BloodMarkerSnapshot],
        ecgRecords: [ECGRecord],
        disabledModifierIDs: Set<String> = [],
        sex: BiologicalSexValue,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClinicalContext {
        var multiplier: Double = 1.0
        var penaltyReasons: [String] = []
        var limitations: [ScientificLimitation] = []
        var evidence: [EvidenceNode] = []
        var suppressesHRV = false

        // Group markers by key and take only the latest snapshot
        let groupedMarkers = Dictionary(grouping: markers, by: { $0.marker.storageKey })

        for modifier in ClinicalModifierRegistry.allModifiers {
            // Check if user disabled this modifier
            guard !disabledModifierIDs.contains(modifier.id) else { continue }

            if let key = modifier.targetMarkerKey, let entries = groupedMarkers[key] {
                guard let latest = entries.sorted(by: { $0.drawnAt < $1.drawnAt }).last else { continue }

                // Staleness check: marker must be within its validity horizon
                let months = calendar.dateComponents([.month], from: latest.drawnAt, to: now).month ?? 0
                guard months <= modifier.validityMonths else { continue }

                // Evaluate condition
                let triggered = isMarkerConditionTriggered(modifier: modifier, snapshot: latest, sex: sex)
                if triggered {
                    multiplier *= modifier.multiplier
                    penaltyReasons.append(modifier.rationale)
                    limitations.append(
                        ScientificLimitation(
                            code: modifier.limitationCode,
                            explanation: modifier.rationale,
                            isBlocking: modifier.isBlockingLimitation
                        )
                    )
                    evidence.append(
                        EvidenceNode(
                            sourceCategory: "Laboratuvar",
                            summary: "\(latest.marker.displayName): \(MathSupport.decimal(latest.value, digits: latest.marker.fractionDigits)) \(latest.unitSymbol) (\(modifier.title))",
                            weight: 1.0 - modifier.multiplier > 0 ? (1.0 - modifier.multiplier) : 0.15,
                            timestamp: latest.drawnAt
                        )
                    )
                }
            } else if let targetECG = modifier.targetECGClassification {
                // Find most recent ECG record
                guard let latestECG = ecgRecords.sorted(by: { $0.recordedAt < $1.recordedAt }).last else { continue }

                // Staleness check for ECG: only records within 30 days are relevant
                let days = calendar.dateComponents([.day], from: latestECG.recordedAt, to: now).day ?? 0
                guard days <= 30 else { continue }

                if latestECG.classification == targetECG {
                    multiplier *= modifier.multiplier
                    if modifier.suppressesHRVRecovery {
                        suppressesHRV = true
                    }
                    penaltyReasons.append(modifier.rationale)
                    limitations.append(
                        ScientificLimitation(
                            code: modifier.limitationCode,
                            explanation: modifier.rationale,
                            isBlocking: modifier.isBlockingLimitation
                        )
                    )
                    evidence.append(
                        EvidenceNode(
                            sourceCategory: "EKG",
                            summary: "\(latestECG.classification.displayName) (\(latestECG.sourceName))",
                            weight: 0.25,
                            timestamp: latestECG.recordedAt
                        )
                    )
                }
            }
        }

        let clampedMultiplier = MathSupport.clamp(multiplier, multiplierFloor, 1.0)

        if clampedMultiplier == 1.0 && penaltyReasons.isEmpty && limitations.isEmpty && !suppressesHRV {
            return .neutral
        }

        return ClinicalContext(
            confidenceMultiplier: clampedMultiplier,
            penaltyReasons: penaltyReasons,
            limitations: limitations,
            evidence: evidence,
            suppressesHRVRecovery: suppressesHRV
        )
    }

    // MARK: - Marker Condition Evaluation

    private static func isMarkerConditionTriggered(
        modifier: ClinicalModifier,
        snapshot: BloodMarkerSnapshot,
        sex: BiologicalSexValue
    ) -> Bool {
        let reference = snapshot.referenceRange.isBounded
            ? snapshot.referenceRange
            : snapshot.marker.referenceRange(for: sex)

        switch modifier.id {
        case ClinicalModifierRegistry.hemoglobinLow.id,
             ClinicalModifierRegistry.ferritinLow.id:
            if let min = reference.minimum {
                return snapshot.value < min
            }
            return false

        case ClinicalModifierRegistry.tshShift.id:
            if reference.isBounded {
                return !reference.contains(snapshot.value)
            }
            return false

        case ClinicalModifierRegistry.hsCRPElevated.id:
            if let max = reference.maximum {
                return snapshot.value > max
            }
            // Clinical default threshold for high hsCRP is > 3.0 mg/L
            return snapshot.value > 3.0

        case ClinicalModifierRegistry.creatineKinaseSevere.id:
            let upper = reference.maximum ?? 200.0
            return snapshot.value > (upper * 5.0)

        default:
            return false
        }
    }
}
