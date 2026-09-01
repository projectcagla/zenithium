//
//  LiveSessionOutbox.swift
//  Zenithium
//
//  What the watch owes the phone when the two are not talking. Adım 4.
//
//  ## The two things that cross, and why they are not the same thing
//
//  **Frames** are the running state — strain now, heart rate now, which band. They go
//  through `updateApplicationContext`, which is latest-state-wins: a queued payload is
//  replaced rather than stacked. That is exactly right, because a frame from forty seconds
//  ago is worthless the moment a newer one exists. Losing frames costs nothing.
//
//  **The end of the session** is not a frame, even though it looks like one. It is the only
//  payload whose loss is visible: a Live Activity that never receives `isRunning: false`
//  keeps running on the phone after the person has finished, showered and sat down. The
//  sender already forced the terminal push past its own throttle, but a throttle is not the
//  thing that drops it — an unreachable phone is, and there was nothing to retry with.
//
//  ## What the outbox holds
//
//  One coalescing slot for the newest frame, and a separate pinned slot for the terminal
//  snapshot that the frame slot cannot overwrite. On reconnection the terminal snapshot goes
//  first: if a session ended while the phone was away, the phone's first news of it should
//  be that it is over, not a frame from the middle of it.
//
//  Alongside those, a bounded backlog of the session's own samples. Those are not for the
//  Live Activity — the phone still does not recompute a running session, and
//  `LiveSessionSnapshot`'s comment about two implementations of one integral still holds.
//  They are for the case where the phone was away for the whole session and the terminal
//  snapshot is all it will ever get: with the samples it can replay `LiveSessionEngine` —
//  the *same* engine, compiled from the same `Domain` files — and reconstruct what the watch
//  showed, instead of having a session it knows ended but nothing about.
//
//  ## Bounded, and honest about it
//
//  The backlog has a cap. A four-hour session produces around fourteen thousand samples and
//  `transferUserInfo` is not a bulk channel; past the cap the oldest samples are dropped and
//  `droppedSampleCount` says how many. A partial replay that says it is partial is worth
//  more than a queue that grows until the watch app is killed for memory.
//

import Foundation

/// Holds what could not be sent, until it can be.
struct LiveSessionOutbox: Sendable, Equatable {

    /// The most samples carried across a reconnection.
    ///
    /// About an hour at one sample a second. Beyond that the replay is partial anyway, and
    /// the terminal snapshot — which is never dropped — already carries the final numbers.
    static let maximumBufferedSamples = 3_600

    /// The newest frame waiting to go. Replaced, never queued.
    private(set) var pendingFrame: LiveSessionSnapshot?

    /// The terminal snapshot, held apart so a later frame cannot displace it.
    ///
    /// In practice nothing arrives after it, but "in practice" is how a Live Activity ends up
    /// running for three hours after a run.
    private(set) var pendingTerminal: LiveSessionSnapshot?

    /// Samples recorded while the phone was unreachable, oldest first.
    private(set) var bufferedSamples: [LiveHeartRateSample] = []

    /// How many samples were dropped to stay inside the cap.
    private(set) var droppedSampleCount = 0

    init() {}

    /// Whether anything is waiting.
    var isEmpty: Bool {
        pendingFrame == nil && pendingTerminal == nil && bufferedSamples.isEmpty
    }

    /// Records a snapshot that could not be delivered.
    mutating func hold(_ snapshot: LiveSessionSnapshot) {
        if snapshot.isRunning {
            // Newest wins, and only when it is actually newer: application context is
            // coalesced and can be handed back out of order.
            if let existing = pendingFrame, existing.generatedAt > snapshot.generatedAt { return }
            pendingFrame = snapshot
        } else {
            if let existing = pendingTerminal, existing.generatedAt > snapshot.generatedAt { return }
            pendingTerminal = snapshot
            // A session that has ended has no running frame worth sending.
            pendingFrame = nil
        }
    }

    /// Records a sample that the phone has not been told about.
    mutating func hold(sample: LiveHeartRateSample) {
        bufferedSamples.append(sample)
        if bufferedSamples.count > Self.maximumBufferedSamples {
            let excess = bufferedSamples.count - Self.maximumBufferedSamples
            bufferedSamples.removeFirst(excess)
            droppedSampleCount += excess
        }
    }

    /// What to send, in the order it should go.
    ///
    /// The terminal snapshot leads: if a session ended while the phone was away, the phone's
    /// first news of it should be that it is over.
    var snapshotsToSend: [LiveSessionSnapshot] {
        [pendingTerminal, pendingFrame].compactMap { $0 }
    }

    /// Clears the snapshots once they have gone.
    mutating func clearSnapshots() {
        pendingFrame = nil
        pendingTerminal = nil
    }

    /// Takes the buffered samples, leaving the outbox empty of them.
    mutating func takeSamples() -> LiveSessionSampleBatch? {
        guard !bufferedSamples.isEmpty else { return nil }
        let batch = LiveSessionSampleBatch(
            samples: bufferedSamples,
            droppedCount: droppedSampleCount
        )
        bufferedSamples.removeAll()
        droppedSampleCount = 0
        return batch
    }

    /// Puts a taken backlog back, oldest first, when it could not be sent after all.
    ///
    /// `takeSamples()` empties the buffer before the caller knows whether the transfer went.
    /// Without this the one failure path — an encoding error — dropped the whole backlog on
    /// the floor, silently, in the type whose entire job is not doing that.
    mutating func restore(samples: [LiveHeartRateSample], droppedCount: Int) {
        guard !samples.isEmpty else { return }
        bufferedSamples.insert(contentsOf: samples, at: 0)
        droppedSampleCount += droppedCount
        if bufferedSamples.count > Self.maximumBufferedSamples {
            let excess = bufferedSamples.count - Self.maximumBufferedSamples
            bufferedSamples.removeFirst(excess)
            droppedSampleCount += excess
        }
    }
}

/// A run of samples the watch could not deliver while it happened.
///
/// Sent through `WCSession.transferUserInfo` rather than the application context: that is a
/// FIFO queue that survives the app being terminated and does not coalesce, which is what
/// "must not be dropped" needs. The application context is the opposite of those things by
/// design, and using it here would silently discard all but the last batch.
struct LiveSessionSampleBatch: Codable, Sendable, Equatable {

    /// The session these belong to, so a batch arriving after the next session started can
    /// be recognised as belonging to the previous one.
    var sessionID: UUID = UUID()

    /// When the session started, so `elapsedSeconds` can be turned back into wall time.
    var startedAt: Date = Date(timeIntervalSince1970: 0)

    /// The samples, oldest first.
    let samples: [LiveHeartRateSample]

    /// How many older samples were dropped to stay inside the cap. A replay built from this
    /// batch is incomplete by exactly this much, and the phone is told rather than left to
    /// assume the run began where the batch begins.
    let droppedCount: Int

    /// Where this batch sits in the run of transfers that carry one backlog, and how many
    /// there are. `0` of `1` is a backlog that fitted in a single transfer.
    ///
    /// Defaulted so a caller that does not care about chunking — the tests, and anything
    /// building a batch to inspect — keeps the two-argument initializer.
    var chunkIndex: Int = 0
    var chunkCount: Int = 1

    /// Whether the batch covers the session from its start.
    var isComplete: Bool { droppedCount == 0 }

    /// Whether this is the last transfer of its backlog.
    var isFinalChunk: Bool { chunkIndex == chunkCount - 1 }

    /// How many samples one `transferUserInfo` carries.
    ///
    /// WatchConnectivity caps a payload at 65,536 bytes and reports an oversize one
    /// asynchronously, through a delegate callback this app does not implement — so an
    /// oversize backlog did not fail loudly, it simply never arrived. Measured, the encoding
    /// costs 53 bytes a sample, so the cap of 3,600 produced a 193 KB payload: every outage
    /// longer than about twenty minutes silently delivered nothing, which is exactly the
    /// outage the outbox exists for.
    ///
    /// 500 samples measures 26 KB at the start of a session and 28 KB in its fourth hour —
    /// `elapsedSeconds` encodes wider as it grows — so the worst case is 42% of the budget.
    /// 600 was tried first and reached 51% late in a session, which is not a margin.
    static let maximumSamplesPerTransfer = 500

    /// Splits a backlog into transfers that each fit.
    ///
    /// `droppedCount` rides on the first chunk only — it describes the backlog, not the
    /// piece — so a receiver adding them up gets the number that was actually dropped.
    func chunked(maximumPerChunk: Int = maximumSamplesPerTransfer) -> [LiveSessionSampleBatch] {
        let size = max(1, maximumPerChunk)
        guard samples.count > size else { return [self] }

        var chunks: [LiveSessionSampleBatch] = []
        var start = samples.startIndex
        while start < samples.endIndex {
            let end = samples.index(start, offsetBy: size, limitedBy: samples.endIndex) ?? samples.endIndex
            var chunk = LiveSessionSampleBatch(
                samples: Array(samples[start..<end]),
                droppedCount: chunks.isEmpty ? droppedCount : 0
            )
            chunk.sessionID = sessionID
            chunk.startedAt = startedAt
            chunks.append(chunk)
            start = end
        }
        for index in chunks.indices {
            chunks[index].chunkIndex = index
            chunks[index].chunkCount = chunks.count
        }
        return chunks
    }

    /// A property-list dictionary for `WCSession.transferUserInfo`.
    func asUserInfo() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return [Self.userInfoKey: try encoder.encode(self)]
    }

    /// The reverse, or `nil` when the payload is not one of these.
    static func from(userInfo: [String: Any]) -> LiveSessionSampleBatch? {
        guard let data = userInfo[userInfoKey] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LiveSessionSampleBatch.self, from: data)
    }

    /// The only key the two sides agree on.
    static let userInfoKey = "com.zenithium.liveSessionSamples"
}
