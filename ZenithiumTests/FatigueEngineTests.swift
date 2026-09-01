//
//  FatigueEngineTests.swift
//  ZenithiumTests
//
//  Spec §11 golden vector 3, plus superposition, mass classes and the projection window.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Fatigue engine")
struct FatigueEngineTests {

    private let now = iso("2025-06-10T18:00:00Z")

    private func impact(
        on muscle: MuscleGroup,
        load: Double,
        hoursAgo: Double,
        involvement: Double = 1.0
    ) -> MuscleSessionImpact {
        MuscleSessionImpact(
            timestamp: now.addingTimeInterval(-hoursAgo * TimeConversion.secondsPerHour),
            source: .workout(id: UUID(), activity: .running),
            sessionLoad: load,
            involvement: [muscle: involvement]
        )
    }

    // MARK: - §11 golden vector 3

    @Test("Golden vector 3 — impact 70, medium mass class, sleep 80, at 24 hours")
    func goldenFatigue() {
        // Triceps is a medium group, so its mass-class multiplier is 1.00.
        #expect(MuscleGroup.triceps.massClass == .medium)

        let modifier = FatigueEngine.sleepModifier(forSleepScore: 80)
        expectClose(modifier, 0.87, tolerance: 0.005, "sleepModifier")

        let halfLife = FatigueEngine.halfLifeHours(for: .triceps, sleepModifier: modifier)
        expectClose(halfLife, 20.88, tolerance: 0.005, "t½")

        let lambda = FatigueEngine.decayConstant(forHalfLifeHours: halfLife)
        expectClose(lambda, 0.033197, tolerance: GoldenTolerance.tight, "λ")

        let projection = FatigueEngine.project(
            FatigueInput(
                sessions: [impact(on: .triceps, load: 70, hoursAgo: 24)],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        let triceps = projection[.triceps]
        expectClose(triceps?.fatigue ?? .nan, 31.56, "Fatigue at 24 h")
        expectClose(triceps?.readiness ?? .nan, 68.4, "Readiness at 24 h")
    }

    // MARK: - §5.4 mass classes

    @Test("Mass classes match the specification")
    func massClasses() {
        let large: [MuscleGroup] = [.quads, .hamstrings, .glutes, .lats, .upperBack, .chest, .lowerBack]
        let medium: [MuscleGroup] = [.shoulders, .triceps, .core, .adductors, .traps]
        let small: [MuscleGroup] = [.biceps, .forearms, .calves, .neck]

        for muscle in large { #expect(muscle.massClass == .large) }
        for muscle in medium { #expect(muscle.massClass == .medium) }
        for muscle in small { #expect(muscle.massClass == .small) }
        #expect(large.count + medium.count + small.count == MuscleGroup.allCases.count)
    }

    @Test("A larger group holds fatigue longer")
    func largeGroupsDecaySlower() {
        let modifier = FatigueEngine.sleepModifier(forSleepScore: 80)
        let large = FatigueEngine.halfLifeHours(for: .quads, sleepModifier: modifier)
        let medium = FatigueEngine.halfLifeHours(for: .triceps, sleepModifier: modifier)
        let small = FatigueEngine.halfLifeHours(for: .calves, sleepModifier: modifier)
        #expect(large > medium)
        #expect(medium > small)
        expectClose(large / medium, 1.15, tolerance: 1e-9, "large multiplier")
        expectClose(small / medium, 0.85, tolerance: 1e-9, "small multiplier")
    }

    // MARK: - §5.4 sleep modifier

    @Test("The sleep modifier is clamped to 0.75…1.35")
    func sleepModifierClamped() {
        expectClose(FatigueEngine.sleepModifier(forSleepScore: 0), 1.35, tolerance: 1e-9, "score 0")
        expectClose(FatigueEngine.sleepModifier(forSleepScore: 100), 0.75, tolerance: 1e-9, "score 100")
        expectClose(FatigueEngine.sleepModifier(forSleepScore: 200), 0.75, tolerance: 1e-9, "beyond range")
        // Better sleep shortens the half-life, so fatigue clears faster.
        #expect(FatigueEngine.sleepModifier(forSleepScore: 90) < FatigueEngine.sleepModifier(forSleepScore: 50))
    }

    @Test("The neutral sleep score yields a 1.0 modifier (ORCH-1)")
    func neutralSleepScoreIsNeutral() {
        expectClose(
            FatigueEngine.sleepModifier(forSleepScore: DailyRecalculationCoordinator.neutralSleepScore),
            1.0,
            tolerance: 1e-9,
            "neutral modifier"
        )
    }

    // MARK: - §5.4 superposition

    @Test("Two sessions on one muscle add rather than replace")
    func impactsSuperpose() {
        let single = FatigueEngine.project(
            FatigueInput(
                sessions: [impact(on: .quads, load: 40, hoursAgo: 12)],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        let double = FatigueEngine.project(
            FatigueInput(
                sessions: [
                    impact(on: .quads, load: 40, hoursAgo: 12),
                    impact(on: .quads, load: 40, hoursAgo: 12)
                ],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        expectClose(
            double[.quads]?.fatigue ?? .nan,
            2 * (single[.quads]?.fatigue ?? 0),
            tolerance: 1e-6,
            "superposed fatigue"
        )
        #expect(double[.quads]?.contributingSessionCount == 2)
    }

    @Test("Fatigue is capped at 100 and readiness floored at 0")
    func fatigueIsCapped() {
        let sessions = (0..<10).map { _ in impact(on: .chest, load: 100, hoursAgo: 0.5) }
        let projection = FatigueEngine.project(
            FatigueInput(sessions: sessions, sleepScore: 50, now: now, projectionWindow: nil)
        )
        expectClose(projection[.chest]?.fatigue ?? .nan, 100, tolerance: 1e-9, "capped fatigue")
        expectClose(projection[.chest]?.readiness ?? .nan, 0, tolerance: 1e-9, "floored readiness")
    }

    @Test("Involvement scales a session's impact")
    func involvementScales() {
        let projection = FatigueEngine.project(
            FatigueInput(
                sessions: [impact(on: .calves, load: 100, hoursAgo: 0, involvement: 0.7)],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        expectClose(projection[.calves]?.fatigue ?? .nan, 70, tolerance: 1e-6, "70% involvement")
    }

    // MARK: - ASSUMPTION MUSCLE-3 window

    @Test("Sessions outside the projection window are excluded")
    func windowTruncates() {
        let projection = FatigueEngine.project(
            FatigueInput(
                sessions: [impact(on: .glutes, load: 100, hoursAgo: 24 * 20)],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        expectClose(projection[.glutes]?.fatigue ?? .nan, 0, tolerance: 1e-9, "twenty days ago")
    }

    @Test("A future session is ignored rather than amplified")
    func futureSessionsIgnored() {
        let future = MuscleSessionImpact(
            timestamp: now.addingTimeInterval(3600),
            source: .workout(id: UUID(), activity: .running),
            sessionLoad: 100,
            involvement: [.quads: 1.0]
        )
        let projection = FatigueEngine.project(
            FatigueInput(sessions: [future], sleepScore: 80, now: now, projectionWindow: nil)
        )
        expectClose(projection[.quads]?.fatigue ?? .nan, 0, tolerance: 1e-9, "future session")
    }

    // MARK: - Coverage

    @Test("Every group is projected, even with no sessions at all")
    func allGroupsProjected() {
        let projection = FatigueEngine.project(
            FatigueInput(sessions: [], sleepScore: 80, now: now, projectionWindow: nil)
        )
        #expect(projection.count == MuscleGroup.allCases.count)
        for muscle in MuscleGroup.allCases {
            expectClose(projection[muscle]?.readiness ?? .nan, 100, tolerance: 1e-9, muscle.rawValue)
            #expect(projection[muscle]?.dominantSource == nil)
        }
    }

    @Test("The dominant contributor is the largest remaining, not the most recent")
    func dominantIsLargestRemaining() {
        let heavyOlder = MuscleSessionImpact(
            timestamp: now.addingTimeInterval(-6 * 3600),
            source: .strengthLog(id: UUID(), pattern: .squat),
            sessionLoad: 90,
            involvement: [.quads: 1.0]
        )
        let lightRecent = MuscleSessionImpact(
            timestamp: now.addingTimeInterval(-1 * 3600),
            source: .workout(id: UUID(), activity: .walking),
            sessionLoad: 5,
            involvement: [.quads: 1.0]
        )
        let projection = FatigueEngine.project(
            FatigueInput(
                sessions: [heavyOlder, lightRecent],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        if case .strengthLog = projection[.quads]?.dominantSource {
            // The heavier older session still dominates six hours later.
        } else {
            Issue.record("Expected the heavier older session to dominate")
        }
    }

    @Test("Projecting forward decays monotonically toward full readiness")
    func forwardProjectionDecays() {
        let projection = FatigueEngine.project(
            FatigueInput(
                sessions: [impact(on: .lats, load: 80, hoursAgo: 0)],
                sleepScore: 80,
                now: now,
                projectionWindow: nil
            )
        )
        guard let lats = projection[.lats] else {
            Issue.record("Lats missing from projection")
            return
        }
        var previous = -1.0
        for hours in stride(from: 0.0, through: 168.0, by: 4.0) {
            let value = FatigueEngine.projectedReadiness(for: .lats, from: lats, hoursAhead: hours)
            #expect(value >= previous)
            #expect(value <= 100)
            previous = value
        }
        #expect(previous > 99)
    }
}
