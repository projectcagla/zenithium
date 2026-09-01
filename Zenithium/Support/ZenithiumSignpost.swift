//
//  ZenithiumSignpost.swift
//  Zenithium
//
//  Signposted intervals on the three paths worth watching. Yol haritası v4, A9.
//
//  Before this file the app had no instrumentation at all, which meant every performance
//  claim about it — including the ones in the roadmap this file comes from — rested on
//  reading the code rather than on measuring it. Signposts close that gap: an Instruments
//  trace now shows how long a recalculation, a lab parse or a map draw actually took, on the
//  device that matters rather than in a simulator.
//
//  `OSSignposter` compiles to almost nothing when nobody is listening, so these are safe to
//  leave in a release build; the intervals only cost anything while a trace is recording.
//
//  ## What this is not
//
//  It is not the regression guard. Wall-clock assertions flicker under CI load, so they get
//  written once and disabled a month later. The guard is `PerformanceRegressionTests`, which
//  asserts on *work done* — splines built, needles examined, reads issued. Each of those is
//  counted where it happens, by the type that does it, and each is deterministic.
//

import Foundation
import OSLog

/// The app's signposted intervals.
enum ZenithiumSignpost {

    /// The daily recalculation pipeline, end to end.
    static let orchestration = OSSignposter(
        subsystem: ZenithiumLog.subsystem,
        category: "orchestration"
    )

    /// Reading and parsing a laboratory document.
    static let labs = OSSignposter(subsystem: ZenithiumLog.subsystem, category: "labs")

    /// View work: body map path building, chart preparation.
    static let ui = OSSignposter(subsystem: ZenithiumLog.subsystem, category: "ui")

    /// Run `work` inside a signposted interval on `signposter`.
    ///
    /// The name has to be a literal string constant, which is why it is `StaticString` here
    /// rather than `String` — Instruments groups intervals by that name and a computed one
    /// would produce a category per call.
    static func interval<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        _ work: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    /// `interval(_:_:_:)` for asynchronous work.
    static func interval<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
