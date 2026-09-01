//
//  SleepScoreEngineTests.swift
//  ZenithiumTests
//
//  Spec §5.2, §5.6 validity rules, and the §11 DST-crossing requirement.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Sleep score engine")
struct SleepScoreEngineTests {

    private func input(
        asleepHours: Double = 7.4,
        timeInBedHours: Double = 8.0,
        deepHours: Double = 1.1,
        remHours: Double = 1.6,
        hasStageData: Bool = true,
        midpointMinutes: Double = 190,
        midpointBaseline: Double? = 210,
        baselineNeed: Double = 8.0,
        yesterdayStrain: Double = 12.0,
        debtHours: Double = 0.4,
        napHours: Double = 0
    ) -> SleepInput {
        let asleep = asleepHours * 3600
        let deep = deepHours * 3600
        let rem = remHours * 3600
        return SleepInput(
            asleepSeconds: asleep,
            timeInBedSeconds: timeInBedHours * 3600,
            deepSeconds: deep,
            remSeconds: rem,
            coreSeconds: max(asleep - deep - rem, 0),
            awakeSeconds: 900,
            hasStageData: hasStageData,
            midpointMinutesFromLocalMidnight: midpointMinutes,
            midpointBaselineMinutes: midpointBaseline,
            baselineNeedHours: baselineNeed,
            yesterdayStrain: yesterdayStrain,
            sleepDebtHours: debtHours,
            napCreditHours: napHours
        )
    }

    // MARK: - §5.2 need model

    @Test("Need is baseline plus strain and debt, minus naps")
    func needModel() {
        // 8.0 + 0.25·(12/21) + min(0.4, 1.5) − 0
        let expected = 8.0 + 0.25 * (12.0 / 21.0) + 0.4
        expectClose(SleepScoreEngine.need(for: input()), expected, tolerance: 1e-9, "need")
    }

    @Test("Debt is capped at 1.5 hours and nap credit at 1.0")
    func capsApply() {
        let output = SleepScoreEngine.compute(input(debtHours: 5.0, napHours: 4.0))
        expectClose(output.appliedDebtHours, 1.5, tolerance: 1e-9, "debt cap")
        expectClose(output.appliedNapCreditHours, 1.0, tolerance: 1e-9, "nap cap")
    }

    @Test("Need can never fall low enough to make a short night look complete")
    func needIsFloored() {
        let output = SleepScoreEngine.compute(
            input(asleepHours: 2.5, baselineNeed: 5.0, debtHours: 0, napHours: 4.0)
        )
        #expect(output.needHours >= 1.0)
        #expect((output.score ?? 100) < 100)
    }

    // MARK: - §5.2 components

    @Test("The four components compute as specified")
    func componentMaths() {
        let sleepInput = input()
        let output = SleepScoreEngine.compute(sleepInput)
        let need = output.needHours

        expectClose(
            output.component(.duration)?.score ?? .nan,
            100 * min(7.4 / need, 1),
            tolerance: 1e-6,
            "Duration"
        )
        expectClose(
            output.component(.efficiency)?.score ?? .nan,
            100 * min(max((7.4 / 8.0 - 0.75) / 0.20, 0), 1),
            tolerance: 1e-6,
            "Efficiency"
        )
        expectClose(
            output.component(.restorative)?.score ?? .nan,
            100 * min(((1.1 + 1.6) / 7.4) / 0.42, 1),
            tolerance: 1e-6,
            "Restorative"
        )
        // |190 − 210| = 20 minutes of drift against a 90-minute tolerance.
        expectClose(
            output.component(.consistency)?.score ?? .nan,
            100 * (1 - 20.0 / 90.0),
            tolerance: 1e-6,
            "Consistency"
        )
    }

    @Test("Component weights match the specification")
    func componentWeights() {
        let output = SleepScoreEngine.compute(input())
        expectClose(output.component(.duration)?.weight ?? .nan, 0.50, tolerance: 1e-9, "Duration")
        expectClose(output.component(.efficiency)?.weight ?? .nan, 0.20, tolerance: 1e-9, "Efficiency")
        expectClose(output.component(.restorative)?.weight ?? .nan, 0.20, tolerance: 1e-9, "Restorative")
        expectClose(output.component(.consistency)?.weight ?? .nan, 0.10, tolerance: 1e-9, "Consistency")
    }

    @Test("Unstaged sleep drops Restorative and renormalizes to 0.625 / 0.25 / 0.125")
    func unstagedRenormalization() {
        let output = SleepScoreEngine.compute(input(hasStageData: false))

        #expect(output.droppedComponents == [.restorative])
        expectClose(output.component(.duration)?.weight ?? .nan, 0.625, tolerance: 1e-9, "Duration")
        expectClose(output.component(.efficiency)?.weight ?? .nan, 0.25, tolerance: 1e-9, "Efficiency")
        expectClose(output.component(.consistency)?.weight ?? .nan, 0.125, tolerance: 1e-9, "Consistency")
        expectClose(
            output.components.map(\.weight).reduce(0, +),
            1.0,
            tolerance: 1e-9,
            "weights sum"
        )
    }

    @Test("Without a midpoint baseline, Consistency is dropped rather than scored perfect")
    func consistencyDroppedWithoutBaseline() {
        let output = SleepScoreEngine.compute(input(midpointBaseline: nil))
        #expect(output.droppedComponents.contains(.consistency))
        expectClose(output.components.map(\.weight).reduce(0, +), 1.0, tolerance: 1e-9, "weights sum")
    }

    // MARK: - §5.6 validity

    @Test("Nights under two hours or over fourteen are rejected")
    func validityBounds() {
        #expect(SleepScoreEngine.compute(input(asleepHours: 1.5)).validity == .tooShort)
        #expect(SleepScoreEngine.compute(input(asleepHours: 14.5)).validity == .tooLong)
        #expect(SleepScoreEngine.compute(input(asleepHours: 0)).validity == .noData)
        #expect(SleepScoreEngine.compute(input(asleepHours: 7.4)).validity == .valid)

        #expect(SleepScoreEngine.compute(input(asleepHours: 1.5)).score == nil)
        #expect(SleepScoreEngine.compute(input(asleepHours: 1.5)).validity.dataQualityReason == .sleepTooShort)
    }

    // MARK: - ASSUMPTION SLEEP-2 contiguity

    @Test("Short awake interruptions do not split the night")
    func shortInterruptionsToleratedAsOneBlock() {
        let start = iso("2025-06-01T23:00:00Z")
        let segments = [
            sleepSegment(from: start, to: start.addingTimeInterval(2 * 3600), stage: .asleepCore),
            // A ten-minute wake: inside the fifteen-minute tolerance.
            sleepSegment(
                from: start.addingTimeInterval(2 * 3600 + 600),
                to: start.addingTimeInterval(5 * 3600),
                stage: .asleepCore
            )
        ]
        let block = SleepScoreEngine.longestAsleepBlock(in: segments)
        #expect(block != nil)
        expectClose(block?.asleepSeconds ?? 0, 5 * 3600 - 600, tolerance: 1, "asleep seconds")
        expectClose(block?.interval.duration ?? 0, 5 * 3600, tolerance: 1, "block span")
    }

    @Test("A long awake run splits the night, and the longer block wins")
    func longInterruptionSplits() {
        let start = iso("2025-06-01T22:00:00Z")
        let segments = [
            // A 40-minute early block.
            sleepSegment(from: start, to: start.addingTimeInterval(40 * 60), stage: .asleepCore),
            // Then two hours awake, then the real night.
            sleepSegment(
                from: start.addingTimeInterval(3 * 3600),
                to: start.addingTimeInterval(9 * 3600),
                stage: .asleepCore
            )
        ]
        let block = SleepScoreEngine.longestAsleepBlock(in: segments)
        expectClose(block?.asleepSeconds ?? 0, 6 * 3600, tolerance: 1, "longest block")
        #expect(block?.interval.start == start.addingTimeInterval(3 * 3600))
    }

    @Test("`.inBed` never counts as asleep")
    func inBedIsNotAsleep() {
        let start = iso("2025-06-01T23:00:00Z")
        let segments = [
            sleepSegment(from: start, to: start.addingTimeInterval(8 * 3600), stage: .inBed),
            sleepSegment(
                from: start.addingTimeInterval(600),
                to: start.addingTimeInterval(7 * 3600),
                stage: .asleepCore
            )
        ]
        expectClose(segments.asleepSeconds, 7 * 3600 - 600, tolerance: 1, "asleep excludes inBed")
    }

    // MARK: - §11 DST crossing

    @Test("A night crossing spring-forward is measured in absolute time")
    func dstCrossingNight() {
        // America/New_York springs forward on 2025-03-09 at 02:00 local.
        // 23:00 EST on the 8th is 04:00 UTC; 07:00 EDT on the 9th is 11:00 UTC.
        // Seven hours of actual sleep, though the wall clock advanced by eight.
        let sleepStart = iso("2025-03-09T04:00:00Z")
        let wake = iso("2025-03-09T11:00:00Z")
        let segments = [
            sleepSegment(from: sleepStart, to: wake, stage: .asleepCore, timeZoneIdentifier: "America/New_York")
        ]

        let block = SleepScoreEngine.longestAsleepBlock(in: segments)
        expectClose(block?.asleepSeconds ?? 0, 7 * 3600, tolerance: 1, "absolute asleep seconds")

        // The midpoint renders in local wall-clock: 03:30 EDT, which is 210 minutes.
        let calendar = TestCalendars.newYork
        let midpoint = SleepScoreEngine.midpoint(of: block?.interval ?? DateInterval())
        let minutes = SleepScoreEngine.minutesFromLocalMidnight(midpoint, calendar: calendar)
        expectClose(minutes, 210, tolerance: 1, "local midpoint minutes")

        // And the night is scored, not rejected — seven hours is a normal night.
        let output = SleepScoreEngine.compute(
            input(asleepHours: 7.0, timeInBedHours: 7.2, midpointMinutes: minutes)
        )
        #expect(output.validity == .valid)
    }

    // MARK: - §5.2 debt and naps

    @Test("Sleep debt decays 25% per night across a seven-night window")
    func debtDecays() {
        let shortfalls = [1.0, 1.0, 1.0]
        let expected = 1.0 + 0.75 + 0.5625
        expectClose(
            SleepScoreEngine.sleepDebt(shortfallsNewestFirst: shortfalls),
            expected,
            tolerance: 1e-9,
            "decayed debt"
        )
    }

    @Test("Only the trailing seven nights count toward debt")
    func debtWindowIsSeven() {
        let long = Array(repeating: 1.0, count: 30)
        let seven = Array(repeating: 1.0, count: 7)
        expectClose(
            SleepScoreEngine.sleepDebt(shortfallsNewestFirst: long),
            SleepScoreEngine.sleepDebt(shortfallsNewestFirst: seven),
            tolerance: 1e-9,
            "window truncation"
        )
    }

    @Test("Naps under twenty minutes contribute nothing")
    func shortNapsIgnored() {
        let start = iso("2025-06-01T14:00:00Z")
        let shortNap = [sleepSegment(from: start, to: start.addingTimeInterval(15 * 60), stage: .asleepCore)]
        let realNap = [sleepSegment(from: start, to: start.addingTimeInterval(30 * 60), stage: .asleepCore)]

        expectClose(SleepScoreEngine.napCredit(from: shortNap), 0, tolerance: 1e-9, "15-minute nap")
        expectClose(SleepScoreEngine.napCredit(from: realNap), 0.5, tolerance: 1e-9, "30-minute nap")
    }

    // MARK: - ASSUMPTION SLEEP-5 circular mean

    @Test("Midpoints either side of midnight average correctly")
    func circularMidpointMean() {
        // 23:50 is 1430 minutes; 00:10 is 10 minutes. The mean is midnight, not midday.
        let mean = SleepScoreEngine.midpointBaseline(minutes: [1430, 10])
        #expect(mean != nil)
        let distanceFromMidnight = abs(
            MathSupport.circularDifference(mean ?? 0, 0, period: 1440)
        )
        #expect(distanceFromMidnight < 1)
    }

    @Test("Consistency uses circular distance, not wall-clock subtraction")
    func consistencyIsCircular() {
        // 23:50 against a 00:10 baseline is twenty minutes of drift.
        let output = SleepScoreEngine.compute(
            input(midpointMinutes: 1430, midpointBaseline: 10)
        )
        expectClose(
            output.component(.consistency)?.score ?? .nan,
            100 * (1 - 20.0 / 90.0),
            tolerance: 1e-6,
            "Consistency across midnight"
        )
    }
}
