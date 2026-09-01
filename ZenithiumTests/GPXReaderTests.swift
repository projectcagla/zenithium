//
//  GPXReaderTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C2 — reading a race organiser's course file.
//
//  Organisers export GPX from a dozen different tools, so the parser is tested against the
//  shapes they actually produce: tracks, routes, bare waypoints, namespaced documents, and
//  files with heights missing from some points. The refusals matter as much as the successes:
//  a track without heights must be rejected rather than planned against as though it were
//  flat, because a plan built on a flat assumption is confidently wrong on every hill.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("GPX reading")
struct GPXReaderTests {

    /// A straight north-bound track, one point every ~11 metres of latitude.
    private func track(points: Int, elevation: (Int) -> Double?, element: String = "trkpt") -> Data {
        var body = ""
        for index in 0..<points {
            let latitude = 41.0 + Double(index) * 0.001
            body += "<\(element) lat=\"\(latitude)\" lon=\"29.0\">"
            if let value = elevation(index) {
                body += "<ele>\(value)</ele>"
            }
            body += "</\(element)>\n"
        }
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test">
          <trk><name>İstanbul Yarı</name><trkseg>
        \(body)
          </trkseg></trk>
        </gpx>
        """.utf8)
    }

    // MARK: - Success

    @Test("Düz bir parkur okunuyor")
    func readsAStraightTrack() throws {
        // 0.001° of latitude is about 111 metres, so thirty points is roughly 3.2 km.
        let data = track(points: 30) { 100 + Double($0) }
        let course = try GPXReader.profile(fromGPX: data, fallbackName: "dosya")

        #expect(course.name == "İstanbul Yarı")
        #expect(course.points.count >= 2)
        #expect(course.distance > 3_000)
        #expect(course.distance < 3_500)
        #expect(course.ascent > 25)
        #expect(course.descent == 0)
        #expect(course.isPlannable)
    }

    @Test("Dosyada isim yoksa dosya adı kullanılıyor")
    func fallsBackToTheFileName() throws {
        let data = Data("""
        <gpx version="1.1"><trk><trkseg>
        \((0..<30).map { "<trkpt lat=\"41.\(String(format: "%03d", $0))\" lon=\"29.0\"><ele>100</ele></trkpt>" }.joined())
        </trkseg></trk></gpx>
        """.utf8)
        let course = try GPXReader.profile(fromGPX: data, fallbackName: "maraton-parkur")
        #expect(course.name == "maraton-parkur")
    }

    @Test("Rota ve nokta biçimleri de okunuyor", arguments: ["rtept", "wpt"])
    func readsRoutesAndWaypoints(element: String) throws {
        let data = track(points: 30, elevation: { 100 + Double($0) }, element: element)
        let course = try GPXReader.profile(fromGPX: data, fallbackName: "dosya")
        #expect(course.isPlannable)
        #expect(course.distance > 3_000)
    }

    @Test("Yüksekliği olmayan noktalar mesafeye sayılıyor, profile girmiyor")
    func pointsWithoutHeightStillCount() throws {
        // Every third point has no height. The course must not get shorter because of it.
        let sparse = try GPXReader.profile(
            fromGPX: track(points: 60) { $0 % 3 == 0 ? nil : 100 + Double($0) },
            fallbackName: "dosya"
        )
        let dense = try GPXReader.profile(
            fromGPX: track(points: 60) { 100 + Double($0) },
            fallbackName: "dosya"
        )
        #expect(abs(sparse.distance - dense.distance) < 1)
    }

    @Test("Yakın noktalar seyreltiliyor")
    func closePointsAreThinned() throws {
        // A trace sampled every metre would otherwise turn GPS noise into 100% gradients.
        var body = ""
        for index in 0..<4_000 {
            body += "<trkpt lat=\"\(41.0 + Double(index) * 0.00001)\" lon=\"29.0\"><ele>100</ele></trkpt>"
        }
        let data = Data("<gpx><trk><trkseg>\(body)</trkseg></trk></gpx>".utf8)
        let course = try GPXReader.profile(fromGPX: data, fallbackName: "dosya")

        #expect(course.points.count < 400, "seyreltme çalışmadı: \(course.points.count)")
        #expect(course.distance > 4_000)
    }

    // MARK: - Refusals

    @Test("Parkur içermeyen dosya reddediliyor")
    func refusesAFileWithNoTrack() {
        let data = Data("<gpx version=\"1.1\"><metadata><name>boş</name></metadata></gpx>".utf8)
        #expect(throws: CourseImportFailure.noTrackPoints) {
            try GPXReader.profile(fromGPX: data, fallbackName: "dosya")
        }
    }

    @Test("Yüksekliksiz parkur düz sayılmıyor, reddediliyor")
    func refusesATrackWithoutHeights() {
        #expect(throws: CourseImportFailure.noElevationData) {
            try GPXReader.profile(fromGPX: track(points: 40) { _ in nil }, fallbackName: "dosya")
        }
    }

    @Test("Çok kısa parkur reddediliyor")
    func refusesAShortTrack() {
        // Three points about 111 metres apart — a course, but not one worth pacing.
        #expect(throws: CourseImportFailure.courseTooShort) {
            try GPXReader.profile(fromGPX: track(points: 3) { _ in 100 }, fallbackName: "dosya")
        }
    }

    @Test("Bozuk XML reddediliyor")
    func refusesBrokenXML() {
        let data = Data("<gpx><trk><trkseg><trkpt lat=".utf8)
        #expect(throws: CourseImportFailure.unreadableFile) {
            try GPXReader.profile(fromGPX: data, fallbackName: "dosya")
        }
    }

    // MARK: - Interpolation

    @Test("Ara yükseklikler doğrusal olarak okunuyor")
    func elevationInterpolatesBetweenPoints() throws {
        let course = CourseProfile(
            name: "test",
            points: [
                CoursePoint(distance: 0, elevation: 100),
                CoursePoint(distance: 1_000, elevation: 200),
                CoursePoint(distance: 2_000, elevation: 150)
            ]
        )
        #expect(course.elevation(atDistance: 0) == 100)
        #expect(course.elevation(atDistance: 500) == 150)
        #expect(course.elevation(atDistance: 1_000) == 200)
        #expect(course.elevation(atDistance: 1_500) == 175)
        #expect(course.elevation(atDistance: 2_000) == 150)
    }

    @Test("Parkur dışı mesafeler uçlara sabitleniyor")
    func elevationClampsOutsideTheCourse() throws {
        let course = CourseProfile(
            name: "test",
            points: [
                CoursePoint(distance: 0, elevation: 100),
                CoursePoint(distance: 1_000, elevation: 200)
            ]
        )
        #expect(course.elevation(atDistance: -50) == 100)
        #expect(course.elevation(atDistance: 5_000) == 200)
    }

    @Test("Tırmanış ve iniş ayrı ayrı toplanıyor")
    func ascentAndDescentAreSeparate() {
        let course = CourseProfile(
            name: "test",
            points: [
                CoursePoint(distance: 0, elevation: 100),
                CoursePoint(distance: 500, elevation: 160),
                CoursePoint(distance: 1_000, elevation: 130),
                CoursePoint(distance: 1_500, elevation: 180)
            ]
        )
        #expect(course.ascent == 110)
        #expect(course.descent == 30)
        #expect(course.distance == 1_500)
    }
}
