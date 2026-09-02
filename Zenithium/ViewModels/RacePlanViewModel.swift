//
//  RacePlanViewModel.swift
//  Zenithium
//
//  The race pacing screen. Yol haritası v4, C2.
//

import Foundation
import Observation

@MainActor
@Observable
final class RacePlanViewModel {

    struct Content: Sendable, Equatable {
        let plan: RacePlan

        /// A finish the runner's own recent efforts support, when the endurance model has
        /// enough to say so, and how far outside its fitted range that sits.
        let suggestion: (seconds: Double, extrapolation: Double)?

        static func == (lhs: Content, rhs: Content) -> Bool {
            lhs.plan == rhs.plan
                && lhs.suggestion?.seconds == rhs.suggestion?.seconds
                && lhs.suggestion?.extrapolation == rhs.suggestion?.extrapolation
        }
    }

    private(set) var state: ViewState<Content> = .noData(reason: .nothingLogged(what: "parkur"))
    private(set) var isReading = false

    /// Why the last file could not be read. Shown beside the picker rather than replacing the
    /// screen: the person still has the button they need, and the sentence says what to fix.
    private(set) var importError: String?

    /// The target the runner has dialled in, seconds. Bound to the stepper.
    var targetFinishSeconds: Double = 45 * 60

    private let reader: GPXReader
    private let health: any HealthDataProviding
    private let nowProvider: @Sendable () -> Date

    /// The course, kept so the target can be changed without re-reading the file.
    private var course: CourseProfile?

    /// The critical-speed model, read once when a course arrives.
    private var model: CriticalSpeedModel?

    init(
        reader: GPXReader = GPXReader(),
        health: any HealthDataProviding,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.health = health
        self.nowProvider = nowProvider
    }

    /// The course currently loaded, if any.
    var loadedCourse: CourseProfile? { course }

    // MARK: - Loading

    func load(fileURL: URL) async {
        isReading = true
        importError = nil
        defer { isReading = false }

        do {
            let profile = try await reader.read(fileURL: fileURL)
            course = profile
            model = await criticalSpeedModel()

            // Open on a target the runner can actually run rather than on a round number,
            // when there is enough history to name one.
            if let model, let suggested = RacePlanEngine.suggestedFinish(course: profile, model: model) {
                targetFinishSeconds = (suggested.seconds / 30).rounded() * 30
            }
            rebuild()
        } catch let failure as CourseImportFailure {
            course = nil
            importError = [failure.errorDescription, failure.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
            state = .noData(reason: .nothingLogged(what: "parkur"))
        } catch {
            course = nil
            importError = "Bu dosya okunamadı. Yarışın sitesinden indirdiğin .gpx dosyasını seç."
            state = .noData(reason: .nothingLogged(what: "parkur"))
        }
    }

    /// Rebuild the plan for the current target. Cheap — nothing is re-read.
    func rebuild() {
        guard let course else { return }
        guard let plan = RacePlanEngine.plan(
            course: course,
            target: .finishTime(targetFinishSeconds)
        ) else {
            state = .noData(reason: .nothingLogged(what: "planlanabilir bir parkur"))
            return
        }
        state = .loaded(
            Content(
                plan: plan,
                suggestion: model.flatMap { RacePlanEngine.suggestedFinish(course: course, model: $0) }
            )
        )
    }

    /// Move the target by a number of seconds, keeping it positive.
    func adjustTarget(bySeconds delta: Double) {
        targetFinishSeconds = max(60, targetFinishSeconds + delta)
        rebuild()
    }

    /// Adopt the model's own suggestion.
    func useSuggestedTarget() {
        guard case .loaded(let content) = state, let suggestion = content.suggestion else { return }
        targetFinishSeconds = (suggestion.seconds / 30).rounded() * 30
        rebuild()
    }

    /// Sets a pace-based target on flat ground (seconds per kilometre).
    func setTargetFlatPace(_ paceSecondsPerKm: Double) {
        guard let course else { return }
        guard let plan = RacePlanEngine.plan(course: course, target: .flatPace(paceSecondsPerKm)) else {
            return
        }
        targetFinishSeconds = plan.targetFinishSeconds
        state = .loaded(
            Content(
                plan: plan,
                suggestion: model.flatMap { RacePlanEngine.suggestedFinish(course: course, model: $0) }
            )
        )
    }

    func clear() {
        course = nil
        model = nil
        importError = nil
        state = .noData(reason: .nothingLogged(what: "parkur"))
    }

    // MARK: - Internals

    /// The runner's own critical-speed model, or `nil` when there is not enough to fit one.
    ///
    /// Reuses the endurance screen's own reading of what counts as an effort rather than
    /// restating it, so the two screens can never disagree about the same runs.
    private func criticalSpeedModel() async -> CriticalSpeedModel? {
        let now = nowProvider()
        let start = now.addingTimeInterval(-Double(EnduranceEngine.effortWindowDays) * 86_400)
        guard let workouts = try? await health.fetchWorkouts(
            in: DateInterval(start: start, end: now)
        ) else { return nil }
        let runs = workouts.filter { $0.activity == .running }
        guard !runs.isEmpty else { return nil }
        return EnduranceEngine.fit(efforts: EnduranceViewModel.efforts(from: runs), now: now)
    }
}
