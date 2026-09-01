//
//  RacePlanEngineTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C2 — even effort over uneven ground.
//
//  The load-bearing property is that the splits add up: whatever the terrain does, the last
//  split's elapsed time is the target the runner asked for. A pacing plan whose own splits
//  disagree with its own finish time is worse than no plan, because it is wrong in a way
//  nobody notices until the finish line.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Race pacing")
struct RacePlanEngineTests {

    // MARK: - Courses

    /// A perfectly level course.
    private func flatCourse(metres: Double) -> CourseProfile {
        CourseProfile(name: "Düz", points: sampled(metres: metres) { _ in 100 })
    }

    /// Climbs `climb` metres over the first half, then gives it all back.
    private func hillCourse(metres: Double, climb: Double) -> CourseProfile {
        let half = metres / 2
        return CourseProfile(name: "Tepe", points: sampled(metres: metres) { distance in
            distance <= half
                ? 100 + (distance / half) * climb
                : 100 + climb - ((distance - half) / half) * climb
        })
    }

    /// Points every 25 metres, always including the exact finish.
    ///
    /// `stride` stops short of a distance that is not a multiple of the step, which would
    /// silently shorten a half marathon by 22 metres and make the sum test pass against the
    /// wrong course.
    private func sampled(metres: Double, elevation: (Double) -> Double) -> [CoursePoint] {
        var points = stride(from: 0.0, through: metres, by: 25).map {
            CoursePoint(distance: $0, elevation: elevation($0))
        }
        if let last = points.last, last.distance < metres {
            points.append(CoursePoint(distance: metres, elevation: elevation(metres)))
        }
        return points
    }

    // MARK: - The property that matters

    struct SplitScenario: Sendable, CustomTestStringConvertible {
        let metres: Double
        let climb: Double
        let target: Double
        var testDescription: String { "\(metres)m climb:\(climb)m target:\(target)s" }
    }

    static let scenarios: [SplitScenario] = [
        SplitScenario(metres: 10_000.0, climb: 0.0, target: 2700.0),
        SplitScenario(metres: 10_000.0, climb: 100.0, target: 2700.0),
        SplitScenario(metres: 21_097.5, climb: 250.0, target: 6000.0),
        SplitScenario(metres: 42_195.0, climb: 600.0, target: 12600.0),
        SplitScenario(metres: 5_000.0, climb: 40.0, target: 1260.0)
    ]

    @Test("Splitler her zaman hedef süreye toplanıyor", arguments: scenarios)
    func splitsSumToTheTarget(scenario: SplitScenario) throws {
        let metres = scenario.metres
        let climb = scenario.climb
        let target = scenario.target
        let course = climb == 0 ? flatCourse(metres: metres) : hillCourse(metres: metres, climb: climb)
        let plan = try #require(RacePlanEngine.plan(course: course, target: .finishTime(target)))
        let finish = try #require(plan.splits.last?.elapsedSeconds)
        #expect(abs(finish - target) < 0.5, "\(metres)m/\(climb)m: \(finish) vs \(target)")
    }

    @Test("Düz parkurda her split aynı tempoda")
    func flatCourseHasOnePace() throws {
        let plan = try #require(
            RacePlanEngine.plan(course: flatCourse(metres: 10_000), target: .finishTime(45 * 60))
        )
        let paces = plan.splits.map(\.targetPace)
        let low = try #require(paces.min())
        let high = try #require(paces.max())
        #expect(high - low < 0.01)
        #expect(abs(plan.terrainCostRatio - 1) < 0.001)
        #expect(abs(plan.flatEquivalentPace - 270) < 0.5)
    }

    @Test("Yokuş yukarı hedef tempo yavaşlıyor, aşağı hızlanıyor")
    func pacesFollowTheGround() throws {
        let plan = try #require(
            RacePlanEngine.plan(
                course: hillCourse(metres: 10_000, climb: 100),
                target: .finishTime(45 * 60)
            )
        )
        let climbing = plan.splits.prefix(5)
        let descending = plan.splits.suffix(5)

        for split in climbing {
            #expect(split.targetPace > plan.flatEquivalentPace, "km\(split.index) yokuşta hızlanmamalı")
            #expect(split.gradient > 0)
        }
        for split in descending {
            #expect(split.targetPace < plan.flatEquivalentPace, "km\(split.index) inişte yavaşlamamalı")
            #expect(split.gradient < 0)
        }
    }

    @Test("Engebeli zemin düz zeminden pahalı")
    func rollingGroundCostsMore() throws {
        let flat = try #require(
            RacePlanEngine.plan(course: flatCourse(metres: 10_000), target: .finishTime(45 * 60))
        )
        let hill = try #require(
            RacePlanEngine.plan(
                course: hillCourse(metres: 10_000, climb: 100),
                target: .finishTime(45 * 60)
            )
        )
        // Same finish time, so the hilly course demands a faster flat-equivalent effort —
        // which is the whole reason the plan exists.
        #expect(hill.terrainCostRatio > flat.terrainCostRatio)
        #expect(hill.flatEquivalentPace < flat.flatEquivalentPace)
    }

    @Test("Hedef tempo verildiğinde bitiş süresi çıkıyor")
    func aPaceTargetProducesAFinish() throws {
        let course = hillCourse(metres: 10_000, climb: 100)
        let byPace = try #require(RacePlanEngine.plan(course: course, target: .flatPace(270)))
        let byTime = try #require(
            RacePlanEngine.plan(course: course, target: .finishTime(byPace.targetFinishSeconds))
        )
        // The two directions have to agree, or one of them is wrong.
        #expect(abs(byPace.flatEquivalentPace - byTime.flatEquivalentPace) < 0.01)
    }

    // MARK: - Splits

    @Test("Kısa kuyruk kendi satırını almıyor")
    func aShortTailIsFoldedIn() {
        let bounds = RacePlanEngine.splitBounds(totalMetres: 10_040)
        #expect(bounds.count == 10)
        #expect(bounds.last?.end == 10_040)
    }

    @Test("Anlamlı bir kuyruk kendi satırını alıyor")
    func aRealTailKeepsItsRow() {
        let bounds = RacePlanEngine.splitBounds(totalMetres: 10_400)
        #expect(bounds.count == 11)
        #expect(bounds.last?.start == 10_000)
    }

    @Test("Yarı maratonun 97 metrelik kuyruğu son kilometreye katılıyor")
    func halfMarathonEndsCleanly() {
        // 21 full kilometres and 97.5 metres. The tail is below the floor, so it joins the
        // twenty-first split rather than appearing as a "kilometre" of a tenth the length.
        let bounds = RacePlanEngine.splitBounds(totalMetres: 21_097.5)
        #expect(bounds.count == 21)
        #expect(bounds.last?.start == 20_000)
        #expect(bounds.last?.end == 21_097.5)
    }

    // MARK: - Refusals

    @Test("Planlanamayacak parkur nil dönüyor")
    func refusesAnEmptyCourse() {
        let empty = CourseProfile(name: "boş", points: [])
        #expect(RacePlanEngine.plan(course: empty, target: .finishTime(1_800)) == nil)
    }

    @Test("Sıfır veya negatif hedef nil dönüyor")
    func refusesANonPositiveTarget() {
        let course = flatCourse(metres: 5_000)
        #expect(RacePlanEngine.plan(course: course, target: .finishTime(0)) == nil)
        #expect(RacePlanEngine.plan(course: course, target: .flatPace(-1)) == nil)
    }

    // MARK: - Grade cost

    @Test("Eğim maliyeti düz zeminde 1")
    func levelGroundCostsOne() {
        #expect(abs(EnduranceEngine.gradeCostRatio(gradient: 0) - 1) < 0.000_001)
    }

    @Test("Yokuş, aynı eğimdeki inişten daha pahalı")
    func climbingCostsMoreThanDescendingSaves() {
        for percent in [0.01, 0.02, 0.05, 0.08] {
            let up = EnduranceEngine.gradeCostRatio(gradient: percent) - 1
            let down = 1 - EnduranceEngine.gradeCostRatio(gradient: -percent)
            #expect(up > down, "%\(percent * 100)")
        }
    }

    @Test("İnişte maliyet bir noktadan sonra tekrar yükseliyor")
    func steepDescentsCostMoreAgain() {
        // Below about −20% braking takes over. A linear rule would have the cost still
        // falling here, which is why the fitted curve is used instead.
        let moderate = EnduranceEngine.gradeCostRatio(gradient: -0.15)
        let steep = EnduranceEngine.gradeCostRatio(gradient: -0.28)
        #expect(steep > moderate)
    }

    @Test("İleri ve geri dönüşüm birbirini götürüyor")
    func theTwoDirectionsAreInverses() {
        for gradient in [-0.1, -0.02, 0, 0.03, 0.12] {
            let actual = EnduranceEngine.pace(forFlatEquivalent: 300, gradient: gradient)
            let back = EnduranceEngine.gradeAdjustedPace(pace: actual, gradient: gradient)
            #expect(abs(back - 300) < 0.000_001, "eğim \(gradient)")
        }
    }
}
