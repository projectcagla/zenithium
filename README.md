# Zenithium

An iOS 18 app that turns Apple Watch HealthKit data into athletic intelligence, computed
entirely on device.

No backend. No account. No network entitlement. No analytics. No third-party packages.
Everything lives in HealthKit and in Zenithium's own SwiftData store.

> **Zenithium is a fitness and wellness tool, not a medical device.** It does not diagnose
> anything and cannot tell you whether you are unwell. If you have symptoms or a health
> question, talk to a clinician.

---

## What it answers

| Question | Surface | Output |
|---|---|---|
| How recovered am I? | Today | Recovery 0–100 %, band, driver breakdown |
| How hard should I go? | Strain | Live strain 0.0–21.0 against a target ceiling |
| What can I train? | Muscle Map | Per-muscle readiness across 16 groups |
| When should I do it? | Circadian Arc | Alertness curve with peak, dip and melatonin markers |

Plus sleep detail, 90-day trends, a bloodwork log, and settings.

---

## Building

```sh
open Zenithium.xcodeproj          # the checked-in project
```

Requires Xcode 16 or later. Set a development team in the target's Signing pane; the App
Group `group.com.projectcagla.zenithra` must exist in the provisioning profile for all three
targets — app, widget extension and watch app — or the store and the widget snapshot will
have nowhere to live.

The identifier is written in four places: `AppGroup.identifier` and the three `.entitlements`
files. A mismatch produces no compiler error and no crash, just a container that silently is
not shared, so `Scripts/check-target-sources.py` compares them.

The project is generated from `project.yml`. To regenerate after adding files:

```sh
python3 Scripts/generate-project.py     # no tools required
xcodegen generate                       # or, if you have XcodeGen
```

`project.yml` is the authoritative definition. If the two ever disagree, `project.yml` is
right and the generator is the bug — and this has happened twice, so there is now a check
for it:

```sh
./Scripts/preflight.sh     # everything checkable without a Swift compiler
```

`preflight.sh` runs four things and regenerates the project:

| Check | What it catches |
|---|---|
| `check-target-sources.py` | `project.yml` and the generator disagreeing about what a target compiles, and the App Group identifier drifting between Swift and the three entitlement files |
| `check-symbols.py` | A type used by a target that the target does not compile, a duplicate top-level declaration, an argument label the type does not have, a banned construct, unbalanced braces |
| `check-privacy-manifest.py` | The privacy manifest claiming less than the source does — a networking API, an SPM dependency, or a required-reason API used but undeclared |
| `generate-project.py` | The checked-in `.xcodeproj` going stale against the source tree |

None of them is a compiler. They cover the failures a build finds late, and the ones a build
does not find at all because they only break a target nobody compiled that day.

### Running the tests

```sh
xcodebuild test -scheme Zenithium -destination 'platform=iOS Simulator,name=iPhone 16'
```

118 tests across nine suites, all Swift Testing. Every engine suite runs without HealthKit,
without SwiftData and without a device — `MockHealthProvider` and an in-memory store stand
in for both.

---

## Architecture

```
Views → ViewModels → Orchestration → {Health, Persistence, Engines} → Domain
```

No arrow points backwards. Two files sit outside the graph as leaves that any layer may
read: `EngineConstants` and `MathSupport`, both pure, stateless and Foundation-only.

| Layer | Isolation | Imports |
|---|---|---|
| `Domain` | none, all `Sendable` | Foundation |
| `Engines` | none, pure `static` | Foundation |
| `Health` | `actor` | Foundation, HealthKit |
| `Persistence` | `@ModelActor` | Foundation, SwiftData |
| `Orchestration` | `actor` | Foundation, BackgroundTasks |
| `ViewModels` | `@MainActor @Observable` | Foundation, Observation |
| `Views` | `@MainActor` | SwiftUI, Charts |

Four rules the code is arranged to make structurally true rather than merely observed:

1. **No `HKSample` subclass leaves `Health/`.** Samples, workouts and query anchors are
   mapped to `Sendable` DTOs *inside* the HealthKit callback, before any continuation
   resumes.
2. **No `PersistentModel` leaves `Persistence/`.** The `@ModelActor` returns snapshot
   structs and accepts write structs.
3. **No engine sees a `Date()` or a `Calendar` it was not handed.** Every engine takes
   `now` as a parameter; nothing in `Engines/` calls `Date()` or `Calendar.current`.
4. **No view calls an engine.** Every number a view renders, including every explanation of
   a number, arrives pre-computed on an engine output type.

---

## The engines

All six are pure, deterministic and unit-testable without HealthKit.

| Engine | What it produces |
|---|---|
| `BaselineEngine` | 60-day EWMA per metric, with winsorization, σ floors, seeding and cold-start prior blending |
| `SleepScoreEngine` | 0–100 from duration, efficiency, restorative fraction and consistency |
| `RecoveryEngine` | 0–100 with a per-driver breakdown, shares and plain-language summaries |
| `StrainEngine` | Banister TRIMP integrated over the intraday series, mapped to the 0–21 scale |
| `FatigueEngine` | Per-muscle exponential decay with a sleep-dependent half-life |
| `CircadianEngine` | A monotone cubic (PCHIP) alertness arc in circular 24-hour time |

### Golden vectors

Verified numerically against the algorithms as written, and asserted in the test suite at
±0.05:

| Input | Result |
|---|---|
| HRV 62 (μ 55, σ 8) · RHR 50 (μ 54, σ 3) · ΔT +0.3 (σ 0.35) · BR 14.2 (μ 14.8, σ 0.8) · Sleep 82 | `Z_total` 0.7951 → **72.2** (Green) → ceiling **17.0** |
| 30 min at HR 150, RHR 50, HRmax 190, female | x 0.714286 → TRIMP **60.75** → strain **6.85** |
| Impact 70, medium mass class, Sleep 80, t = 24 h | modifier 0.87 · t½ 20.88 h · λ 0.033197 → fatigue **31.56**, readiness **68.4** |
| sleepStart 23:30, duration 7.5 h | Mid **03:15** → peak 07:45 · dip 11:15 · secondary 14:45 · melatonin 18:15 |

The PCHIP arc reaches exactly 100.000 at its peak anchor and never exceeds it, and the
24-hour wrap seam is C¹-continuous rather than kinking wherever the rendered day begins.

---

## Constants

Every number, with the rule it comes from. Taxonomy values live on the `Domain` type that
owns the taxonomy; formula values live in `EngineConstants`; each has exactly one
definition site.

### Baseline

| Constant | Value |
|---|---|
| EWMA window · α | 60 days · 2/61 = 0.032787 |
| Winsorization | μ ± 3σ, skipped below 3 days |
| σ floors | HRV 3.0 ms · RHR 1.5 bpm · Temp 0.15 °C · BR 0.30 br/min |
| Cold start | no score below 5 days; blended to the prior below 14; `w = n/14` |
| Population priors | HRV 45 (σ 18) · RHR 60 (σ 7) · BR 15 (σ 2) · ΔT 0 (σ 0.35) |

### Recovery

| Constant | Value |
|---|---|
| Weights | HRV 0.40 · RHR 0.25 · Sleep 0.20 · Temp 0.10 · Resp 0.05 |
| z clamp · logistic slope | ±3 · 1.2 |
| Bands | Red 1–33 · Yellow 34–66 · Green 67–100 |
| Ceiling | `21 · (Recovery/100)^0.65` |

### Sleep

| Constant | Value |
|---|---|
| Need | baseline + 0.25·(strain/21) + min(debt, 1.5) − nap credit (≤ 1.0) |
| Component weights | Duration 0.50 · Efficiency 0.20 · Restorative 0.20 · Consistency 0.10 |
| Thresholds | efficiency floor 0.75, span 0.20 · restorative target 0.42 · consistency ±90 min |
| Validity | reject below 2 h or above 14 h |

### Strain

| Constant | Value |
|---|---|
| Scale · k | 21.0 · 0.0065 |
| Banister | male b 0.64, c 1.92 · female/unspecified b 0.86, c 1.67 |
| Segments | Δt clamped to 60 s; gaps over 120 s contribute nothing |
| HRmax | override, else max(99.5th percentile of daily maxima over 365 d, Tanaka 208 − 0.7·age) |
| Zones | %HRR bands 0/20/40/60/80/90/100 |

### Fatigue

| Constant | Value |
|---|---|
| Half-life | `24 h · sleepModifier · massClass` |
| Sleep modifier | `clamp(1.35 − 0.006·SleepScore, 0.75, 1.35)` |
| Mass classes | large 1.15 · medium 1.00 · small 0.85 |
| Strength load | `clamp(Σ(sets · reps · RPE) / 3, 0, 100)` |

### Circadian

| Offset from midpoint | Event | Alertness |
|---|---|---|
| +2.0 | wake inertia end | 55 |
| +4.5 | morning peak | 100 |
| +8.0 | afternoon dip | 62 |
| +11.5 | secondary peak | 88 |
| +15.0 | melatonin onset | 30 |
| +18.5 | sleep trough | 8 |

Amplitude scales by `0.7 + 0.3·(Recovery/100)`. The anchor set is injectable; a
wake-referenced preset ships alongside the default.

---

## Decisions

Every non-obvious choice is recorded in [`docs/PHASE0-ASSUMPTIONS.md`](docs/PHASE0-ASSUMPTIONS.md)
with a rationale and the one-line change that reverses it. Three worth knowing up front:

**The specification contradicts itself on one point, and Zenithium follows the rule rather
than the table.** §5.6 prints the no-temperature weights as 0.4211 / 0.2632 / 0.2105 /
0.0526 — figures that divide by 0.95 and sum to 0.9474. §4.3 and §11 both require the
surviving weights to sum to 1.0, and §5.2's own unstaged renormalization in the same
document divides by the surviving sum and does reach 1.0. Zenithium divides by the surviving
sum, giving 0.4444 / 0.2778 / 0.2222 / 0.0556. Following §5.6 literally would shrink every
score toward the middle by about 5 % on any watch without wrist temperature.
(`RECOV-1`)

**The afternoon dip is anchored where the spec says, and the anchor is injectable.** At a
03:15 midpoint, `Mid + 8.0 h` puts the dip at 11:15 — earlier than the post-lunch dip in the
literature. The specification flags this itself. The default matches it; `CircadianAnchors`
makes re-anchoring a one-line change with no engine edit. (`CIRC-1`)

**Sensor artefacts are rejected, not clamped.** A 900 ms HRV reading is a fault rather than
an extreme day, and a clamped fault still drags the baseline. Values outside a metric's
plausible range never reach winsorization. (`BASE-1`)

---

## Safety and privacy

- Not a medical device; no diagnosis, and never advice to ignore symptoms.
- Low recovery is directive about *training*, never about health status. All health-adjacent
  copy lives in one auditable file, `Domain/SafetyCopy.swift`.
- Bloodwork shows reference ranges and trends only. The range bar is monochrome and the
  marker dot is white wherever it sits — colouring by position would be an interpretation.
- No calorie targets, no weight goals, no restriction prompts anywhere.
- No network entitlement, and CloudKit is explicitly disabled on every `ModelConfiguration`
  rather than left at its default.

---

## Repository

```
Zenithium/
├── App/              entry point, root view, composition root
├── Support/          OSLog vendor, App Group identity
├── Domain/           Sendable value types, enums, ZenithiumError, engine IO
├── Models/           SwiftData @Model types, SchemaV1, migration plan
├── Health/           HealthKit actor, DTO mapping, seeded mock provider
├── Engines/          pure math, Foundation only
├── Persistence/      container factory, @ModelActor store, repositories
├── Orchestration/    recalculation pipeline, observation relay, background scheduler
├── ViewModels/       @MainActor @Observable, one per screen
└── Views/            design system + seven feature folders
ZenithiumWidgets/      three widgets over the App-Group snapshot
ZenithiumTests/        118 Swift Testing tests
docs/                 assumptions, manifest, dependency graph, constants
```
