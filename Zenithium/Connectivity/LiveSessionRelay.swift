//
//  LiveSessionRelay.swift
//  Zenithium
//
//  The phone's end of a running session. Yol haritası v4, C10.
//
//  ## The shape
//
//  The watch owns the session: it has the heart rate, it runs `LiveSessionEngine`, and it
//  pushes a `LiveSessionSnapshot` through `WCSession.updateApplicationContext` about once a
//  second. This receives those and drives a Live Activity from them.
//
//  `updateApplicationContext` rather than `sendMessage` because the semantics are right:
//  it is a latest-state-wins channel that coalesces when delivery is slow and does not need
//  the phone to be reachable at that instant. A session in a pocket on a run is exactly the
//  case `sendMessage` handles badly.
//
//  ## What the phone does not do
//
//  It does not recompute a *running* session. The strain shown in the Dynamic Island is the
//  number the watch calculated, carried across — not a second implementation of the same
//  integral running on a different device with a slower copy of the samples. Two
//  implementations of one number is the drift this project spent four waves removing.
//
//  There is one exception, and it is not a second implementation. When the phone was out of
//  range for a whole session it receives a `LiveSessionSampleBatch` afterwards, and replays
//  it through `LiveSessionEngine` — the same engine, compiled from the same `Domain` file the
//  watch compiled. Same code, same constants, run once at the end rather than continuously.
//  Without it a phone that missed a run knows only that one ended.
//
//  ## Ordering
//
//  Application context is coalesced, so a payload can arrive after a newer one. Every
//  snapshot carries `generatedAt` and anything older than what is already displayed is
//  dropped, which is cheaper and more obvious than trying to make the channel ordered.
//

import Foundation

#if canImport(ActivityKit) && canImport(WatchConnectivity)
import ActivityKit
import WatchConnectivity

/// Receives session snapshots from the watch and runs the Live Activity.
@MainActor
@Observable
final class LiveSessionRelay {

    /// The most recent snapshot, or `nil` when no session is running.
    private(set) var snapshot: LiveSessionSnapshot?

    /// Why the relay is not running, when it is not.
    private(set) var unavailableReason: String?

    /// The last session reconstructed from a delivered sample backlog, when there was one.
    ///
    /// Held so the Today screen can say a session happened while the phone was away, rather
    /// than the app silently knowing nothing until HealthKit syncs the workout.
    private(set) var replayedSession: LiveSessionOutput?

    /// Whether that replay covered the session from its start.
    private(set) var replayWasComplete = true

    private var session: WCSession?
    private var bridge: LiveSessionBridge?
    private var activityID: String?

    /// Chunks of one backlog, held until the last one lands.
    ///
    /// A backlog longer than 600 samples arrives as several `transferUserInfo` payloads.
    /// They are FIFO and belong to one session, so they are concatenated before the engine
    /// sees them — replaying each chunk on its own would show the last twenty minutes of a
    /// run and call it the session.
    private var pendingChunks: (sessionID: UUID, samples: [LiveHeartRateSample], droppedCount: Int)?

    init() {}

    /// Start listening. Safe to call more than once.
    func start() {
        guard WCSession.isSupported() else {
            unavailableReason = "Bu cihaz Apple Watch ile eşleşmiyor"
            return
        }
        guard session == nil else { return }

        let bridge = LiveSessionBridge(
            onContext: { [weak self] snapshot in
                Task { @MainActor in self?.receive(snapshot) }
            },
            onUserInfo: { [weak self] batch in
                Task { @MainActor in self?.receiveBacklog(batch) }
            }
        )
        let session = WCSession.default
        session.delegate = bridge
        session.activate()

        self.bridge = bridge
        self.session = session

        // A context may already be waiting from before the app launched.
        if let snapshot = LiveSessionSnapshot.from(applicationContext: session.receivedApplicationContext) {
            receive(snapshot)
        }
    }

    // MARK: - Receiving

    private func receive(_ incoming: LiveSessionSnapshot) {
        // Coalesced delivery can hand over an older payload after a newer one.
        if let snapshot, incoming.generatedAt <= snapshot.generatedAt,
           incoming.sessionID == snapshot.sessionID {
            return
        }

        snapshot = incoming
        Task { await apply(incoming) }
    }

    /// Gathers a chunked backlog, answering only once the last piece has arrived.
    ///
    /// A chunk whose session does not match what is being gathered replaces it: the watch
    /// sends one backlog at a time, so a new session's first chunk means the previous
    /// backlog was cut short and will not be completed.
    private func accumulate(_ chunk: LiveSessionSampleBatch) -> LiveSessionSampleBatch? {
        if chunk.chunkCount <= 1 { pendingChunks = nil; return chunk }

        if var pending = pendingChunks, pending.sessionID == chunk.sessionID {
            pending.samples.append(contentsOf: chunk.samples)
            pending.droppedCount += chunk.droppedCount
            pendingChunks = pending
        } else {
            pendingChunks = (chunk.sessionID, chunk.samples, chunk.droppedCount)
        }

        guard chunk.isFinalChunk, let pending = pendingChunks else { return nil }
        pendingChunks = nil
        var assembled = LiveSessionSampleBatch(
            samples: pending.samples,
            droppedCount: pending.droppedCount
        )
        assembled.sessionID = chunk.sessionID
        assembled.startedAt = chunk.startedAt
        return assembled
    }

    /// Replays a backlog of samples the watch could not deliver while the session ran.
    ///
    /// Runs the shared engine once over what arrived. The result is a summary of a session
    /// that is already over, not a live reading, so nothing here touches the Live Activity.
    private func receiveBacklog(_ chunk: LiveSessionSampleBatch) {
        // Nothing to replay until the last chunk of this backlog has arrived.
        guard let batch = accumulate(chunk) else { return }
        guard let last = batch.samples.last else { return }

        // The rates the watch used are not in the batch, and inventing them would produce a
        // number that disagrees with the watch's. The snapshot the watch published carries
        // the day's figures, so the replay is anchored to the same starting point.
        let published = WidgetSnapshotStore.read()
        let output = LiveSessionEngine.evaluate(
            LiveSessionInput(
                elapsedSeconds: last.elapsedSeconds,
                samples: batch.samples,
                restingHeartRate: Self.fallbackRestingHeartRate,
                maxHeartRate: Self.fallbackMaxHeartRate,
                biologicalSex: .notSet,
                strainBeforeSession: published.hasData ? published.dayStrain : 0,
                ceiling: published.targetCeiling
            )
        )
        replayedSession = output
        replayWasComplete = batch.isComplete
        ZenithiumLog.widget.notice(
            "Replayed \(batch.samples.count, privacy: .public) buffered live-session samples"
        )
    }

    /// Used only when replaying a backlog, where the watch's own rates did not travel with
    /// the samples. Deliberately the same population defaults the watch falls back to, so the
    /// two do not disagree by construction.
    private static let fallbackRestingHeartRate: Double = 60
    private static let fallbackMaxHeartRate: Double = 190

    private func currentActivity() -> Activity<LiveSessionAttributes>? {
        if let activityID {
            return Activity<LiveSessionAttributes>.activities.first(where: { $0.id == activityID })
        }
        return Activity<LiveSessionAttributes>.activities.first
    }

    private func apply(_ incoming: LiveSessionSnapshot) async {
        guard incoming.isRunning else {
            await end(incoming)
            return
        }
        if let activity = currentActivity(), activity.attributes.sessionID == incoming.sessionID {
            self.activityID = activity.id
            await update(with: incoming)
        } else {
            // A different session started while one was showing — end the old one rather
            // than leaving two, which is what happens if the watch app is relaunched.
            if currentActivity() != nil { await dismiss() }
            await begin(incoming)
        }
    }

    private func begin(_ incoming: LiveSessionSnapshot) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            unavailableReason = "Canlı Etkinlikler kapalı"
            return
        }
        let attributes = LiveSessionAttributes(
            sessionID: incoming.sessionID,
            startedAt: incoming.startedAt
        )
        let content = ActivityContent(
            state: LiveSessionAttributes.ContentState(snapshot: incoming),
            // Stale after a few minutes without an update: a session whose watch went out of
            // range should read as stale rather than as frozen at the last number it saw.
            staleDate: Date().addingTimeInterval(Self.staleAfterSeconds)
        )
        if let activity = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
            self.activityID = activity.id
            unavailableReason = nil
        } else {
            self.activityID = nil
            unavailableReason = "Canlı Etkinlik başlatılamadı"
        }
    }

    private func update(with incoming: LiveSessionSnapshot) async {
        guard let activityID else { return }
        let content = ActivityContent(
            state: LiveSessionAttributes.ContentState(snapshot: incoming),
            staleDate: Date().addingTimeInterval(Self.staleAfterSeconds)
        )
        await Self.updateLiveActivity(id: activityID, content: content)
    }

    private func end(_ incoming: LiveSessionSnapshot) async {
        guard let activityID else {
            self.activityID = nil
            snapshot = nil
            return
        }
        let content = ActivityContent(
            state: LiveSessionAttributes.ContentState(snapshot: incoming),
            staleDate: nil
        )
        await Self.endLiveActivity(
            id: activityID,
            content: content,
            dismissalPolicy: .after(.now + Self.finalDisplaySeconds)
        )
        self.activityID = nil
        snapshot = nil
    }

    private func dismiss() async {
        guard let activityID else { return }
        await Self.dismissLiveActivity(id: activityID)
        self.activityID = nil
    }

    private nonisolated static func updateLiveActivity(
        id: String,
        content: ActivityContent<LiveSessionAttributes.ContentState>
    ) async {
        for activity in Activity<LiveSessionAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    private nonisolated static func endLiveActivity(
        id: String,
        content: ActivityContent<LiveSessionAttributes.ContentState>,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        for activity in Activity<LiveSessionAttributes>.activities where activity.id == id {
            await activity.end(content, dismissalPolicy: dismissalPolicy)
        }
    }

    private nonisolated static func dismissLiveActivity(id: String) async {
        for activity in Activity<LiveSessionAttributes>.activities where activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// How long a snapshot stays fresh.
    static let staleAfterSeconds: TimeInterval = 180

    /// How long the finished card stays on screen.
    static let finalDisplaySeconds: TimeInterval = 60
}

/// Carries `WCSession`'s delegate callbacks onto the main actor.
///
/// `@unchecked Sendable` for the same reason as the HealthKit bridge: one immutable
/// `@Sendable` closure and no mutable state of its own, which the checker cannot see through
/// `NSObject`.
private final class LiveSessionBridge: NSObject, WCSessionDelegate, @unchecked Sendable {

    private let onContext: @Sendable (LiveSessionSnapshot) -> Void
    private let onUserInfo: @Sendable (LiveSessionSampleBatch) -> Void

    init(
        onContext: @escaping @Sendable (LiveSessionSnapshot) -> Void,
        onUserInfo: @escaping @Sendable (LiveSessionSampleBatch) -> Void
    ) {
        self.onContext = onContext
        self.onUserInfo = onUserInfo
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        if let snapshot = LiveSessionSnapshot.from(applicationContext: session.receivedApplicationContext) {
            onContext(snapshot)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let snapshot = LiveSessionSnapshot.from(applicationContext: applicationContext) {
            onContext(snapshot)
        }
    }

    /// The backlog channel. FIFO and not coalesced, unlike the application context.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let batch = LiveSessionSampleBatch.from(userInfo: userInfo) {
            onUserInfo(batch)
        }
    }

    // Required on iOS. Both mean the watch went away, and neither needs anything here: the
    // activity's stale date already handles a session that stops reporting.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
