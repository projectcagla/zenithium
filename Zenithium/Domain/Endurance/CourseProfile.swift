//
//  CourseProfile.swift
//  Zenithium
//
//  A race course, as distance and height. Yol haritası v4, C2.
//
//  Everything downstream of this file works in two numbers per point — how far along the
//  course, and how high. Latitude and longitude are used once, to turn a track into
//  distances, and then discarded: a pacing plan has no use for where in the world the course
//  is, and not carrying the coordinates forward means they cannot end up somewhere they
//  should not be.
//

import Foundation

/// One point on a course: how far in, and how high.
struct CoursePoint: Sendable, Equatable, Hashable {

    /// Metres from the start, along the ground.
    let distance: Double

    /// Metres above sea level.
    let elevation: Double
}

/// A course, ready to plan against.
struct CourseProfile: Sendable, Equatable, Hashable, Identifiable {

    /// What the file called it, or the file's own name.
    let name: String

    /// Points in order, starting at distance zero.
    let points: [CoursePoint]

    var id: String { name }

    /// Total length, metres.
    var distance: Double { points.last?.distance ?? 0 }

    /// Total climb, metres. Only rises count.
    var ascent: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1.elevation - pair.0.elevation)
        }
    }

    /// Total descent, metres, as a positive number.
    var descent: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.0.elevation - pair.1.elevation)
        }
    }

    /// The lowest and highest points, for the chart's axis.
    var elevationRange: ClosedRange<Double>? {
        let elevations = points.map(\.elevation)
        guard let low = elevations.min(), let high = elevations.max() else { return nil }
        return high > low ? low...high : (low - 1)...(high + 1)
    }

    /// Whether there is enough here to plan against.
    var isPlannable: Bool { points.count >= 2 && distance > 0 }

    /// The elevation at a distance, linearly interpolated between the points either side.
    ///
    /// Linear rather than a spline: a course profile is a sampled polyline already, and a
    /// smoothing interpolation would invent gradients that the recorded track does not have.
    func elevation(atDistance target: Double) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if target <= first.distance { return first.elevation }
        if target >= last.distance { return last.elevation }

        // Points are ordered, so a binary search finds the bracketing pair without walking
        // a course that may hold tens of thousands of samples.
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if points[middle].distance <= target {
                low = middle
            } else {
                high = middle
            }
        }
        let start = points[low]
        let end = points[high]
        let span = end.distance - start.distance
        guard span > 0 else { return start.elevation }
        let fraction = (target - start.distance) / span
        return start.elevation + (end.elevation - start.elevation) * fraction
    }
}

/// What went wrong reading a course file.
enum CourseImportFailure: Error, Sendable, Equatable {

    /// The file could not be read at all.
    case unreadableFile

    /// The file parsed but held no track.
    case noTrackPoints

    /// The track has points but no heights, so there is nothing to adjust a pace for.
    case noElevationData

    /// The track is too short to plan against.
    case courseTooShort
}

extension CourseImportFailure: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Bu dosya okunamadı"
        case .noTrackPoints: return "Dosyada bir parkur bulunamadı"
        case .noElevationData: return "Parkurda yükseklik verisi yok"
        case .courseTooShort: return "Parkur plan yapılamayacak kadar kısa"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadableFile, .noTrackPoints:
            return "Yarışın sitesinden indirdiğin .gpx dosyasını seç."
        case .noElevationData:
            return "Yükseklik içeren bir GPX gerekiyor — çoğu yarış parkuru içerir."
        case .courseTooShort:
            return "En az bir kilometrelik bir parkur gerekiyor."
        }
    }
}
