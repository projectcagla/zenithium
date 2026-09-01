//
//  HeatAcclimation.swift
//  Zenithium
//
//  How far into heat adaptation a person is. Yol haritası v4, C7.
//

import Foundation

/// One session's heat exposure.
struct HeatExposure: Sendable, Equatable, Hashable, Identifiable {

    let date: Date

    /// Ambient temperature, °C.
    let temperatureCelsius: Double

    /// Relative humidity, 0…1, when it was recorded.
    let humidity: Double?

    /// How long the session ran, minutes.
    let minutes: Double

    var id: Date { date }
}

/// Where somebody sits on the adaptation curve.
struct HeatAcclimationState: Sendable, Equatable {

    /// Above this the state is described as established rather than as beginning.
    ///
    /// Defined here rather than on the engine because `Domain` is compiled by the watch and
    /// the widget while `Engines` is not, and a type in `Domain` that reaches into `Engines`
    /// breaks both extension targets.
    static let establishedThreshold: Double = 0.5

    /// Days without exposure before the state is described as decaying.
    static let decayGraceDays = 4

    /// 0…1. Zero is unadapted; one is the plateau the literature describes after roughly two
    /// weeks of consistent exposure.
    let adaptation: Double

    /// Sessions that contributed, newest first.
    let exposures: [HeatExposure]

    /// The warmest session in the window, °C.
    let peakTemperature: Double?

    /// Days since the most recent qualifying exposure, or `nil` if there were none.
    let daysSinceLastExposure: Int?

    /// Whether there is enough to say anything at all.
    var isEstablished: Bool { adaptation >= Self.establishedThreshold }

    /// Whether adaptation is being lost for want of exposure.
    var isDecaying: Bool {
        guard let daysSinceLastExposure else { return false }
        return adaptation > 0 && daysSinceLastExposure >= Self.decayGraceDays
    }
}
