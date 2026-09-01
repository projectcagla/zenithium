# Zenithium — Phase 0 index

Zenithium is an iOS 18+ app that turns Apple Watch HealthKit data into athletic
intelligence, computed 100 % on-device. Zero backend, zero accounts, zero network calls,
zero analytics, zero third-party packages.

Phase 0 is specification only — no code. It fixes every decision the later phases depend on.

| Document | Contents |
|---|---|
| [PHASE0-ASSUMPTIONS.md](PHASE0-ASSUMPTIONS.md) | Assumption Log — 66 decisions with rationale and the one-line reversal for each. |
| [PHASE0-MANIFEST.md](PHASE0-MANIFEST.md) | Every file in the finished app, in emission order, one-line purpose each. |
| [PHASE0-DEPENDENCY-GRAPH.md](PHASE0-DEPENDENCY-GRAPH.md) | Module graph, per-layer import budget, isolation map, boundary-crossing rules. |
| [PHASE0-ENGINE-CONSTANTS.md](PHASE0-ENGINE-CONSTANTS.md) | Every constant, its value, and its spec section. |

## Delivery phases

| Phase | Contents | State |
|---|---|---|
| 0 | Assumptions · manifest · dependency graph · constants | **done** |
| 1 | `Domain/` + `Models/` | **done** |
| 2 | `Health/` | **done** |
| 3 | `Engines/` | **done** |
| 4 | `Persistence/` + `Orchestration/` | **done** |
| 5 | `ViewModels/` | **done** |
| 6 | DesignSystem + Today + Strain | **done** |
| 7 | Remaining views + widgets | **done** |
| 8 | Tests | **done** |
| 9 | Project, plist, entitlements, README | **done** |

## Standing engineering rules

- Swift 6 language mode, strict concurrency complete, zero warnings.
- iOS 18.0, Xcode 16+, first-party frameworks only.
- `actor` for I/O · `@ModelActor` for SwiftData writes · `@MainActor @Observable` for view
  models · pure value types for engines.
- Banned: `ObservableObject`/`@Published`, Combine, `DispatchQueue`, `NSLock`, `!`, `try!`,
  `as!`, `print()`, mutable global singletons, storyboards.
- Engines import `Foundation` only, take `now` and `Calendar` as parameters, and are
  deterministic and unit-testable without HealthKit.
- Zenithium is a fitness and wellness tool, **not a medical device**. It does not diagnose and
  never advises ignoring symptoms.
