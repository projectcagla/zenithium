//
//  BoundedConcurrency.swift
//  Zenithium
//
//  One bounded task group, used everywhere a batch of independent reads is issued.
//
//  ## Why a helper rather than three hand-rolled groups
//
//  Three sites fan out reads: the baseline fetch and the overnight fetch in
//  `HealthKitService`, and the eighteen vital signs in `VitalsViewModel`. Two of them were
//  unbounded — legal only because `MetricKind` happens to have four cases today. The bound
//  was therefore a property of an enum somebody could extend, not a property of the code
//  that needs it, and adding a fifth metric would have widened the fan-out silently.
//
//  This makes the bound explicit and puts it in one place. It also fixes the ordering
//  problem the hand-rolled versions each solved differently: results come back in input
//  order, not in completion order, so a screen is laid out the same way on every launch
//  without the caller re-sorting.
//
//  ## Isolation
//
//  `operation` is `@Sendable` and every child runs on the global executor, so a caller that
//  is an actor or `@MainActor` does not serialise the batch on its own executor. The
//  accumulator is local to the group body, so nothing crosses an isolation boundary that is
//  not already `Sendable`.
//

import Foundation

/// Concurrency ceilings that are a property of the resource, not of the caller.
enum ZenithiumConcurrency {

    /// How many HealthKit reads may be in flight at once.
    ///
    /// HealthKit serialises the underlying queries against its own store anyway, so past a
    /// handful in flight the extra children only add scheduling. Four is enough to keep the
    /// pipe full while leaving the store responsive to the foreground query a user's tap
    /// just issued.
    static let maximumConcurrentHealthReads = 4
}

/// Runs `operation` over `inputs` with at most `limit` children in flight, and returns the
/// results in `inputs` order.
///
/// The group never grows past `limit`: a new child is started only as a finished one is
/// collected. `operation` cannot throw — a batch where one input's failure must not cancel
/// the rest has to model that failure as a value, which every call site here already does.
func withBoundedTaskGroup<Input: Sendable, Output: Sendable>(
    over inputs: [Input],
    limit: Int,
    operation: @Sendable @escaping (Input) async -> Output
) async -> [Output] {
    guard !inputs.isEmpty else { return [] }
    let bound = max(1, min(limit, inputs.count))

    return await withTaskGroup(
        of: (index: Int, value: Output).self,
        returning: [Output].self
    ) { group in
        var collected: [(index: Int, value: Output)] = []
        collected.reserveCapacity(inputs.count)
        var started = 0

        func startNext() {
            let index = started
            let input = inputs[index]
            group.addTask { (index, await operation(input)) }
            started += 1
        }

        while started < bound {
            startNext()
        }

        while let finished = await group.next() {
            collected.append(finished)
            if started < inputs.count { startNext() }
        }

        // Sorted rather than written into pre-sized slots: an `[Output?]` accumulator makes
        // the element type doubly optional whenever `Output` is itself optional — which one
        // call site's is — and unwrapping that cleanly costs more than sorting eighteen
        // pairs ever will.
        return collected.sorted { $0.index < $1.index }.map(\.value)
    }
}
