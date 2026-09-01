//
//  LiveWorkoutViewModel.swift
//  ZenithiumWatch
//
//  The live session, on the wrist. Yol haritası v4, C1.
//
//  ## What changed, and why it was worth changing
//
//  The watch app was built as a reader: it opened no HealthKit store, held no authorization,
//  and displayed what the phone had already computed. That was the right shape for showing
//  this morning's recovery, and the wrong shape for the one thing a watch is actually better
//  at than a phone — being there during the session.
//
//  So this target now starts workout sessions and reads live heart rate. It still writes
//  nothing to HealthKit beyond the workout itself, and it still computes nothing the phone
//  does not: `LiveSessionEngine` is compiled from `Domain`, which both targets share, so the
//  strain shown mid-run and the strain shown that evening come from one definition.
//
//  ## The starting point comes from the phone
//
//  A session does not begin at zero — the day may already hold strain, and the ceiling comes
//  from a prescription the phone computed this morning. Both arrive through the App Group
//  snapshot the widget already reads. If there is no snapshot the screen still runs; it just
//  has no ceiling to be near, and says so rather than inventing one.
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class LiveWorkoutViewModel {

    enum Phase: Equatable {
        case idle
        case requestingAuthorization
        case running
        case paused
        case ending
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var output: LiveSessionOutput?
    private(set) var elapsedSeconds: Double = 0
    private(set) var heartRate: Double?

    /// What the phone knew when the session started.
    private(set) var ceiling: Double?
    private(set) var strainBeforeSession: Double = 0

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var bridge: LiveWorkoutBridge?
    private var ticker: Task<Void, Never>?

    /// The session's accumulated impulse.
    ///
    /// Replaces the growing `[LiveHeartRateSample]` this used to hold. The engine walked that
    /// array three times per recompute and recomputes happen twice a second, which is
    /// quadratic in session length — around 1.2 billion element visits over four hours. The
    /// track folds each sample in once as it arrives, and `LiveSessionTrackTests` asserts the
    /// total is the same number the engine's own integral produces. Adım 4.
    private var track = LiveSessionTrack(
        restingHeartRate: 60,
        maxHeartRate: 190,
        biologicalSex: .notSet
    )
    private var startedAt: Date?

    /// When the current pause began, and how much paused time has accumulated before it.
    ///
    /// Everything downstream measured time as `Date().timeIntervalSince(startedAt)`, which is
    /// wall clock and counts a pause as if the person were still running. Three things read
    /// it and all three were wrong after a pause: the duration on the watch face jumped
    /// forward by the whole pause on resume, each sample's `elapsedSeconds` carried the same
    /// jump, and the projection — which divides accumulated impulse by elapsed time to reach
    /// a ceiling — read a rate diluted by however long the person had stood still.
    ///
    /// The impulse integral itself was already safe: a pause longer than
    /// `maximumGapSeconds` reads as a gap and contributes nothing. It is the clock around it
    /// that needed fixing.
    private var pausedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0

    /// Identifies this session to the phone. Yol haritası v4, C10.
    private var sessionID = UUID()

    /// Pushes the session's state to the phone, which runs the Live Activity from it.
    private let sender = WatchSessionSender()

    /// Resting and maximum heart rate. Read from the snapshot where the phone has published
    /// them, otherwise the population defaults — a live screen that refuses to run because a
    /// baseline is missing would be useless on exactly the day someone first opens it.
    private var restingHeartRate: Double = 60
    private var maxHeartRate: Double = 190
    private var biologicalSex: BiologicalSexValue = .notSet

    /// The activity the session records.
    var activity: HKWorkoutActivityType = .running

    // MARK: - Lifecycle

    func start() async {
        guard phase == .idle || phase == .finished else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            phase = .failed("Bu cihazda sağlık verisi yok")
            return
        }

        phase = .requestingAuthorization
        readSnapshot()

        do {
            try await requestAuthorization()
            try beginSession()
            phase = .running
            startTicking()
        } catch {
            phase = .failed("Antrenman başlatılamadı")
        }
    }

    func pause() {
        guard phase == .running else { return }
        session?.pause()
        pausedAt = Date()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt {
            accumulatedPausedSeconds += max(0, Date().timeIntervalSince(pausedAt))
        }
        pausedAt = nil
        session?.resume()
        phase = .running
    }

    /// Time the session has actually been running, excluding pauses.
    ///
    /// A pause still in progress counts from the moment it started, so the number does not
    /// creep while the watch face is showing it.
    private func movingSeconds(at date: Date = Date()) -> Double {
        guard let startedAt else { return 0 }
        let pausedSoFar = accumulatedPausedSeconds
            + (pausedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        return max(0, date.timeIntervalSince(startedAt) - pausedSoFar)
    }

    func end() async {
        guard phase == .running || phase == .paused else { return }
        phase = .ending
        ticker?.cancel()
        ticker = nil

        let now = Date()
        session?.end()
        if let builder {
            try? await builder.endCollection(at: now)
            _ = try? await builder.finishWorkout()
        }
        session = nil
        builder = nil
        bridge = nil
        phase = .finished

        // The last push is what ends the phone's Live Activity, so it happens after the
        // phase has moved — a card left running after the run is the one failure here that
        // somebody actually notices.
        if let output {
            push(output, isRunning: false)
        }
    }

    // MARK: - HealthKit

    private func requestAuthorization() async throws {
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        let distance = HKQuantityType(.distanceWalkingRunning)

        try await healthStore.requestAuthorization(
            toShare: [HKQuantityType.workoutType()],
            read: [heartRate, energy, distance]
        )
    }

    private func beginSession() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        // The bridge holds only `@Sendable` closures, so the delegate callbacks can arrive on
        // whatever queue HealthKit uses and still land back here safely.
        let bridge = LiveWorkoutBridge(
            onHeartRate: { [weak self] beatsPerMinute, date in
                Task { @MainActor in self?.record(beatsPerMinute: beatsPerMinute, at: date) }
            },
            onFailure: { [weak self] message in
                Task { @MainActor in self?.phase = .failed(message) }
            }
        )
        session.delegate = bridge
        builder.delegate = bridge

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { _, _ in }

        self.session = session
        self.builder = builder
        self.bridge = bridge
        self.startedAt = now
        self.pausedAt = nil
        self.accumulatedPausedSeconds = 0
        // Built here rather than at declaration, because the rates come from the phone's
        // snapshot and that is read just before this runs.
        self.track = LiveSessionTrack(
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            biologicalSex: biologicalSex
        )
        self.sessionID = UUID()
        sender.start()
    }

    // MARK: - Samples

    private func record(beatsPerMinute: Double, at date: Date) {
        // A sample that arrives while the session is paused is not part of it. HealthKit
        // usually stops delivering across a pause, but "usually" is not a guarantee and a
        // reading folded in here would add impulse to a session nobody is running.
        guard phase == .running, let startedAt, beatsPerMinute > 0 else { return }
        let elapsed = movingSeconds(at: date)
        guard elapsed >= 0 else { return }

        heartRate = beatsPerMinute
        let sample = LiveHeartRateSample(elapsedSeconds: elapsed, beatsPerMinute: beatsPerMinute)
        track.append(sample)
        // Buffered only while the phone is out of touch — the sender decides, because it is
        // the one that knows whether anything is owed.
        sender.record(sample: sample, sessionID: sessionID, startedAt: startedAt)
        recompute()
    }

    /// A one-second tick so the clock and the projection move even between beats.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await MainActor.run {
                    guard self.phase == .running else { return }
                    self.recompute()
                }
            }
        }
    }

    private func recompute() {
        guard startedAt != nil else { return }
        elapsedSeconds = movingSeconds()
        let evaluated = LiveSessionEngine.evaluate(
            LiveSessionInput(
                elapsedSeconds: elapsedSeconds,
                // The track carries the totals; the input carries the retained window, which
                // is all the projection reads.
                samples: track.retained,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate,
                biologicalSex: biologicalSex,
                strainBeforeSession: strainBeforeSession,
                ceiling: ceiling
            ),
            track: track
        )
        output = evaluated
        push(evaluated, isRunning: phase == .running || phase == .paused)
    }

    /// Send the current state to the phone. Throttled by the sender.
    private func push(_ evaluated: LiveSessionOutput, isRunning: Bool) {
        guard let startedAt else { return }
        sender.send(
            LiveSessionSnapshot(
                sessionID: sessionID,
                startedAt: startedAt,
                dayStrain: evaluated.dayStrain,
                ceilingProgress: evaluated.ceilingProgress,
                ceiling: ceiling,
                heartRate: heartRate,
                band: evaluated.band,
                isRunning: isRunning,
                generatedAt: Date()
            )
        )
    }

    // MARK: - The phone's starting point

    private func readSnapshot() {
        let snapshot = WidgetSnapshotStore.read()
        guard snapshot.hasData else { return }
        strainBeforeSession = snapshot.dayStrain
        ceiling = snapshot.targetCeiling
    }
}

/// Carries HealthKit's delegate callbacks back to the model.
///
/// `@unchecked Sendable` because every stored property is an immutable `@Sendable` closure
/// and the class adds no mutable state of its own; the checker cannot see that through
/// `NSObject`. The callbacks hop to the main actor before touching anything.
private final class LiveWorkoutBridge: NSObject, @unchecked Sendable {

    private let onHeartRate: @Sendable (Double, Date) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(
        onHeartRate: @escaping @Sendable (Double, Date) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.onHeartRate = onHeartRate
        self.onFailure = onFailure
    }
}

extension LiveWorkoutBridge: HKWorkoutSessionDelegate {

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // State is driven from the model's own calls; nothing to mirror back.
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        onFailure("Antrenman durdu")
    }
}

extension LiveWorkoutBridge: HKLiveWorkoutBuilderDelegate {

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let date = statistics.mostRecentQuantityDateInterval()?.end ?? Date()
        onHeartRate(quantity.doubleValue(for: unit), date)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Pauses and resumes are already reflected by the model's own phase.
    }
}
