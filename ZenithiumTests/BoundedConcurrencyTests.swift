//
//  BoundedConcurrencyTests.swift
//  ZenithiumTests
//
//  The two properties `withBoundedTaskGroup` exists for, asserted as counts rather than
//  timings: the ceiling actually holds, and answers come back in input order.
//
//  Both matter for a reason a reader can check. Exceeding the ceiling is how eighteen vital
//  reads used to arrive at HealthKit at once; returning in completion order is how a screen
//  ends up laid out differently on each launch.
//

import Testing
import Foundation
@testable import Zenithium

/// Tracks how many children were running at the same time.
private actor ConcurrencyPeak {

    private var current = 0

    /// The highest simultaneous count seen. Monotonic, which is what lets a child wait on it
    /// without the value moving back under it.
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

@Suite("Bounded task group")
struct BoundedConcurrencyTests {

    @Test("Aynı anda tavandan fazla çocuk koşmuyor")
    func neverExceedsTheCeiling() async {
        let peak = ConcurrencyPeak()

        let results = await withBoundedTaskGroup(over: Array(0..<24), limit: 4) { value -> Int in
            await peak.enter()
            await Task.yield()
            await peak.leave()
            return value
        }

        #expect(results.count == 24)
        #expect(await peak.peak <= 4)
    }

    /// The ceiling being respected is worth nothing if the group only ever runs one child.
    /// Each child waits until the ceiling has actually been reached, so a group that
    /// serialised would exhaust the spin and fail rather than quietly pass.
    @Test("Tavan kadar çocuk gerçekten aynı anda koşuyor")
    func reachesTheCeiling() async {
        let peak = ConcurrencyPeak()

        _ = await withBoundedTaskGroup(over: Array(0..<12), limit: 4) { value -> Int in
            await peak.enter()
            var spins = 0
            while await peak.peak < 4, spins < 100_000 {
                await Task.yield()
                spins += 1
            }
            await peak.leave()
            return value
        }

        #expect(await peak.peak == 4)
    }

    @Test("Sonuçlar giriş sırasında dönüyor, bitiş sırasında değil")
    func answersInInputOrder() async {
        let inputs = Array(0..<10)

        let results = await withBoundedTaskGroup(over: inputs, limit: 3) { value -> Int in
            // Later inputs finish sooner, so completion order is close to the reverse of
            // input order. Anything that collected results as they arrived would show it.
            for _ in 0..<(inputs.count - value) {
                await Task.yield()
            }
            return value
        }

        #expect(results == inputs)
    }

    @Test("Tavan giriş sayısından büyükse fazladan çocuk başlatılmıyor")
    func ceilingAboveInputCountStartsOnlyWhatIsNeeded() async {
        let peak = ConcurrencyPeak()

        let results = await withBoundedTaskGroup(over: [1, 2], limit: 16) { value -> Int in
            await peak.enter()
            await Task.yield()
            await peak.leave()
            return value * 10
        }

        #expect(results == [10, 20])
        #expect(await peak.peak <= 2)
    }

    @Test("Boş giriş hiç çocuk başlatmıyor")
    func emptyInputDoesNothing() async {
        let results = await withBoundedTaskGroup(over: [Int](), limit: 4) { value -> Int in
            Issue.record("boş girdi için çocuk başlatıldı")
            return value
        }
        #expect(results.isEmpty)
    }

    @Test("Sıfır ya da negatif tavan yine de ilerliyor")
    func nonPositiveCeilingStillMakesProgress() async {
        let results = await withBoundedTaskGroup(over: Array(0..<5), limit: 0) { value -> Int in
            value + 1
        }
        #expect(results == [1, 2, 3, 4, 5])
    }
}
