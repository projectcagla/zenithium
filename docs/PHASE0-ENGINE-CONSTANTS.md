# Zenithium — Phase 0 · EngineConstants Value Table

Every magic number in the app, its value, and the spec section it comes from. Phase 3 emits
`Zenithium/Engines/EngineConstants.swift` containing exactly these values, each with a doc
comment citing the section in the right-hand column.

## `EngineConstants.Baseline` — §4

| Symbol | Value | Spec |
|---|---|---|
| `windowDays` | 60 | §4.1 |
| `alpha` | 2.0 / 61.0 = 0.032786885245901641 | §4.1 |
| `sigmaFloorHRV` | 3.0 ms | §4.2.3 |
| `sigmaFloorRestingHR` | 1.5 bpm | §4.2.3 |
| `sigmaFloorTemperature` | 0.15 °C | §4.2.3 |
| `sigmaFloorRespiratory` | 0.30 br/min | §4.2.3 |
| `winsorSigmaMultiple` | 3.0 | §4.2.2 |
| `minSamplesForScore` | 5 | §4.2.4 |
| `fullConfidenceSamples` | 14 | §4.2.4 |
| `minSamplesForSeed` | 3 | §4.2.6 |
| `minSamplesForWinsorization` | 3 | ASSUMPTION BASE-2 |
| `priorHRV` | μ 45.0 ms, σ 18.0 | §4.2.4 |
| `priorRestingHR` | μ 60.0 bpm, σ 7.0 | §4.2.4 |
| `priorRespiratory` | μ 15.0 br/min, σ 2.0 | §4.2.4 |
| `priorTemperature` | μ 0.0 °C, σ 0.35 | §4.2.4 |

## `EngineConstants.Recovery` — §5.1

| Symbol | Value | Spec |
|---|---|---|
| `weightHRV` | 0.40 | §5.1 |
| `weightRestingHR` | 0.25 | §5.1 |
| `weightSleep` | 0.20 | §5.1 |
| `weightTemperature` | 0.10 | §5.1 |
| `weightRespiratory` | 0.05 | §5.1 |
| `zClampRange` | −3.0 … +3.0 | §5.1 |
| `sleepNormCenter` | 70.0 | §5.1 |
| `sleepNormScale` | 15.0 | §5.1 |
| `logisticSlope` | 1.2 | §5.1 |
| `scoreRange` | 1.0 … 100.0 | §5.1 |
| `bandRedUpperBound` | 33 | §5.1 |
| `bandYellowUpperBound` | 66 | §5.1 |
| Renormalized weights, no temperature | 0.444444…, 0.277778…, 0.222222…, 0.055556… — see ASSUMPTION RECOV-1 | §4.3, §11 |

## `EngineConstants.Sleep` — §5.2

| Symbol | Value | Spec |
|---|---|---|
| `defaultBaselineNeedHours` | 8.0 | §5.2 |
| `strainNeedCoefficient` | 0.25 (× strain / 21) | §5.2 |
| `maxDebtContributionHours` | 1.5 | §5.2 |
| `debtDecayPerNight` | 0.25 | §5.2 |
| `debtWindowNights` | 7 | §5.2 |
| `maxNapCreditHours` | 1.0 | §5.2 |
| `minNapSeconds` | 1200 (20 min) | §5.2 |
| `napLookbackDays` | 1 | ASSUMPTION SLEEP-4 |
| `efficiencyFloor` | 0.75 | §5.2 |
| `efficiencySpan` | 0.20 | §5.2 |
| `restorativeTarget` | 0.42 | §5.2 |
| `consistencyToleranceMinutes` | 90.0 | §5.2 |
| `consistencyWindowDays` | 14 | §5.2 |
| `weightDuration` | 0.50 | §5.2 |
| `weightEfficiency` | 0.20 | §5.2 |
| `weightRestorative` | 0.20 | §5.2 |
| `weightConsistency` | 0.10 | §5.2 |
| Renormalized, unstaged | 0.625, 0.25, 0.125 | §5.2 |
| `minValidSleepSeconds` | 7200 (2 h) | §5.6 |
| `maxValidSleepSeconds` | 50400 (14 h) | §5.6 |
| `contiguityToleranceSeconds` | 900 (15 min) | ASSUMPTION SLEEP-2 |
| `nightWindow` | 18:00 prev day … 12:00 today | ASSUMPTION SLEEP-1 |

## `EngineConstants.Strain` — §5.3

| Symbol | Value | Spec |
|---|---|---|
| `scaleMax` | 21.0 | §5.3 |
| `trimpScaleK` | 0.0065 | §5.3 |
| `tanakaIntercept` | 208.0 | §5.3 |
| `tanakaSlope` | 0.7 | §5.3 |
| `assumedAgeYears` | 35 | §5.3 / HRMAX-1 |
| `observedMaxLookbackDays` | 365 | §5.3 |
| `observedMaxPercentile` | 0.995 | ASSUMPTION HRMAX-2 |
| `trimpMale` | b 0.64, c 1.92 | §5.3 |
| `trimpFemaleOrUnspecified` | b 0.86, c 1.67 | §5.3 |
| `maxSegmentSeconds` | 60.0 | §5.3 |
| `maxGapSeconds` | 120.0 | §5.3 / STRAIN-2 |
| `ceilingExponent` | 0.65 | §5.3 |
| `zoneUpperBounds` (%HRR) | 0.20, 0.40, 0.60, 0.80, 0.90, 1.00 | ASSUMPTION ZONE-1 |
| `dayBoundaryFallbackHour` | 4 (local) | ASSUMPTION DAY-1 |
| Calibration anchors | TRIMP 65→7.2 · 135→12.3 · 200→15.3 · 365→19.0 · 500→20.2 | §5.3 |
| Ceiling references | Recovery 33→10.2 · 67→16.2 · 90→19.6 | §5.3 |

## `EngineConstants.Fatigue` — §5.4

| Symbol | Value | Spec |
|---|---|---|
| `baseHalfLifeHours` | 24.0 | §5.4 |
| `sleepModifierIntercept` | 1.35 | §5.4 |
| `sleepModifierSlope` | 0.006 | §5.4 |
| `sleepModifierRange` | 0.75 … 1.35 | §5.4 |
| `massClassLarge` | 1.15 — Quads, Hamstrings, Glutes, Lats, Upper Back, Chest, Lower Back | §5.4 |
| `massClassMedium` | 1.00 — Shoulders, Triceps, Core/Abs, Adductors, Traps | §5.4 |
| `massClassSmall` | 0.85 — Biceps, Forearms, Calves, Neck | §5.4 |
| `strengthLoadDivisor` | 3.0 | §5.4 |
| `sessionLoadRange` | 0 … 100 | §5.4 |
| `fatigueCeiling` | 100.0 | §5.4 |
| `projectionWindowDays` | 14 | ASSUMPTION MUSCLE-3 |
| `rpeRange` | 1 … 10 | ASSUMPTION RPE-1 |

## `EngineConstants.Circadian` — §5.5

| Offset (h after midpoint) | Event | Alertness |
|---|---|---|
| +2.0 | wake inertia end | 55 |
| +4.5 | morning peak | 100 |
| +8.0 | afternoon dip | 62 |
| +11.5 | secondary peak | 88 |
| +15.0 | melatonin onset | 30 |
| +18.5 | sleep trough | 8 |

| Symbol | Value | Spec |
|---|---|---|
| `amplitudeBase` | 0.7 | §5.5 |
| `amplitudeRecoveryCoefficient` | 0.3 | §5.5 |
| `sampleIntervalSeconds` | 300 (288 samples/day) | ASSUMPTION CIRC-2 |
| `interpolation` | monotone cubic Hermite (PCHIP, Fritsch–Carlson) | §5.5 |
| `maxAlertness` | 100.0 (arc must never exceed) | §11 |

## `EngineConstants.Orchestration`

| Symbol | Value | Spec |
|---|---|---|
| `observerDebounceSeconds` | 30.0 | ASSUMPTION BG-2 |
| `backgroundTaskIdentifier` | `com.zenithium.refresh.daily` | ASSUMPTION BG-1 |
| `backgroundEarliestOffsetMinutes` | 30 after wake (fallback 06:00) | ASSUMPTION BG-1 |
| `intradayDownsampleSeconds` | 5.0 | §8 |
| `appGroupIdentifier` | `group.com.projectcagla.zenithra` | §10 / STORE-2 |
| `engineVersion` | 1 | §7 |

## Golden vectors this table must reproduce (§11)

| # | Input | Expected |
|---|---|---|
| 1 | HRV 62 (μ 55, σ 8) · RHR 50 (μ 54, σ 3) · ΔT +0.3 (σ 0.35) · BR 14.2 (μ 14.8, σ 0.8) · Sleep 82 | Z_HRV 0.8750 · Z_RHR 1.3333 · Z_Temp −0.8571 · Z_Resp 0.7500 · SleepNorm 0.8000 · Z_total 0.7951 · Recovery 72.2 (Green) · Ceiling 17.0 |
| 2 | 30 min @ HR 150, RHR 50, HRmax 190, female | x 0.714286 · TRIMP 60.75 · Strain 6.85 |
| 3 | impact 70, medium mass, Sleep 80, t = 24 h | modifier 0.87 · t½ 20.88 h · λ 0.033197 · Fatigue 31.56 · Readiness 68.4 |
| 4 | sleepStart 23:30, duration 7.5 h | Mid 03:15 · peak 07:45 · dip 11:15 · secondary 14:45 · melatonin 18:15 |
| 5 | cold start n = 10 | confidence 0.714 |

All five were verified numerically against the engines as written, together with the five
strain calibration anchors (±0.1), the three ceiling reference points, the §5.2 unstaged
renormalization, EWMA convergence, winsorization damping, PCHIP no-overshoot (max = 100.000
exactly, at the +4.5 h anchor) and C¹ continuity across the 24-hour wrap seam.

## Known specification conflict

§5.6 states the no-temperature weights as `0.4211 / 0.2632 / 0.2105 / 0.0526`. Those are the
surviving weights divided by **0.95**, and they sum to **0.9474**, not 1.0 — which contradicts
§4.3 ("renormalize the surviving weights to sum to 1.0") and §11 ("missing temp → weights sum
to 1.0"). §5.2's own unstaged renormalization (`0.625 / 0.25 / 0.125`) divides by the surviving
sum and does reach 1.0, so the §5.6 figures are an arithmetic slip rather than a different
rule. Zenithium implements §4.3. Recorded as ASSUMPTION RECOV-1.
