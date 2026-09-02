//
//  VitalsViewModel.swift
//  Zenithium
//
//  The vitals screen. Faz 11, Faz 28.
//

import Foundation
import Observation

@MainActor
@Observable
final class VitalsViewModel {

    struct Content: Sendable, Equatable {

        /// Every sign that returned data, grouped and ordered.
        let readings: [VitalReading]

        /// This morning's multivariate deviation, when it is worth surfacing.
        let deviation: DeviationScore

        /// The sentence for that deviation, or `nil` when the morning is ordinary.
        let deviationSummary: String?

        /// Signs that returned nothing, so the screen can say what is missing rather than
        /// silently omitting it. A user who wonders where VO₂max went deserves an answer.
        let missing: [VitalSign]

        /// The long-horizon composite (Faz 29), when enough pillars had data.
        let longevity: LongevityScore?

        /// Daylight context and its effect on the circadian curve's confidence (Faz 30).
        let daylight: DaylightContext

        /// Rolling sleep owed, and the weekly drift of the sleep midpoint. Yol haritası v4, C4.
        let sleepDebt: SleepDebtLedger
        let socialJetlag: SocialJetlag?

        /// Where this VO₂max sits against published norms, when age and sex are known.
        /// Context, never a verdict (§12). Yol haritası v4, C11.
        let vo2MaxNorm: NormPosition?

        /// A recent time-zone change, when there was one.
        let timeZoneShift: TimeZoneShift?

        var groups: [(category: VitalCategory, readings: [VitalReading])] {
            VitalCategory.allCases
                .sorted { $0.order < $1.order }
                .compactMap { category in
                    let rows = readings.filter { $0.sign.category == category }
                    return rows.isEmpty ? nil : (category, rows)
                }
        }
    }

    private(set) var state: ViewState<Content> = .loading

    private let vitals: any VitalsProviding
    private let records: any BiometricDayRepository

    /// Read only for the sleep need. Optional so previews and tests can leave it out.
    private let profile: (any ProfileRepository)?

    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        vitals: any VitalsProviding,
        records: any BiometricDayRepository,
        profile: (any ProfileRepository)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.vitals = vitals
        self.records = records
        self.profile = profile
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    /// What reading one sign produced.
    ///
    /// A task group's result has to be `Sendable`, and `any Error` is not — so the two
    /// outcomes the screen actually distinguishes are spelled out here instead of being
    /// carried as an opaque error.
    private enum VitalReadOutcome: Sendable {

        /// The sign's daily values, possibly empty.
        case samples([VitalSample])

        /// HealthKit refused at a level that makes every other sign moot.
        case blocked(ZenithiumError)

        /// This sign failed on its own. The rest of the screen is unaffected.
        case unreadable
    }

    /// Where the latest VO₂max sits against the published reference band.
    ///
    /// `nil` whenever any input is missing — no reading, no birth date, no recorded sex, or
    /// an age outside the table. Each of those is a reason not to compare rather than a
    /// reason to guess. Yol haritası v4, C11.
    ///
    /// Also `nil` while `ReferenceNorms.isPublicationVerified` is `false`. ASSUMPTION NORM-1
    /// was checked in Adım 6 and did not hold: two of the four cells that could be checked
    /// against the cited paper are wrong. Showing a percentile from a table in that state
    /// would give the number an authority it has not earned, and this is the layer where
    /// that decision belongs — the lookup itself is arithmetic and stays correct.
    nonisolated static func vo2MaxNorm(
        readings: [VitalReading],
        characteristics: UserCharacteristics?,
        now: Date,
        calendar: Calendar
    ) -> NormPosition? {
        guard ReferenceNorms.isPublicationVerified else { return nil }
        guard let characteristics,
              let value = readings.first(where: { $0.sign == .vo2Max })?.latest?.value else {
            return nil
        }
        return ReferenceNorms.vo2MaxPosition(
            value: value,
            age: characteristics.age(at: now, calendar: calendar),
            biologicalSex: characteristics.biologicalSex
        )
    }

    func onAppear() async {
        if state.isLoading { await load() }
    }

    func load() async {
        let now = nowProvider()
        let calendar = calendarProvider()

        // Eighteen signs, read a few at a time rather than one after another.
        //
        // This used to be a sequential loop, defended on the grounds that one failing sign
        // must not take the rest of the screen with it. That reason was right and the remedy
        // was too expensive: each child below reports its own outcome, so a sign that throws
        // is still only that sign's problem, and the screen no longer waits out eighteen
        // round trips to draw. Yol haritası v4, A3.
        //
        // The ceiling is a property of HealthKit rather than of this screen, so it lives in
        // `ZenithiumConcurrency` alongside the other two fan-outs that share it.
        let signs: [VitalSign] = VitalSign.allCases
        let results: [VitalReadOutcome] = await withBoundedTaskGroup(
            over: signs,
            limit: ZenithiumConcurrency.maximumConcurrentHealthReads
        ) { [vitals] (sign: VitalSign) -> VitalReadOutcome in
            do {
                let fetched = try await vitals.fetchVitalSamples(
                    sign: sign,
                    days: sign.trendWindowDays,
                    now: now,
                    calendar: calendar
                )
                return .samples(fetched)
            } catch let error as ZenithiumError where error.blocksPartialResults {
                return .blocked(error)
            } catch is CancellationError {
                // Structured cancellation arrives as `CancellationError`, not as
                // `ZenithiumError.cancelled`, so without this it fell through to `.unreadable`
                // and an abandoned load still drew a screen — one short of eighteen signs.
                return .blocked(.cancelled)
            } catch {
                return .unreadable
            }
        }

        var samples: [VitalSample] = []
        var missing: [VitalSign] = []

        // One answer per sign, in `VitalSign` order rather than in the order the queries
        // happened to finish, so the screen is laid out the same way on every launch. Pairing
        // positionally rather than through a dictionary drops a lookup that could not miss
        // and a `uniqueKeysWithValues` trap that only `allCases` being distinct kept unreached.
        for (sign, outcome) in zip(signs, results) {
            switch outcome {
            case .samples(let fetched):
                if fetched.isEmpty {
                    missing.append(sign)
                } else {
                    samples.append(contentsOf: fetched)
                }
            case .blocked(let error):
                // An error that withholds data is the whole screen's problem; one unreadable
                // sign is only that sign's. Cancellation lands here too and maps to `nil`,
                // which leaves the screen exactly as the abandoned load found it.
                if let mapped = ViewState<Content>.from(error) {
                    state = mapped
                }
                return
            case .unreadable:
                missing.append(sign)
            }
        }

        guard !samples.isEmpty else {
            state = .noData(reason: .nothingLogged(what: "sağlık ölçümü"))
            return
        }

        let readings = VitalsEngine.readings(from: samples)
        let deviation = VitalsEngine.deviationScore(from: readings)

        // The composite and the environment context both need the day records. A failure
        // there costs those two cards and nothing else, so it is a silent optional.
        // The person's own sleep need, when a profile is available. Falling back to the
        // population default rather than skipping the ledger: a debt measured against eight
        // hours is still worth more than no debt at all.
        var sleepNeedHours = EngineConstants.Sleep.defaultBaselineNeedHours
        var characteristics: UserCharacteristics?
        if let profile, let snapshot = try? await profile.profile() {
            sleepNeedHours = snapshot.baselineSleepNeedHours
            characteristics = snapshot.characteristics
        }

        let history = (try? await records.dayRecords(
            from: now.addingTimeInterval(-Double(LongevityEngine.windowDays) * 86_400),
            through: now
        )) ?? []

        state = .loaded(
            Content(
                readings: readings,
                deviation: deviation,
                deviationSummary: VitalsEngine.deviationSummary(for: deviation),
                missing: missing,
                longevity: LongevityEngine.score(vitals: readings, days: history, now: now),
                daylight: EnvironmentEngine.daylightContext(from: samples),
                sleepDebt: SleepDebtEngine.ledger(
                    days: history,
                    needHours: sleepNeedHours,
                    now: now,
                    calendar: calendar
                ),
                socialJetlag: SleepDebtEngine.socialJetlag(
                    days: history,
                    now: now,
                    calendar: calendar
                ),
                vo2MaxNorm: Self.vo2MaxNorm(
                    readings: readings,
                    characteristics: characteristics,
                    now: now,
                    calendar: calendar
                ),
                timeZoneShift: {
                    guard let shift = EnvironmentEngine.recentTimeZoneShift(in: history),
                          EnvironmentEngine.isAdapting(to: shift, on: now, calendar: calendar) else {
                        return nil
                    }
                    return shift
                }()
            )
        )
    }
}
