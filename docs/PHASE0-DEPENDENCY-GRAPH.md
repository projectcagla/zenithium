# Zenithium — Phase 0 · Module Dependency Graph

The rule (§6): `Views → ViewModels → Orchestration → {Health, Persistence, Engines} → Domain`.
No arrow points backwards. `Engines` depends on `Domain` only — and `Domain` imports nothing
but `Foundation`.

```
              ┌─────────────────────────────────────────────┐
              │                  Views                      │
              │  Today · Strain · Sleep · MuscleMap ·        │
              │  Trends · Bloodwork · Settings · Onboarding  │
              │  + DesignSystem                             │
              └───────────────────┬─────────────────────────┘
                                  │ reads @Observable state, sends intents
                                  ▼
              ┌─────────────────────────────────────────────┐
              │        ViewModels   @MainActor @Observable   │
              │        each owns one ViewState<Value>        │
              └───────────────────┬─────────────────────────┘
                                  │ protocol-injected
                                  ▼
              ┌─────────────────────────────────────────────┐
              │              Orchestration                   │
              │  DailyRecalculationCoordinator (single-flight)│
              │  HealthObservationRelay · DayWindowResolver   │
              │  BackgroundRefreshScheduler                   │
              └───┬──────────────────┬──────────────────┬────┘
                  │                  │                  │
                  ▼                  ▼                  ▼
        ┌──────────────┐   ┌──────────────────┐   ┌──────────────┐
        │    Health    │   │   Persistence    │   │   Engines    │
        │ actor        │   │ @ModelActor      │   │ pure structs │
        │ HealthKit    │   │ SwiftData        │   │ Foundation   │
        │ Service      │   │ ZenithiumStore    │   │ only         │
        └───────┬──────┘   └────────┬─────────┘   └──────┬───────┘
                │                   │                    │
                └───────────────────┼────────────────────┘
                                    ▼
                       ┌────────────────────────┐
                       │        Domain          │
                       │ Sendable value types,  │
                       │ enums, ZenithiumError,  │
                       │ units, Engine IO       │
                       └────────────────────────┘
                                    ▲
                       ┌────────────┴───────────┐
                       │       Support          │
                       │ ZenithiumLog (OSLog)    │  ← leaf, imported by any layer
                       └────────────────────────┘
```

## Import budget per layer

| Layer | Allowed imports |
|---|---|
| `Domain` | `Foundation` |
| `Support` | `Foundation`, `OSLog` |
| `Engines` | `Foundation` (+ `Domain` types — same module, no import needed) |
| `Persistence` | `Foundation`, `SwiftData`, `OSLog` |
| `Health` | `Foundation`, `HealthKit`, `OSLog` |
| `Orchestration` | `Foundation`, `BackgroundTasks`, `OSLog` |
| `ViewModels` | `Foundation`, `Observation`, `OSLog` |
| `Views` | `SwiftUI`, `Charts`, `Foundation` |
| `Widgets` | `SwiftUI`, `WidgetKit`, `Foundation` |
| `Tests` | `Testing`, `Foundation` (+ `@testable import Zenithium`) |

No layer imports `Combine`, `UIKit`, `Network`, or any third-party module.

## Isolation map

| Type | Isolation | Why |
|---|---|---|
| `HealthKitService` | `actor` | Serialises HealthKit query state, anchors and continuations. |
| `HealthKitAnchorStore` | `actor` | Anchor read/write must not race the queries that consume them. |
| `ZenithiumStore` | `@ModelActor` | Every SwiftData write happens off the main actor; returns `Sendable` snapshots only. |
| `DailyRecalculationCoordinator` | `actor` | Owns the single-flight task handle; safe to call concurrently. |
| `HealthObservationRelay` | `actor` | Owns the debounce timer state. |
| `BackgroundRefreshScheduler` | `@MainActor` | `BGTaskScheduler` registration must happen on launch on the main actor. |
| All `*ViewModel` | `@MainActor @Observable` | UI state, mutated only on the main actor. |
| All `Engines.*` | none (pure `static`) | Deterministic, side-effect-free, callable from any isolation. |
| All `Domain.*` | none, `Sendable` | Value types crossing every boundary. |

## Crossing rules

1. No `HKSample`, `HKWorkout`, `HKQuantitySample`, `HKQueryAnchor` or `HKHealthStore`
   reference leaves `Health/`. Mapping to `Sendable` DTOs happens inside the actor
   (`HealthKitMapping.swift`), before any `return`.
2. No `PersistentModel` leaves `Persistence/`. `StoreSnapshots.swift` declares the
   `Sendable` structs that do.
3. Engines never see a `Date()` they did not receive, never see a `Calendar` they did not
   receive, and never see a HealthKit or SwiftData type at all.
4. Views never call an engine. Every number a view renders — including every explanation of
   a number — arrives pre-computed on an engine output type.
