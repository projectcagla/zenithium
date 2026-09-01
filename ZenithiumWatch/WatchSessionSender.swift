//
//  WatchSessionSender.swift
//  ZenithiumWatch
//
//  The watch's end of a running session. Yol haritası v4, C10.
//
//  One job: push the session's current state to the phone so it can run a Live Activity.
//  `updateApplicationContext` is a latest-state-wins channel — a queued payload is replaced
//  rather than stacked — which is exactly right for "here is the number now" and wrong for
//  anything that must not be dropped.
//
//  Throttled, because the session recomputes every second and a Live Activity does not need
//  a new frame every second. Sending less costs nothing anybody can see and saves the radio
//  waking on a run.
//
//  ## What happens when the phone is not there
//
//  It often is not: a phone left at home, in a locker, or simply out of range for a stretch
//  of a run. Until Adım 4 an undeliverable payload was logged and forgotten, which was right
//  for a frame and wrong for the last one — a Live Activity that never hears `isRunning:
//  false` keeps running on the phone long after the session ended.
//
//  So undeliverable payloads go into a `LiveSessionOutbox` instead of the floor, and the
//  outbox is drained the moment `WCSession` says the phone is reachable again. Frames
//  coalesce there, the terminal snapshot is pinned, and the session's samples ride along on
//  `transferUserInfo` so a phone that missed the whole run has something to reconstruct it
//  from.
//

import Foundation
import WatchConnectivity

/// Pushes session snapshots to the phone.
@MainActor
final class WatchSessionSender {

    /// The shortest gap between two pushes.
    ///
    /// Three seconds: a Live Activity updates smoothly at that rate, and the clock on it runs
    /// from `startedAt` rather than from these, so nothing looks stuck between them.
    static let minimumIntervalSeconds: TimeInterval = 3

    private var session: WCSession?
    private var lastSentAt: Date?
    private var lastSentSessionID: UUID?

    /// What could not be delivered yet.
    private(set) var outbox = LiveSessionOutbox()

    /// The session the buffered samples belong to.
    private var bufferedSessionID: UUID?
    private var bufferedStartedAt: Date?

    /// How many drains have actually sent something. Counted for the suite.
    private(set) var flushCount = 0

    private var reachabilityDelegate: ReachabilityWatchDelegate?

    init() {}

    /// Activate the channel. Safe to call more than once.
    func start() {
        guard WCSession.isSupported(), session == nil else { return }
        let session = WCSession.default
        let delegate = ReachabilityWatchDelegate { [weak self] in
            Task { @MainActor in self?.flush() }
        }
        session.delegate = delegate
        session.activate()
        self.session = session
        self.reachabilityDelegate = delegate
    }

    /// Send a snapshot, unless one went recently.
    ///
    /// The end of a session always goes through, whatever the throttle says: a final payload
    /// that was dropped leaves a Live Activity running on a phone after the run has finished,
    /// which is the one failure here somebody would actually notice.
    func send(_ snapshot: LiveSessionSnapshot, now: Date = Date()) {
        guard let session, session.activationState == .activated else {
            // Not activated yet. The terminal snapshot in particular has to survive this,
            // because a session can end before the channel ever comes up.
            outbox.hold(snapshot)
            return
        }

        let isNewSession = snapshot.sessionID != lastSentSessionID
        let isDue = lastSentAt.map { now.timeIntervalSince($0) >= Self.minimumIntervalSeconds } ?? true
        guard !snapshot.isRunning || isNewSession || isDue else { return }

        guard deliver(snapshot, over: session) else {
            outbox.hold(snapshot)
            return
        }
        lastSentAt = now
        lastSentSessionID = snapshot.sessionID
    }

    /// Records a sample so a phone that missed the session can be given it later.
    ///
    /// Only buffered while there is something to catch up on: when the phone is keeping up,
    /// the frames already carry everything it draws and the samples would be dead weight.
    func record(sample: LiveHeartRateSample, sessionID: UUID, startedAt: Date) {
        guard shouldBufferSamples else { return }
        if bufferedSessionID != sessionID {
            bufferedSessionID = sessionID
            bufferedStartedAt = startedAt
        }
        outbox.hold(sample: sample)
    }

    /// Whether the phone is currently out of touch.
    private var shouldBufferSamples: Bool {
        guard let session, session.activationState == .activated else { return true }
        return !session.isReachable || outbox.pendingTerminal != nil
    }

    /// Sends everything the outbox is holding. Called when the phone becomes reachable.
    func flush() {
        guard let session, session.activationState == .activated, !outbox.isEmpty else { return }

        var delivered = false
        for snapshot in outbox.snapshotsToSend where deliver(snapshot, over: session) {
            delivered = true
            lastSentSessionID = snapshot.sessionID
        }
        if delivered {
            outbox.clearSnapshots()
            lastSentAt = Date()
        }

        if var batch = outbox.takeSamples() {
            batch.sessionID = bufferedSessionID ?? batch.sessionID
            batch.startedAt = bufferedStartedAt ?? batch.startedAt

            // Split before sending. A backlog encodes at 53 bytes a sample and
            // WatchConnectivity caps a payload at 65,536, so an hour out of touch produced a
            // 193 KB transfer that was refused asynchronously — through a delegate callback
            // this app does not implement, so it looked like success and delivered nothing.
            //
            // `transferUserInfo` is FIFO and survives termination, so the chunks arrive in
            // the order they were queued and the phone reassembles them.
            var unsent: [LiveHeartRateSample] = []
            for chunk in batch.chunked() {
                guard let userInfo = try? chunk.asUserInfo() else {
                    unsent.append(contentsOf: chunk.samples)
                    continue
                }
                session.transferUserInfo(userInfo)
                delivered = true
            }
            // Anything that could not be encoded goes back rather than on the floor.
            outbox.restore(samples: unsent, droppedCount: batch.droppedCount)
        }
        if delivered { flushCount += 1 }
    }

    /// One push. `false` when it did not go.
    private func deliver(_ snapshot: LiveSessionSnapshot, over session: WCSession) -> Bool {
        guard let context = try? snapshot.asApplicationContext() else { return false }
        do {
            try session.updateApplicationContext(context)
            return true
        } catch {
            // A failed frame costs one frame of a card on another device. A failed terminal
            // snapshot costs a card that never stops, which is why it is held rather than
            // logged and dropped.
            ZenithiumLog.widget.debug("Live session context push failed")
            return false
        }
    }
}

/// A delegate that exists because the API requires one, and reports reachability.
///
/// `@unchecked Sendable`: every stored property is an immutable `@Sendable` closure and the
/// class adds no mutable state, which the checker cannot conclude through `NSObject`.
private final class ReachabilityWatchDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {

    private let onReachable: @Sendable () -> Void

    init(onReachable: @escaping @Sendable () -> Void) {
        self.onReachable = onReachable
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if activationState == .activated { onReachable() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { onReachable() }
    }
}
