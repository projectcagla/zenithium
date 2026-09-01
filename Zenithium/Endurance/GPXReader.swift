//
//  GPXReader.swift
//  Zenithium
//
//  Turning a race organiser's GPX into a course profile. Yol haritası v4, C2.
//
//  GPX is XML, and `XMLParser` is in Foundation, so this needs nothing that is not already on
//  the framework list. The parser is deliberately forgiving about structure — track, route or
//  bare waypoints all yield points, because organisers export all three — and deliberately
//  strict about content: a track without heights is refused rather than planned against as if
//  it were flat.
//
//  Distances come from the haversine formula on the WGS-84 mean radius. A course is a few
//  tens of kilometres of running, not a great-circle flight, so the spherical approximation
//  is well inside the noise of a consumer GPS trace.
//

import Foundation

/// Reads GPX files into course profiles.
actor GPXReader {

    /// Points closer together than this are merged.
    ///
    /// GPS traces contain samples a metre or two apart, and a two-metre horizontal step with
    /// a two-metre vertical error in it reads as a 100% gradient. Resampling to a floor makes
    /// the gradients describe the course rather than the receiver.
    static let minimumSpacingMetres: Double = 25

    /// Below this a course is not worth pacing.
    static let minimumCourseMetres: Double = 1_000

    /// Read `url` into a course profile.
    func read(fileURL url: URL) throws -> CourseProfile {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw CourseImportFailure.unreadableFile
        }
        let name = url.deletingPathExtension().lastPathComponent
        return try Self.profile(fromGPX: data, fallbackName: name)
    }

    /// Parse GPX bytes into a profile. Pure, so it can be tested without a file.
    static func profile(fromGPX data: Data, fallbackName: String) throws -> CourseProfile {
        let delegate = GPXTrackCollector()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw CourseImportFailure.unreadableFile }

        let fixes = delegate.fixes
        guard !fixes.isEmpty else { throw CourseImportFailure.noTrackPoints }
        guard fixes.contains(where: { $0.elevation != nil }) else {
            throw CourseImportFailure.noElevationData
        }

        let points = resample(fixes)
        guard points.count >= 2, let total = points.last?.distance,
              total >= minimumCourseMetres else {
            throw CourseImportFailure.courseTooShort
        }

        let name = delegate.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CourseProfile(
            name: (name?.isEmpty == false ? name : nil) ?? fallbackName,
            points: points
        )
    }

    // MARK: - Geometry

    /// Cumulative distance along the fixes, thinned to `minimumSpacingMetres`.
    ///
    /// Fixes without a height are still used for distance — dropping them would shorten the
    /// course — but never emitted as points, because a point with no height has no gradient.
    private static func resample(_ fixes: [GPXFix]) -> [CoursePoint] {
        var points: [CoursePoint] = []
        var travelled: Double = 0
        var previous: GPXFix?
        var lastEmitted: Double = -.greatestFiniteMagnitude

        for fix in fixes {
            if let previous {
                travelled += distance(from: previous, to: fix)
            }
            previous = fix

            guard let elevation = fix.elevation else { continue }
            let isFirst = points.isEmpty
            let isFarEnough = travelled - lastEmitted >= minimumSpacingMetres
            guard isFirst || isFarEnough else { continue }

            // The first emitted point anchors the course at zero even when the track began
            // with a few height-less fixes.
            points.append(CoursePoint(distance: isFirst ? 0 : travelled, elevation: elevation))
            lastEmitted = travelled
        }

        // Always keep the last fix with a height, so the course ends where the track does.
        if let last = fixes.last(where: { $0.elevation != nil }),
           let elevation = last.elevation,
           let final = points.last,
           travelled - final.distance > 1 {
            points.append(CoursePoint(distance: travelled, elevation: elevation))
        }
        return points
    }

    /// Great-circle distance between two fixes, metres.
    private static func distance(from start: GPXFix, to end: GPXFix) -> Double {
        let earthRadius: Double = 6_371_008.8
        let radians = Double.pi / 180
        let lat1 = start.latitude * radians
        let lat2 = end.latitude * radians
        let deltaLat = (end.latitude - start.latitude) * radians
        let deltaLon = (end.longitude - start.longitude) * radians

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

/// One point as the file recorded it.
private struct GPXFix: Sendable {
    let latitude: Double
    let longitude: Double
    var elevation: Double?
}

/// Collects `trkpt`, `rtept` and `wpt` elements, in document order.
private final class GPXTrackCollector: NSObject, XMLParserDelegate {

    private(set) var fixes: [GPXFix] = []
    private(set) var name: String?

    private var currentText = ""
    private var isInsideName = false
    private var hasTakenName = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentText = ""
        switch elementName {
        case "trkpt", "rtept", "wpt":
            guard let latitude = Double(attributes["lat"] ?? ""),
                  let longitude = Double(attributes["lon"] ?? "") else { return }
            fixes.append(GPXFix(latitude: latitude, longitude: longitude, elevation: nil))
        case "name":
            // The first name in the file — the track's, or the file's own metadata.
            isInsideName = !hasTakenName
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "ele":
            guard let elevation = Double(currentText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  !fixes.isEmpty else { break }
            fixes[fixes.count - 1].elevation = elevation
        case "name":
            if isInsideName {
                name = currentText
                hasTakenName = true
                isInsideName = false
            }
        default:
            break
        }
        currentText = ""
    }
}
