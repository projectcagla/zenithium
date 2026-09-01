# Zenithium

An iOS 18 application that transforms raw Apple Watch HealthKit streams into deterministic athletic intelligence, computed entirely on device.

Zero backend servers. Zero user accounts. Zero network entitlements. Zero telemetry. Zero third-party dependencies. All biometrics and state reside exclusively within HealthKit and an App-Group shared SwiftData store.

> **Zenithium is an athletic measurement instrument, not a medical device.** It does not provide medical diagnoses, clinical assessments, or treatment advice. Consult a qualified clinician for health concerns.

---

## The Four Daily Questions

Zenithium structures its presentation around a strict epistemic hierarchy:

| Hierarchy | Question | Presentation Surface | Output |
|---|---|---|---|
| **1. Decision** | What should I do today? | Today Hero | Deterministic action (`Push`, `Maintain`, `Recover`, `Calibrate`) and target physiological strain ceiling |
| **2. Evidence** | Why this decision? | Evidence Layer | Dominant biometric drivers, contribution shares, and step-by-step mathematical trace |
| **3. Confidence** | How confident is the system? | Epistemic Badge | Mathematical confidence factor (0.00–1.00) based on baseline maturity and signal quality |
| **4. Boundaries** | What is unknown? | Disclosure Notes | Sensor voids, missing nocturnal parameters, or cold-start fallback intervals |

---

## Architectural Principles

1. **Deterministic Calculation Over Heuristics**  
   Decision logic, strain ceilings, recovery scores, and fatigue projections are computed by 29 pure mathematical engines. On-device models generate linguistic summaries only; they never calculate numbers or alter decisions.
2. **Zero External Dependencies**  
   Built exclusively with Apple system frameworks (`SwiftUI`, `HealthKit`, `SwiftData`, `Observation`, `ActivityKit`, `WidgetKit`). Zero SPM packages, zero CocoaPods, zero dynamic libraries.
3. **Strict Unidirectional Dependency Graph**  
   `Views` → `ViewModels` → `Orchestration` → `{Health, Persistence, Engines}` → `Domain`.  
   No backward references. Engine and Domain layers are completely free of UI and persistence dependencies.
4. **Strict Concurrency Enforcement**  
   Compiled with Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) with warnings treated as errors. All HealthKit transfers map to `Sendable` value types before crossing actor isolation boundaries.

---

## Engine Catalog

29 pure, deterministic calculation engines implemented as Foundation-only stateless enums with `static func` entry points:

| Engine | Primary Function | Theoretical Basis |
|---|---|---|
| `BaselineEngine` | 60-day EWMA baseline calculation with σ floors and winsorization | Exponentially weighted moving average, dynamic prior blending |
| `RecoveryEngine` | 0–100 % daily recovery synthesis with driver attribution | Weighted standardized z-scores with logistic mapping |
| `StrainEngine` | Intraday Banister TRIMP integration mapped to 0.0–21.0 scale | Exponential heart rate reserve integration ($\Delta t \le 60\text{s}$) |
| `SleepScoreEngine` | 0–100 sleep quality score across duration, efficiency, restorative stages | Multi-component restorative sleep model |
| `SleepDebtEngine` | Trailing sleep shortfall accumulation and decay | 14-day exponential debt window with nap credits |
| `DecisionEngine` | Deterministic athletic action synthesis and limitation auditing | Epistemic evidence graph with strict confidence bounds |
| `FatigueEngine` | Per-muscle exponential recovery decay across 16 groups | Sleep-dependent biological half-life modeling |
| `CircadianEngine` | 24-hour alertness curve anchored to nocturnal sleep midpoint | Monotone cubic Hermite interpolation (PCHIP) |
| `TrainingLoadEngine` | Acute-to-Chronic Workload Ratio (ACWR) and Foster monotony | 7-day acute vs. 28-day chronic exponential load tracking |
| `EnduranceEngine` | Critical speed, tempo zones, and race finish prediction | Two-parameter hyperbolic critical speed model |
| `StrengthEngine` | Estimated 1RM and muscle volume tracking | Brzycki / Epley formulas with fatigue dampening |
| `HybridEngine` | Concurrent endurance and strength interference modeling | Molecular signaling interference window estimation |
| `VitalsEngine` | Multi-metric baseline deviation and biological age trend | Multi-system biometric deviation scoring |
| `LongevityEngine` | Cardio-respiratory fitness and autonomic resilience trajectory | Longitudinal biomarker regression |
| `DataQualityEngine` | Multi-sensor completeness and nocturnal wear auditing | Sensor presence, sample density, and timing validation |
| `CircadianWindowEngine` | Optimal physical and cognitive performance windows | Phase-locked circadian rhythm estimation |
| `HeatAcclimationEngine` | Thermal strain and heart rate drift under ambient heat | Cardiac drift and plasma volume adaptation metrics |
| `LabReportParser` | Deterministic text and tabular lab extraction for blood panels | Regex-driven Turkish laboratory standard parser |
| `BiomarkerCatalog` | Biological reference intervals for clinical blood markers | Standard hematological and metabolic reference bounds |

---

## Scientific Boundaries and Known Limitations

Reliability requires explicit disclosure of what the system cannot compute:

* **NORM-1 Disclosures**: Population reference baselines for rare biomarkers without established longitudinal cohort data are left unpopulated rather than interpolated with unvalidated synthetic priors.
* **Cold-Start Phase**: Days 1–5 produce no isolated recovery scores; days 6–13 blend personal metrics with population priors ($w = n / 14$). Full personalization is active only after $\ge 14$ days of recorded nocturnal wear.
* **Sensor Artefacts**: Extreme biometric outliers (e.g., HRV $> 900\text{ms}$) are rejected outright at the data quality layer rather than clamped, preventing distortion of rolling baselines.
* **Nutritional and Caloric Boundaries (§1)**: Zenithium intentionally does not track calories, macronutrients, or body weight. Caloric intake models introduce substantial reporting errors that degrade physiological decision models.

---

## Building and Verification

### Requirements
- macOS 15.0+
- Xcode 16.0+ (Swift 6.0 toolchain)
- Apple Developer Account with App Group capabilities (`group.<TeamID>.zenithium`)

### Quick Build

```sh
# Generate project files and check source alignment
./Scripts/preflight.sh

# Run entire test suite (596 tests, Swift Testing)
xcodebuild test -project Zenithium.xcodeproj -scheme Zenithium -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

### Preflight Verification Pipeline
`Scripts/preflight.sh` validates the repository state before compilation:
1. `check-target-sources.py`: Ensures target membership and App Group synchronization across entitlements.
2. `check-symbols.py`: Validates Swift symbol availability and syntax consistency.
3. `check-privacy-manifest.py`: Verifies zero undeclared network or tracking entitlements in privacy manifests.
4. `generate-project.py`: Regenerates `Zenithium.xcodeproj` directly from `project.yml`.

---

## Repository Structure

```
Zenithium/
├── App/              Application lifecycle, composition root, tab router
├── Support/          OSLog logging infrastructure, App Group identifiers
├── Domain/           Sendable DTOs, domain models, error enumerations, SafetyCopy
├── Models/           SwiftData schema definitions and model configurations
├── Health/           HealthKit actor isolation, DTO mapping, mock provider
├── Engines/          29 pure calculation engines (Foundation only)
├── Persistence/      ModelActor store, repository protocols, caching layer
├── Orchestration/    Daily recalculation coordinator, background tasks, relays
├── ViewModels/       @MainActor @Observable presentation controllers
└── Views/            Design system (SF Pro typography, anodized spectrum) and feature views
ZenithiumWidgets/     Lock Screen and Home Screen widgets
ZenithiumWatch/       watchOS independent workout and biometric tracking target
ZenithiumTests/       596 unit, integration, and golden vector test cases
Scripts/              Preflight, validation, and project generation utilities
docs/                 Scientific specifications, legal documents (privacy & support), and web assets
```

---

## Legal & App Store Hosting (GitHub Pages)

The public privacy policy and support landing pages are hosted via GitHub Pages from `/docs`:
- **Privacy Policy**: `https://projectcagla.github.io/zenithium/privacy`
- **Support Page**: `https://projectcagla.github.io/zenithium/support`

### Enabling GitHub Pages
1. Navigate to repository **Settings** › **Pages**.
2. Under **Build and deployment** › **Source**, select **Deploy from a branch**.
3. Under **Branch**, select **`main`** and folder **`/docs`**, then click **Save**.

