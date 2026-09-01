# Zenithium — Phase 0 · File Manifest

Every file the finished app contains, in emission order. A file may only reference symbols
declared in a file above it. `#` column = the phase in which the file is emitted.

## Phase 1 — `Domain/` + `Models/`

| # | Path | Purpose |
|---|---|---|
| 1 | `Zenithium/Support/AppGroup.swift` | The shared App Group identifier, container URL, defaults suite, store URL and widget snapshot URL (ASSUMPTION STORE-2, WIDGET-1). |
| 1 | `Zenithium/Support/ZenithiumLog.swift` | OSLog subsystem + the six categories; private-by-default biometric logging helpers. |
| 1 | `Zenithium/Domain/HealthDataKind.swift` | The Sendable identity of every HealthKit category the app reads, so no other layer imports HealthKit. |
| 1 | `Zenithium/Domain/ZenithiumError.swift` | Typed `throws` error enum: authorization, HealthKit query, store, engine-input, background-task cases, each with a recovery suggestion. |
| 1 | `Zenithium/Domain/Units.swift` | Canonical unit wrappers (ms, bpm, °C, br/min, seconds) and the HealthKit-boundary conversion helpers. |
| 1 | `Zenithium/Domain/MetricKind.swift` | The four baselined metrics (`hrv`, `restingHR`, `wristTemperature`, `respiratoryRate`) with σ floors, priors and display metadata. |
| 1 | `Zenithium/Domain/MuscleGroup.swift` | The 16 groups in fixed enum order + `MassClass` and its half-life multiplier. |
| 1 | `Zenithium/Domain/RecoveryBand.swift` | Red/Yellow/Green bands, thresholds, glyph + label (no colour-only encoding). |
| 1 | `Zenithium/Domain/DataQuality.swift` | `.good` / `.partial` / `.suspect` + the reasons that produce each. |
| 1 | `Zenithium/Domain/SleepStage.swift` | Stage enum, `isAsleep`, and the `HKCategoryValueSleepAnalysis` raw-value mapping table. |
| 1 | `Zenithium/Domain/DayBoundary.swift` | `.wakeAnchored` / `.midnight` and the day-window resolver contract. |
| 1 | `Zenithium/Domain/BiologicalSexValue.swift` | Sendable sex enum + the sex-specific TRIMP constants (b, c). |
| 1 | `Zenithium/Domain/UserCharacteristics.swift` | Age, sex, date of birth, unit preference — the Sendable projection of `HKCharacteristicType`. |
| 1 | `Zenithium/Domain/HeartRateSample.swift` | `Sendable` intraday HR DTO (timestamp, bpm, sourceBundleID). |
| 1 | `Zenithium/Domain/SleepSegment.swift` | `Sendable` sleep interval DTO (interval, stage, sourceBundleID, timeZone). |
| 1 | `Zenithium/Domain/WorkoutActivity.swift` | The 30 domain activity types the involvement matrix covers (ASSUMPTION MUSCLE-1). |
| 1 | `Zenithium/Domain/WorkoutSummary.swift` | `Sendable` workout DTO — activity type, interval, energy, distance, average HR. Never an `HKWorkout`. |
| 1 | `Zenithium/Domain/OvernightData.swift` | One night's ingest bundle: HRV, RHR, wrist temp, respiratory rate, sleep segments, quality flags. |
| 1 | `Zenithium/Domain/BaselineSeries.swift` | N days of daily aggregates per metric, with per-day validity flags. |
| 1 | `Zenithium/Domain/HealthChangeEvent.swift` | What changed and when — drives the observation stream. |
| 1 | `Zenithium/Domain/HealthAuthorizationState.swift` | `.notDetermined` / `.authorized` / `.denied` / `.unavailable` + per-type detail. |
| 1 | `Zenithium/Domain/BloodMarkerKind.swift` | ApoB, hs-CRP, Vitamin D, Ferritin, Fasting Glucose + `.custom(String)`, with default unit and reference/optimal ranges. |
| 1 | `Zenithium/Domain/MovementPattern.swift` | Push / Pull / Squat / Hinge / Carry / Isolation(MuscleGroup) presets. The involvement rows themselves live in `Engines`. |
| 1 | `Zenithium/Domain/StrengthEntry.swift` | One logged exercise: name, sets, reps, RPE, and its `sets · reps · RPE` volume load (ASSUMPTION RPE-1). |
| 1 | `Zenithium/Domain/EngineIO/BaselineIO.swift` | `BaselineSnapshot` (μ, V, σ, n, lastUpdated), `BaselineUpdate` (raw, clamped, winsorized flag). |
| 1 | `Zenithium/Domain/EngineIO/SleepIO.swift` | `SleepInput` / `SleepOutput` incl. component scores, dropped components, renormalized weights. |
| 1 | `Zenithium/Domain/EngineIO/RecoveryIO.swift` | `RecoveryInput` / `RecoveryOutput` incl. `DriverContribution` (metric, z, weight, contribution, share) and confidence. |
| 1 | `Zenithium/Domain/EngineIO/StrainIO.swift` | `StrainInput` / `StrainOutput` incl. TRIMP, zone seconds, ceiling, anchor for monotonic recompute. |
| 1 | `Zenithium/Domain/EngineIO/FatigueIO.swift` | `FatigueInput` (sessions, sleep score, now), `MuscleSessionImpact`, `MuscleReadiness` (fatigue, readiness, top contributor). |
| 1 | `Zenithium/Domain/EngineIO/CircadianIO.swift` | `CircadianAnchors`, `CircadianInput`, `CircadianArc` (samples, marker timestamps, amplitude scale). |
| 1 | `Zenithium/Domain/SafetyCopy.swift` | Every user-facing training-directive / disclaimer string (§12), in one auditable table. |
| 1 | `Zenithium/Models/UserProfile.swift` | `@Model` — birth date, sex, HRmax override, baseline sleep need, unit preference, onboarding state. |
| 1 | `Zenithium/Models/BaselineState.swift` | `@Model` — persisted EWMA μ / V / n / lastUpdated per `MetricKind` (unique). |
| 1 | `Zenithium/Models/BiometricDayRecord.swift` | `@Model` — the full daily record listed in §7, unique on `dayStart`. |
| 1 | `Zenithium/Models/MuscleFatigueSnapshot.swift` | `@Model` — cached per-muscle fatigue at a timestamp, unique on `(computedAt, engineVersion)`. |
| 1 | `Zenithium/Models/StrengthSessionLog.swift` | `@Model` — manual strength session: date, pattern, entries (sets/reps/RPE), derived session load. |
| 1 | `Zenithium/Models/BloodMarker.swift` | `@Model` — marker, value, unit, ref/optimal ranges, drawnAt, note. |
| 1 | `Zenithium/Models/SchemaV1.swift` | `VersionedSchema` listing all six model types. |
| 1 | `Zenithium/Models/ZenithiumMigrationPlan.swift` | `SchemaMigrationPlan` with `SchemaV1` only and empty stages. |

## Phase 2 — `Health/`

| # | Path | Purpose |
|---|---|---|
| 2 | `Zenithium/Health/HealthKitTypeCatalog.swift` | Every `HKObjectType` the app reads, its unit, its aggregation option, the `HKWorkoutActivityType` → `WorkoutActivity` map, and the `HealthQueryTuning` values. |
| 2 | `Zenithium/Health/HealthDataProviding.swift` | The `Sendable` protocol from §8 — the only Health surface any other layer may see. |
| 2 | `Zenithium/Health/HealthKitMapping.swift` | `HKSample` → Sendable DTO mappers, unit conversions, HR downsampling to ≤ 1 sample / 5 s. Called only from inside the actor. |
| 2 | `Zenithium/Health/HealthKitAnchorStore.swift` | Persisted `HKQueryAnchor` per type in the App Group, with deletion-aware bookkeeping. |
| 2 | `Zenithium/Health/HealthKitService.swift` | The `actor` — authorization, statistics collection, anchored queries, observer queries, background delivery, `AsyncStream` of changes, cancellation-safe continuations. |
| 2 | `Zenithium/Health/MockHealthProvider.swift` | Deterministic seeded 90-day generator (seeded LCG, no `Foundation.random`) implementing the same protocol for previews and tests. |

## Phase 3 — `Engines/`

| # | Path | Purpose |
|---|---|---|
| 3 | `Zenithium/Engines/EngineConstants.swift` | Every magic number in the app, each with a doc comment citing its spec section. |
| 3 | `Zenithium/Engines/MathSupport.swift` | `clamp`, `logistic`, `winsorize`, circular mean, percentile, safe division. Foundation only. |
| 3 | `Zenithium/Engines/MonotoneCubicInterpolator.swift` | PCHIP (Fritsch–Carlson) — provably no overshoot; used by the circadian arc. |
| 3 | `Zenithium/Engines/BaselineEngine.swift` | EWMA μ/V update with winsorization, σ floors, seeding, gap handling, prior blending. |
| 3 | `Zenithium/Engines/SleepScoreEngine.swift` | Need model, four components, weight renormalization when stages are absent. |
| 3 | `Zenithium/Engines/RecoveryEngine.swift` | Z-scores, clamping, weight renormalization, logistic map, driver breakdown, confidence. |
| 3 | `Zenithium/Engines/StrainEngine.swift` | HRmax resolution, HRR, Banister TRIMP with gap rules, Whoop-scale mapping, zone seconds, ceiling, monotonic anchor. |
| 3 | `Zenithium/Engines/MuscleInvolvementMatrix.swift` | Activity → 16-muscle involvement rows (24 activity types + movement-pattern presets). |
| 3 | `Zenithium/Engines/FatigueEngine.swift` | Session impacts, per-muscle λ from half-life × sleep modifier × mass class, exponential superposition. |
| 3 | `Zenithium/Engines/CircadianEngine.swift` | Midpoint resolution, anchor placement in circular time, PCHIP arc, recovery amplitude scaling, marker extraction. |

## Phase 4 — `Persistence/` + `Orchestration/`

| # | Path | Purpose |
|---|---|---|
| 4 | `Zenithium/Persistence/StoreSnapshots.swift` | The `Sendable` structs the `@ModelActor` returns — no `PersistentModel` ever crosses the boundary. |
| 4 | `Zenithium/Persistence/ModelContainerFactory.swift` | Schema + `ModelConfiguration` in the App Group; in-memory variant for tests and previews. |
| 4 | `Zenithium/Persistence/ZenithiumStore.swift` | The `@ModelActor` — all reads and writes, upserts keyed on natural keys, `engineVersion` backfill detection. |
| 4 | `Zenithium/Persistence/Repositories.swift` | Narrow protocols (`BiometricReading`, `BaselineWriting`, …) the coordinator and view models depend on, with `ZenithiumStore` conformances. |
| 4 | `Zenithium/Persistence/WidgetSnapshot.swift` | The Codable payload shared through the App Group plus its atomic reader/writer. Member of **both** targets, which is why it lives here rather than in the widget folder (ASSUMPTION WIDGET-1). |
| 4 | `Zenithium/Orchestration/DayWindowResolver.swift` | Wake-anchored day windows, DST-safe, timezone-of-record aware. |
| 4 | `Zenithium/Orchestration/DailyRecalculationCoordinator.swift` | Single-flight, cancellable, idempotent pipeline: fetch → engines → store → widget snapshot → notify. |
| 4 | `Zenithium/Orchestration/HealthObservationRelay.swift` | Debounced consumer of the health change stream. |
| 4 | `Zenithium/Orchestration/BackgroundRefreshScheduler.swift` | `BGAppRefreshTask` registration, scheduling and expiry handling. |
| 4 | `Zenithium/App/AppDependencies.swift` | The composition root — builds the container, store, health provider, coordinator, and hands protocols to view models. |

## Phase 5 — `ViewModels/`

| # | Path | Purpose |
|---|---|---|
| 5 | `Zenithium/ViewModels/ViewState.swift` | The generic `ViewState<Value>` enum: `.calibrating(progress:)`, `.needsAuthorization`, `.noData(reason:)`, `.loaded(_)`, `.failed(_)`. |
| 5 | `Zenithium/ViewModels/TodayViewModel.swift` | Recovery, drivers, ceiling, circadian summary, calibration progress. |
| 5 | `Zenithium/ViewModels/StrainViewModel.swift` | Live strain, ceiling, zone bars, workout list. |
| 5 | `Zenithium/ViewModels/SleepViewModel.swift` | Score, components, stage breakdown, debt, consistency. |
| 5 | `Zenithium/ViewModels/MuscleMapViewModel.swift` | 16-muscle readiness, per-muscle detail, strength logging. |
| 5 | `Zenithium/ViewModels/TrendsViewModel.swift` | 7/30/90-day series for recovery, strain, sleep, HRV, RHR. |
| 5 | `Zenithium/ViewModels/BloodworkViewModel.swift` | Marker list, per-marker history, entry validation. |
| 5 | `Zenithium/ViewModels/SettingsViewModel.swift` | Profile, sleep need, HRmax override, day boundary, units, privacy and disclaimer surfaces. |
| 5 | `Zenithium/ViewModels/OnboardingViewModel.swift` | Permission request flow, profile capture, disclaimer acknowledgement. |

## Phase 6 — Design system + Today + Strain

| # | Path | Purpose |
|---|---|---|
| 6 | `Zenithium/Views/DesignSystem/ZenithiumColor.swift` | OLED palette, band colours, contrast-checked pairs. |
| 6 | `Zenithium/Views/DesignSystem/ZenithiumFont.swift` | SF Pro Rounded scale with `.monospacedDigit()` numerals, Dynamic Type to AX5. |
| 6 | `Zenithium/Views/DesignSystem/RingGauge.swift` | `Canvas` + `AngularGradient` ring, 18 pt rounded stroke, spring animation, band-transition `.sensoryFeedback`, full accessibility. |
| 6 | `Zenithium/Views/DesignSystem/BandChip.swift` | Colour + glyph + text band label. |
| 6 | `Zenithium/Views/DesignSystem/MetricTile.swift` | Label / value / delta tile with accessibility value. |
| 6 | `Zenithium/Views/DesignSystem/SectionCard.swift` | Surface card with hairline border. |
| 6 | `Zenithium/Views/DesignSystem/StateViews.swift` | `CalibratingView`, `AuthorizationGateView` (deep link to Settings), `NoDataView`, `ErrorStateView`. |
| 6 | `Zenithium/Views/Today/TodayView.swift` | Recovery ring, band, drivers, ceiling, circadian strip, safety copy. |
| 6 | `Zenithium/Views/Today/DriverBreakdownView.swift` | Per-driver bars with share-of-total and plain-language top ± driver. |
| 6 | `Zenithium/Views/Strain/StrainView.swift` | Live strain ring vs ceiling, day progress, workout list. |
| 6 | `Zenithium/Views/Strain/ZoneBarsView.swift` | Six %HRR zone bars with accessible durations. |
| 6 | `Zenithium/Views/Circadian/CircadianArcView.swift` | The alertness arc with its six named markers. Emitted in Phase 6 rather than 7 because Today embeds it, and a phase that cannot compile on its own is not a phase. |

## Phase 7 — Remaining views + widgets

| # | Path | Purpose |
|---|---|---|
| 7 | `Zenithium/Views/Sleep/SleepView.swift` | Score, need vs actual, components, debt. |
| 7 | `Zenithium/Views/Sleep/SleepStageBarView.swift` | Stacked stage timeline with accessibility descriptor. |
| 7 | `Zenithium/Views/Muscle/BodyGeometry.swift` | Vector paths for the 16 regions, anterior and posterior. |
| 7 | `Zenithium/Views/Muscle/MuscleMapView.swift` | Anterior/posterior map, per-region readiness fill, tap → detail. |
| 7 | `Zenithium/Views/Muscle/MuscleDetailView.swift` | One muscle: readiness, decay curve, contributing sessions. |
| 7 | `Zenithium/Views/Muscle/StrengthSessionLoggerView.swift` | Pattern picker, sets/reps/RPE entry, live session-load preview. |
| 7 | `Zenithium/Views/Trends/TrendsView.swift` | 7/30/90 segmented range, metric picker. |
| 7 | `Zenithium/Views/Trends/TrendChart.swift` | Scrubbable Swift Chart with `.accessibilityChartDescriptor`. |
| 7 | `Zenithium/Views/Bloodwork/BloodworkView.swift` | Marker list with range position, no interpretation. |
| 7 | `Zenithium/Views/Bloodwork/BloodMarkerDetailView.swift` | Per-marker history chart and reference band. |
| 7 | `Zenithium/Views/Bloodwork/BloodMarkerEditorView.swift` | Add / edit a draw, unit-aware entry. |
| 7 | `Zenithium/Views/Settings/SettingsView.swift` | Profile, sleep need, HRmax, day boundary, units, links. |
| 7 | `Zenithium/Views/Settings/PrivacyView.swift` | On-device / no account / no network statement. |
| 7 | `Zenithium/Views/Settings/DisclaimerView.swift` | Not-a-medical-device copy. |
| 7 | `Zenithium/Views/Onboarding/OnboardingView.swift` | Disclaimer → permissions → profile → done. |
| 7 | `Zenithium/App/RootView.swift` | Tab shell, onboarding gate, authorization gate. |
| 7 | `Zenithium/App/ZenithiumApp.swift` | `@main`, container injection, background task registration, scene phase handling. |
| 7 | `ZenithiumWidgets/ZenithiumTimelineProvider.swift` | Timeline provider (placeholder / snapshot / timeline). |
| 7 | `ZenithiumWidgets/RecoveryCircularWidget.swift` | Lock Screen `.accessoryCircular`. |
| 7 | `ZenithiumWidgets/RecoveryStrainWidget.swift` | Home Screen small — recovery + strain vs ceiling. |
| 7 | `ZenithiumWidgets/ThreeDayTrendWidget.swift` | Home Screen medium — three-day trend. |
| 7 | `ZenithiumWidgets/ZenithiumWidgetBundle.swift` | `@main` widget bundle. |

## Phase 8 — `Tests/`

| # | Path | Purpose |
|---|---|---|
| 8 | `ZenithiumTests/TestSupport.swift` | `expectClose`, fixed `Calendar`/`TimeZone`, deterministic fixtures. |
| 8 | `ZenithiumTests/BaselineEngineTests.swift` | EWMA convergence, winsorization, σ floors, seeding, gaps, prior blending, cold start (n = 3 → no score, n = 10 → 0.714). |
| 8 | `ZenithiumTests/RecoveryEngineTests.swift` | Golden vector 1, z clamping, missing-temp renormalization to 1.0, HRV/RHR suppression rule. |
| 8 | `ZenithiumTests/SleepScoreEngineTests.swift` | Component maths, unstaged renormalization, debt/nap credit, DST-crossing night. |
| 8 | `ZenithiumTests/StrainEngineTests.swift` | Golden vector 2, the five calibration anchors ±0.1, gap rules, monotonicity, ceiling references. |
| 8 | `ZenithiumTests/FatigueEngineTests.swift` | Golden vector 3, superposition, mass-class half-lives, 14-day window truncation. |
| 8 | `ZenithiumTests/CircadianEngineTests.swift` | Golden vector 4, PCHIP no-overshoot (≤ 100 everywhere), circular wrap continuity, amplitude scaling. |
| 8 | `ZenithiumTests/InvolvementMatrixTests.swift` | Every row ∈ [0, 1], normative rows exact, strength types contribute no muscle impact. |
| 8 | `ZenithiumTests/PipelineIntegrationTests.swift` | `MockHealthProvider` → coordinator → in-memory store, end to end, idempotent on re-run. |

## Phase 9 — Project, plist, entitlements, docs

| # | Path | Purpose |
|---|---|---|
| 9 | `Zenithium/Info.plist` | Health usage descriptions, `BGTaskSchedulerPermittedIdentifiers`, scene config. |
| 9 | `Zenithium/Zenithium.entitlements` | HealthKit, HealthKit background delivery, App Group. |
| 9 | `ZenithiumWidgets/Info.plist` | Widget extension point. |
| 9 | `ZenithiumWidgets/ZenithiumWidgets.entitlements` | App Group. |
| 9 | `project.yml` | XcodeGen spec: two targets + test target, Swift 6 strict concurrency, iOS 18.0. |
| 9 | `Zenithium.xcodeproj/project.pbxproj` | Checked-in project so the repo opens without any tool. |
| 9 | `README.md` | Architecture notes, constants table, how to build, spec traceability. |
