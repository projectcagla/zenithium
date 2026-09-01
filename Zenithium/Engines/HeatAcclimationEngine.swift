//
//  HeatAcclimationEngine.swift
//  Zenithium
//
//  Heat adaptation, from the sessions that were actually done in it. Yol haritası v4, C7.
//
//  ## What the literature supports
//
//  Repeated exercise in the heat produces a well-characterised set of adaptations — plasma
//  volume expands, core temperature at a given workload falls, sweating starts earlier and
//  more dilutely. The time course is the useful part and it is consistent across studies:
//  most of the effect appears within five to ten days of daily exposure, the plateau is
//  reached at roughly two weeks, and it decays over two to three weeks without exposure,
//  faster than it was gained.
//
//  So the model is a bounded accumulation with decay, and nothing more clever. Each session
//  above the threshold adds an increment scaled by how hot it was and how long it ran; each
//  day without one removes a little.
//
//  ## What it deliberately does not do
//
//  It does not adjust the prescription. §1 rules out an app that tells somebody to train less
//  because of the weather, and the honest reason is simpler: the pace-versus-heat literature
//  is about performance at a given effort, not about how much effort is safe, and the app has
//  no way to know whether a person is in a position to hydrate, seek shade, or stop. It
//  reports where the adaptation is. What to do about a hot afternoon is theirs.
//
//  ## Humidity
//
//  Folded into the effective temperature when it was recorded, because thirty degrees at
//  ninety per cent humidity is a different session from thirty at thirty — evaporative
//  cooling is what fails first. Absent, the dry temperature is used and the reading is simply
//  more conservative.
//

import Foundation

enum HeatAcclimationEngine {

    /// Below this a session does not count as heat exposure.
    ///
    /// Twenty-four degrees, which is where the physiological literature starts finding
    /// adaptation from repeated exposure rather than the ordinary thermoregulation of any
    /// session.
    static let thresholdCelsius: Double = 24

    /// The temperature at which a session contributes its full daily increment.
    static let fullEffectCelsius: Double = 33

    /// The session length that counts as a full dose, minutes. Shorter sessions contribute
    /// proportionally; longer ones do not contribute more, because the adaptation stimulus
    /// saturates rather than scaling with the whole afternoon.
    static let fullDoseMinutes: Double = 60

    /// How many consecutive full-dose days reach the plateau.
    static let daysToPlateau: Double = 14

    /// Days without exposure before decay begins.
    ///
    /// Defined by `HeatAcclimationState`, which the extension targets also compile.
    static var decayGraceDays: Int { HeatAcclimationState.decayGraceDays }

    /// How many days of no exposure remove the whole adaptation.
    static let daysToFullDecay: Double = 21

    /// Above this the state is described as established rather than as beginning.
    static var establishedThreshold: Double { HeatAcclimationState.establishedThreshold }

    /// How far back exposures are read.
    static let windowDays = 35

    // MARK: - State

    /// Where the person sits on the adaptation curve.
    static func state(
        exposures: [HeatExposure],
        now: Date,
        calendar: Calendar
    ) -> HeatAcclimationState {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let qualifying = exposures
            .filter { $0.date >= start && $0.date <= now && effectiveTemperature(for: $0) >= thresholdCelsius }
            .sorted { $0.date < $1.date }

        guard !qualifying.isEmpty else {
            return HeatAcclimationState(
                adaptation: 0,
                exposures: [],
                peakTemperature: nil,
                daysSinceLastExposure: nil
            )
        }

        // Walk the window a day at a time so gaps decay and exposures build, in order.
        var adaptation: Double = 0
        var index = qualifying.startIndex
        var day = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        var daysSinceExposure = 0

        while day <= today {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            var gainToday: Double = 0
            while index < qualifying.endIndex, qualifying[index].date < next {
                gainToday += increment(for: qualifying[index])
                index = qualifying.index(after: index)
            }

            if gainToday > 0 {
                // Bounded: each day can move at most one day's worth towards the plateau, and
                // the remaining distance shrinks as the plateau is approached.
                let step = min(gainToday, 1) / daysToPlateau
                adaptation += (1 - adaptation) * step * plateauApproachRate
                daysSinceExposure = 0
            } else {
                daysSinceExposure += 1
                if daysSinceExposure > decayGraceDays {
                    adaptation = max(0, adaptation - 1 / daysToFullDecay)
                }
            }
            day = next
        }

        return HeatAcclimationState(
            adaptation: MathSupport.clamp(adaptation, 0, 1),
            exposures: qualifying.reversed(),
            peakTemperature: qualifying.map(\.temperatureCelsius).max(),
            daysSinceLastExposure: daysSinceExposure
        )
    }

    /// How fast the bounded accumulation approaches the plateau.
    ///
    /// Chosen so that fourteen consecutive full-dose days land close to the plateau rather
    /// than asymptotically short of it — a bounded model with a naive step reaches about
    /// sixty per cent in that time, which contradicts the time course it is meant to encode.
    static let plateauApproachRate: Double = 2.6

    // MARK: - One session

    /// A session's contribution, 0…1 of a full day's dose.
    static func increment(for exposure: HeatExposure) -> Double {
        let temperature = effectiveTemperature(for: exposure)
        guard temperature >= thresholdCelsius else { return 0 }
        let span = fullEffectCelsius - thresholdCelsius
        let intensity = span > 0
            ? MathSupport.clamp((temperature - thresholdCelsius) / span, 0, 1)
            : 1
        let duration = MathSupport.clamp(exposure.minutes / fullDoseMinutes, 0, 1)
        return intensity * duration
    }

    /// Temperature adjusted for humidity, when it was recorded.
    ///
    /// A simple linear addition rather than a wet-bulb globe temperature: WBGT needs
    /// radiant heat and wind, neither of which a watch records, and computing it from two of
    /// four inputs would give a number with a name it has not earned. Up to four degrees at
    /// full saturation, which is the right order for the evaporative penalty.
    static func effectiveTemperature(for exposure: HeatExposure) -> Double {
        guard let humidity = exposure.humidity else { return exposure.temperatureCelsius }
        let excess = MathSupport.clamp((humidity - 0.4) / 0.6, 0, 1)
        return exposure.temperatureCelsius + excess * humidityPenaltyCelsius
    }

    /// The most humidity can add to the effective temperature, °C.
    static let humidityPenaltyCelsius: Double = 4

    // MARK: - Building exposures

    /// Turn workouts into exposures, dropping the ones with no weather recorded.
    static func exposures(from workouts: [WorkoutSummary]) -> [HeatExposure] {
        workouts.compactMap { workout in
            guard let temperature = workout.ambientTemperatureCelsius else { return nil }
            return HeatExposure(
                date: workout.interval.start,
                temperatureCelsius: temperature,
                humidity: workout.ambientHumidity,
                minutes: workout.interval.duration / 60
            )
        }
    }

    // MARK: - Copy

    /// One sentence. Where the adaptation is — never what to do about the weather (§1).
    static func summary(for state: HeatAcclimationState) -> String? {
        guard !state.exposures.isEmpty else { return nil }
        let percent = Int((state.adaptation * 100).rounded())

        if state.isDecaying, let days = state.daysSinceLastExposure {
            return "Sıcak ortam uyumun %\(percent) civarında ve geriliyor — son sıcak seansının üstünden \(days) gün geçti."
        }
        if state.isEstablished {
            return "Son \(windowDays) günde \(state.exposures.count) sıcak seans; uyumun %\(percent) civarında."
        }
        return "Sıcak ortam uyumun başlangıcında (%\(percent)) — \(state.exposures.count) seans birikti."
    }
}
