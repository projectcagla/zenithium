//
//  Units.swift
//  Zenithium
//
//  Canonical units and the only conversion helpers in the app. Spec §2.8: all internal
//  maths is in canonical units; conversion happens at the HealthKit boundary only, never
//  in the UI.
//

import Foundation

/// Canonical units for every quantity Zenithium stores or computes.
///
/// | Quantity | Canonical unit |
/// |---|---|
/// | Heart rate variability (SDNN) | milliseconds |
/// | Heart rate | beats per minute |
/// | Wrist temperature | degrees Celsius |
/// | Respiratory rate | breaths per minute |
/// | Duration | seconds |
/// | Energy | kilocalories |
/// | Distance | metres |
/// | Blood oxygen | fraction, 0…1 |
enum CanonicalUnit {

    static let heartRateVariabilitySymbol = "ms"
    static let heartRateSymbol = "bpm"
    static let temperatureSymbol = "°C"
    static let respiratoryRateSymbol = "br/min"
    static let durationSymbol = "s"
    static let energySymbol = "kcal"
    static let distanceSymbol = "m"
    static let fractionSymbol = "%"
}

/// Time conversions. Every duration in the domain is a `TimeInterval` in seconds.
enum TimeConversion {

    static let secondsPerMinute: Double = 60
    static let minutesPerHour: Double = 60
    static let secondsPerHour: Double = 3600
    static let hoursPerDay: Double = 24
    static let secondsPerDay: Double = 86_400

    static func hours(fromSeconds seconds: Double) -> Double {
        seconds / secondsPerHour
    }

    static func seconds(fromHours hours: Double) -> Double {
        hours * secondsPerHour
    }

    static func minutes(fromSeconds seconds: Double) -> Double {
        seconds / secondsPerMinute
    }

    static func seconds(fromMinutes minutes: Double) -> Double {
        minutes * secondsPerMinute
    }
}

/// Temperature conversions, used only for display when the user prefers imperial units.
enum TemperatureConversion {

    /// Converts an absolute Celsius reading to Fahrenheit.
    static func fahrenheit(fromCelsius celsius: Double) -> Double {
        celsius * 9 / 5 + 32
    }

    /// Converts a Celsius *difference* to a Fahrenheit difference.
    ///
    /// A delta must not carry the +32 offset. Wrist temperature deviation (`ΔT`, §3) is a
    /// delta, so this is the conversion the temperature tile uses — never `fahrenheit(fromCelsius:)`.
    static func fahrenheitDelta(fromCelsiusDelta celsius: Double) -> Double {
        celsius * 9 / 5
    }
}

/// Distance conversions, used only for display.
enum DistanceConversion {

    static let metresPerKilometre: Double = 1000
    static let metresPerMile: Double = 1609.344

    static func kilometres(fromMetres metres: Double) -> Double {
        metres / metresPerKilometre
    }

    static func miles(fromMetres metres: Double) -> Double {
        metres / metresPerMile
    }
}

/// The user's display unit preference. Affects presentation only — never storage or maths.
enum UnitPreference: String, Sendable, Codable, CaseIterable, Hashable {
    case metric
    case imperial

    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    /// The symbol a wrist-temperature *delta* is shown in.
    var temperatureDeltaSymbol: String {
        switch self {
        case .metric: return "°C"
        case .imperial: return "°F"
        }
    }

    var distanceSymbol: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    /// Converts a canonical Celsius delta into this preference's unit.
    func temperatureDelta(fromCelsius celsius: Double) -> Double {
        switch self {
        case .metric: return celsius
        case .imperial: return TemperatureConversion.fahrenheitDelta(fromCelsiusDelta: celsius)
        }
    }

    /// Converts canonical metres into this preference's unit.
    func distance(fromMetres metres: Double) -> Double {
        switch self {
        case .metric: return DistanceConversion.kilometres(fromMetres: metres)
        case .imperial: return DistanceConversion.miles(fromMetres: metres)
        }
    }
}
