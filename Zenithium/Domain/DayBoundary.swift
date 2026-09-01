//
//  DayBoundary.swift
//  Zenithium
//
//  Where one physiological day ends and the next begins. Spec §5.3, ASSUMPTION DAY-1
//  (default is wake-anchored, with a local 04:00 fallback when no sleep record exists).
//

import Foundation

/// The rule that decides which day a sample belongs to.
enum DayBoundary: String, Sendable, Codable, CaseIterable, Hashable {

    /// The day starts at the user's wake time, falling back to `fallbackHour` local when no
    /// sleep record is available. ASSUMPTION DAY-1 — this is the default.
    case wakeAnchored

    /// The day starts at local midnight.
    case midnight

    /// ASSUMPTION DAY-1 — reverse the assumption by changing this to `.midnight`.
    static let `default`: DayBoundary = .wakeAnchored

    /// ASSUMPTION DAY-1 — the hour used when wake-anchored but no sleep record exists.
    static let fallbackHour: Int = 4

    var displayName: String {
        switch self {
        case .wakeAnchored: return "Wake time"
        case .midnight: return "Midnight"
        }
    }

    var explanation: String {
        switch self {
        case .wakeAnchored:
            return "Strain resets when you wake up, so a late night belongs to the day before."
        case .midnight:
            return "Strain resets at midnight, matching the calendar day."
        }
    }
}

/// A concrete day window with the time zone that was in effect when it was resolved.
///
/// Spec §5.6: timezone travel uses the zone in effect at the record's date, stored on the
/// record; DST transitions are computed in absolute time and rendered in local wall-clock.
struct DayWindow: Sendable, Equatable, Hashable {

    /// The instant the physiological day starts.
    let start: Date

    /// The instant the physiological day ends. Always strictly after `start`.
    let end: Date

    /// The identifier of the time zone in effect at `start`.
    let timeZoneIdentifier: String

    /// The calendar day this window is filed under, normalised to local midnight of `start`.
    let dayStart: Date

    /// How the boundary was chosen.
    let boundary: DayBoundary

    /// Whether the wake-anchored boundary had to fall back because no sleep record existed.
    let usedFallbackAnchor: Bool

    init(
        start: Date,
        end: Date,
        timeZoneIdentifier: String,
        dayStart: Date,
        boundary: DayBoundary,
        usedFallbackAnchor: Bool
    ) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dayStart = dayStart
        self.boundary = boundary
        self.usedFallbackAnchor = usedFallbackAnchor
    }

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }

    /// The time zone the window was resolved in, or UTC if the stored identifier is unknown
    /// (which can happen if a record travels to a device with an older tz database).
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
    }
}
