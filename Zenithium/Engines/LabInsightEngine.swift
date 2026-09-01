//
//  LabInsightEngine.swift
//  Zenithium
//
//  Turns stored blood markers into observations. Faz 23.
//
//  Spec §12 draws the line this engine lives on, and it is worth stating plainly because
//  the temptation to cross it is constant: **a value outside its reference band produces
//  exactly one output here, and that output is "take this to your doctor."** No cause, no
//  name for it, no supplement, no dose, no "this usually means". Zenithium is allowed to
//  say where a number sits, how it has moved, how old it is, and how it behaves around
//  training. It is not allowed to say what it means about the body.
//
//  What the engine *is* good for is the part a laboratory report cannot do: it knows what
//  the user was doing in the days before the blood was drawn, and it knows what the rest of
//  the panel looks like.
//

import Foundation

enum LabInsightEngine {

    /// Markers whose value is known to move for days after a hard session, which makes a
    /// draw taken too soon after one hard to read.
    static let trainingSensitiveKeys: Set<String> = [
        "creatineKinase", "ast", "highSensitivityCRP", "alt"
    ]

    /// How long after a session those markers stay disturbed.
    static let trainingSensitiveWindowHours = 72

    /// Panels where a lone value genuinely cannot be read without its partners.
    ///
    /// Ferritin without transferrin saturation is the classic case: ferritin is also an
    /// acute-phase reactant, so a single number carries two possible stories and the panel
    /// is what separates them. Saying so is a statement about the measurement, not about
    /// the person — which is what keeps it on the right side of §12.
    static let panelCompanions: [String: [String]] = [
        "ferritin": ["transferrinSaturation", "serumIron"],
        "totalCholesterol": ["ldlCholesterol", "hdlCholesterol", "triglycerides"],
        "tsh": ["freeT4"],
        "fastingGlucose": ["hba1c"],
        "creatinine": ["egfr"]
    ]

    // MARK: - Entry point

    /// Every observation worth making about a set of markers.
    ///
    /// - Parameters:
    ///   - markers: every stored value, any age, in any order.
    ///   - sex: decides which reference band applies.
    ///   - sessionDates: when the user trained, used only for the timing caveat.
    ///   - now: today.
    static func observations(
        markers: [BloodMarkerSnapshot],
        sex: BiologicalSexValue,
        sessionDates: [Date] = [],
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [LabObservation] {
        let grouped = Dictionary(grouping: markers, by: { $0.marker.storageKey })
        var result: [LabObservation] = []

        for (key, entries) in grouped {
            let ordered = entries.sorted { $0.drawnAt < $1.drawnAt }
            guard let latest = ordered.last else { continue }

            result.append(contentsOf: rangeObservations(for: latest, sex: sex))
            if let movement = movementObservation(latest: latest, previous: ordered.dropLast().last, calendar: calendar) {
                result.append(movement)
            }
            if let aging = agingObservation(for: latest, now: now, calendar: calendar) {
                result.append(aging)
            }
            if let caveat = timingObservation(for: latest, sessionDates: sessionDates) {
                result.append(caveat)
            }
            if let note = latest.marker.contextNote {
                result.append(
                    LabObservation(
                        id: "\(key).context",
                        marker: latest.marker,
                        kind: .context,
                        message: note,
                        requiresClinician: false,
                        priority: 10
                    )
                )
            }
        }

        result.append(contentsOf: panelObservations(present: Set(grouped.keys), markers: grouped))

        return result.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Ranges

    private static func rangeObservations(
        for snapshot: BloodMarkerSnapshot,
        sex: BiologicalSexValue
    ) -> [LabObservation] {
        let marker = snapshot.marker
        let key = marker.storageKey
        let reference = snapshot.referenceRange.isBounded
            ? snapshot.referenceRange
            : marker.referenceRange(for: sex)

        if reference.isBounded, !reference.contains(snapshot.value) {
            let isAbove = reference.maximum.map { snapshot.value > $0 } ?? false
            return [
                LabObservation(
                    id: "\(key).reference",
                    marker: marker,
                    kind: .outsideReference(isAbove: isAbove),
                    message: "\(marker.displayName) \(format(snapshot)) — laboratuvarın referans aralığının \(isAbove ? "üstünde" : "altında").",
                    requiresClinician: true,
                    priority: 100
                )
            ]
        }

        let optimal = snapshot.optimalRange.isBounded
            ? snapshot.optimalRange
            : marker.optimalRange(for: sex)
        if optimal.isBounded, !optimal.contains(snapshot.value) {
            let isAbove = optimal.maximum.map { snapshot.value > $0 } ?? false
            return [
                LabObservation(
                    id: "\(key).optimal",
                    marker: marker,
                    kind: .outsideOptimal(isAbove: isAbove),
                    message: "\(marker.displayName) \(format(snapshot)) — referans aralığının içinde, sporcu literatüründe sık anılan dar bandın \(isAbove ? "üstünde" : "altında").",
                    requiresClinician: false,
                    priority: 60
                )
            ]
        }

        return []
    }

    // MARK: - Movement

    /// How the marker has moved since the draw before it.
    ///
    /// Movement is reported as a number and a direction, never as better or worse. Whether
    /// a rise is welcome depends on the marker and on the person, and Zenithium knows
    /// neither well enough to say.
    private static func movementObservation(
        latest: BloodMarkerSnapshot,
        previous: BloodMarkerSnapshot?,
        calendar: Calendar
    ) -> LabObservation? {
        guard let previous, previous.unitSymbol == latest.unitSymbol else { return nil }
        let delta = latest.value - previous.value
        guard abs(delta) > 0 else { return nil }

        // A change smaller than the marker's own display precision is noise.
        let digits = latest.marker.fractionDigits
        let smallestMeaningful = pow(10.0, Double(-digits))
        guard abs(delta) >= smallestMeaningful else { return nil }

        let days = calendar.dateComponents([.day], from: previous.drawnAt, to: latest.drawnAt).day ?? 0
        guard days > 0 else { return nil }

        let direction = delta > 0 ? "yükselmiş" : "düşmüş"
        return LabObservation(
            id: "\(latest.marker.storageKey).movement",
            marker: latest.marker,
            kind: .movement(delta: delta, days: days),
            message: "\(latest.marker.displayName) önceki ölçüme göre \(ZenithiumFormat.signed(delta, digits: digits)) \(latest.unitSymbol) \(direction) — arada \(days) gün var.",
            requiresClinician: false,
            priority: 40
        )
    }

    // MARK: - Age

    private static func agingObservation(
        for snapshot: BloodMarkerSnapshot,
        now: Date,
        calendar: Calendar
    ) -> LabObservation? {
        let months = calendar.dateComponents([.month], from: snapshot.drawnAt, to: now).month ?? 0
        let limit = snapshot.marker.retestMonths
        guard months >= limit else { return nil }
        return LabObservation(
            id: "\(snapshot.marker.storageKey).aging",
            marker: snapshot.marker,
            kind: .aging(months: months),
            message: "\(snapshot.marker.displayName) değerin \(months) aylık.",
            requiresClinician: false,
            priority: 20
        )
    }

    // MARK: - Timing

    /// Whether the draw landed inside the window where training still moves the marker.
    private static func timingObservation(
        for snapshot: BloodMarkerSnapshot,
        sessionDates: [Date]
    ) -> LabObservation? {
        guard trainingSensitiveKeys.contains(snapshot.marker.storageKey) else { return nil }
        let window = Double(trainingSensitiveWindowHours) * 3600
        let priorSessions = sessionDates.filter { $0 <= snapshot.drawnAt && snapshot.drawnAt.timeIntervalSince($0) <= window }
        guard let nearest = priorSessions.max() else { return nil }

        let hours = Int((snapshot.drawnAt.timeIntervalSince(nearest) / 3600).rounded())
        return LabObservation(
            id: "\(snapshot.marker.storageKey).timing",
            marker: snapshot.marker,
            kind: .timingCaveat(hoursSinceSession: hours),
            message: "Bu ölçüm, bir antrenmandan \(hours) saat sonra alınmış. \(snapshot.marker.displayName) bu pencerede antrenmandan etkilenir; karşılaştırırken bunu hesaba kat.",
            requiresClinician: false,
            priority: 70
        )
    }

    // MARK: - Panels

    private static func panelObservations(
        present: Set<String>,
        markers: [String: [BloodMarkerSnapshot]]
    ) -> [LabObservation] {
        var result: [LabObservation] = []
        for (key, companions) in panelCompanions {
            guard present.contains(key) else { continue }
            let missing = companions.filter { !present.contains($0) }
            guard !missing.isEmpty else { continue }
            guard let anchor = markers[key]?.last?.marker else { continue }
            guard let panel = anchor.panel else { continue }

            let names = missing.compactMap { BiomarkerCatalog.definition(forKey: $0)?.displayName }
            guard !names.isEmpty else { continue }

            result.append(
                LabObservation(
                    id: "\(key).panel",
                    marker: anchor,
                    kind: .panelGap(panel: panel, missing: missing),
                    message: "\(anchor.displayName) kayıtlı ama \(names.joined(separator: ", ")) yok — bu değer tek başına eksik bir tablo çiziyor.",
                    requiresClinician: false,
                    priority: 30
                )
            )
        }
        return result
    }

    // MARK: - Formatting

    private static func format(_ snapshot: BloodMarkerSnapshot) -> String {
        let value = ZenithiumFormat.metric(snapshot.value, digits: snapshot.marker.fractionDigits)
        return snapshot.unitSymbol.isEmpty ? value : "\(value) \(snapshot.unitSymbol)"
    }
}
