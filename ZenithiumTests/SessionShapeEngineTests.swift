//
//  SessionShapeEngineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C8 — the sessions somebody keeps doing.
//
//  The roadmap asked for workouts to be classified into Hyrox stations. They cannot be: a
//  sled push and a set of wall balls both arrive as "functional strength training, 42
//  minutes", and guessing would fill a log with stations nobody did. What is genuinely in the
//  data is repetition, so that is what these tests are about — and the bucketing, because a
//  bucket that is too tight recognises nothing and one that is too loose calls a jog and a
//  long run the same session.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Session shapes")
struct SessionShapeEngineTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func workout(
        daysAgo: Double,
        activity: WorkoutActivity = .running,
        minutes: Double,
        kilometres: Double?,
        heartRate: Double? = 148
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            activity: activity,
            interval: DateInterval(
                start: now.addingTimeInterval(-daysAgo * 86_400),
                duration: minutes * 60
            ),
            activeEnergyKilocalories: nil,
            distanceMeters: kilometres.map { $0 * 1_000 },
            averageHeartRate: heartRate,
            sourceBundleIdentifier: nil
        )
    }

    // MARK: - Recognition

    @Test("Haftalık tekrar eden koşu tanınıyor")
    func aweeklyRunIsRecognised() throws {
        let workouts = (0..<8).map {
            workout(daysAgo: Double($0) * 7, minutes: 41 + Double($0 % 3), kilometres: 8.0 + Double($0 % 3) * 0.2)
        }
        let shapes = SessionShapeEngine.shapes(from: workouts, now: now)
        let shape = try #require(shapes.first)
        #expect(shape.activity == .running)
        #expect(shape.occurrences == 8)
        #expect(shape.isEstablished)
        #expect(abs((shape.kilometres ?? 0) - 8.2) < 0.3)
        #expect(shape.displayName.contains("km"))
    }

    @Test("İki kez yapılan bir şey alışkanlık sayılmıyor")
    func twiceIsNotAHabit() {
        let workouts = [
            workout(daysAgo: 3, minutes: 45, kilometres: 9),
            workout(daysAgo: 10, minutes: 46, kilometres: 9.1)
        ]
        #expect(SessionShapeEngine.shapes(from: workouts, now: now).isEmpty)
    }

    @Test("Farklı uzunluktaki seanslar tek şekle karışmıyor")
    func differentLengthsStaySeparate() {
        let short = (0..<4).map { workout(daysAgo: Double($0) * 5, minutes: 22, kilometres: 4) }
        let long = (0..<4).map { workout(daysAgo: Double($0) * 5 + 2, minutes: 75, kilometres: 15) }
        let shapes = SessionShapeEngine.shapes(from: short + long, now: now)
        #expect(shapes.count == 2)
        #expect(Set(shapes.map(\.minutesLow)).count == 2)
    }

    @Test("Farklı etkinlikler ayrı şekiller")
    func differentActivitiesStaySeparate() {
        let runs = (0..<4).map { workout(daysAgo: Double($0) * 5, minutes: 40, kilometres: 8) }
        let rides = (0..<4).map {
            workout(daysAgo: Double($0) * 5 + 1, activity: .cycling, minutes: 40, kilometres: 8)
        }
        let shapes = SessionShapeEngine.shapes(from: runs + rides, now: now)
        #expect(shapes.count == 2)
        #expect(Set(shapes.map(\.activity)) == [.running, .cycling])
    }

    @Test("Mesafesiz seanslar mesafesi sıfır olanlarla karışmıyor")
    func distancelessSessionsAreTheirOwnShape() {
        let strength = (0..<4).map {
            workout(daysAgo: Double($0) * 4, activity: .traditionalStrengthTraining, minutes: 45, kilometres: nil)
        }
        let shapes = SessionShapeEngine.shapes(from: strength, now: now)
        #expect(shapes.count == 1)
        #expect(shapes.first?.kilometres == nil)
        #expect(shapes.first?.displayName.contains("dk") == true)
    }

    // MARK: - Filters

    @Test("Çok kısa kayıtlar seans sayılmıyor")
    func veryShortRecordsAreNotSessions() {
        let workouts = (0..<6).map { workout(daysAgo: Double($0) * 3, minutes: 4, kilometres: 0.7) }
        #expect(SessionShapeEngine.shapes(from: workouts, now: now).isEmpty)
    }

    @Test("Pencere dışındaki seanslar sayılmıyor")
    func oldSessionsFallOutOfTheWindow() {
        let old = (0..<6).map {
            workout(daysAgo: 200 + Double($0), minutes: 40, kilometres: 8)
        }
        #expect(SessionShapeEngine.shapes(from: old, now: now).isEmpty)
    }

    @Test("Gelecekteki kayıtlar sayılmıyor")
    func futureRecordsAreIgnored() {
        let future = (0..<5).map { workout(daysAgo: -Double($0) - 1, minutes: 40, kilometres: 8) }
        #expect(SessionShapeEngine.shapes(from: future, now: now).isEmpty)
    }

    // MARK: - Ordering

    @Test("Sık olan önce geliyor")
    func themostFrequentComesFirst() throws {
        let often = (0..<9).map { workout(daysAgo: Double($0) * 3, minutes: 40, kilometres: 8) }
        let seldom = (0..<3).map { workout(daysAgo: Double($0) * 9 + 1, minutes: 90, kilometres: 20) }
        let shapes = SessionShapeEngine.shapes(from: often + seldom, now: now)
        #expect(shapes.first?.occurrences == 9)
        #expect(shapes.last?.occurrences == 3)
    }

    // MARK: - Naming

    @Test("İsimler betimleyici, yorum içermiyor")
    func namesDescribeRatherThanInterpret() throws {
        let workouts = (0..<5).map { workout(daysAgo: Double($0) * 6, minutes: 40, kilometres: 8) }
        let shape = try #require(SessionShapeEngine.shapes(from: workouts, now: now).first)
        let name = shape.displayName.lowercased()
        // The app does not know whether that Tuesday was a tempo or a commute.
        for word in ["tempo", "interval", "kolay", "sert", "toparlanma", "uzun koşu"] {
            #expect(!name.contains(word), "\(word)")
        }
    }
}
