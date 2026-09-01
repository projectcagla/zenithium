//
//  StrainScale.swift
//  Zenithium
//
//  The TRIMP ↔ strain mapping, on its own. Yol haritası v4, C1.
//
//  These four functions used to live inside `StrainEngine`, which is fine until something
//  other than the phone needs them. The live session screen on the watch needs exactly this
//  mapping and nothing else — not the day integral, not the heart-rate resolution, not the
//  recovery-derived ceiling — and pulling `StrainEngine` into the watch target would have
//  dragged `RecoveryEngine` and `BaselineEngine` behind it.
//
//  So the scale moves here, into `Domain`, which every target already compiles. `StrainEngine`
//  forwards to it and keeps its own orchestration. There is still one definition of what a
//  strain of 14 means, which is the property that matters: two surfaces disagreeing about the
//  same number is worse than either of them being slightly wrong.
//
//  §5.3 — `DailyStrain = 21 · (1 − e^(−k · TRIMP))`.
//

import Foundation

/// The mapping between accumulated training impulse and the 0–21 strain scale.
enum StrainScale {

    /// §5.3 — `DailyStrain = 21 · (1 − e^(−k · TRIMP))`.
    static func strain(forTRIMP trimp: Double) -> Double {
        guard trimp.isFinite, trimp > 0 else { return 0 }
        let exponent = MathSupport.clamp(-EngineConstants.Strain.trimpScaleK * trimp, -60, 0)
        return EngineConstants.Strain.scaleMax * (1 - exp(exponent))
    }

    /// The inverse of `strain(forTRIMP:)`.
    ///
    /// `strain = S·(1 − e^(−k·TRIMP))`  ⟹  `TRIMP = −ln(1 − strain/S) / k`
    ///
    /// Returns `nil` at or above the scale ceiling, where the logarithm diverges — the model
    /// says that strain is approached but never reached, and inventing a finite answer there
    /// would be inventing physiology.
    static func trimp(forStrain strain: Double) -> Double? {
        let scale = EngineConstants.Strain.scaleMax
        guard strain > 0 else { return 0 }
        guard strain < scale else { return nil }
        return -log(1 - strain / scale) / EngineConstants.Strain.trimpScaleK
    }

    /// TRIMP for a session held at a fixed fraction of heart-rate reserve.
    ///
    /// The forward integral with a constant integrand: `TRIMP = minutes · x · b · e^(c·x)`.
    static func trimp(
        forMinutes minutes: Double,
        reserveFraction: Double,
        biologicalSex: BiologicalSexValue
    ) -> Double {
        guard minutes > 0 else { return 0 }
        let constants = biologicalSex.trimpConstants
        let x = MathSupport.clamp(reserveFraction, 0, 1)
        return minutes * x * constants.b * exp(constants.c * x)
    }

    /// How many minutes at `reserveFraction` reach `trimp`.
    ///
    /// The same expression solved for duration. Returns `nil` at zero intensity, where no
    /// amount of time accumulates load.
    static func minutes(
        forTRIMP trimp: Double,
        reserveFraction: Double,
        biologicalSex: BiologicalSexValue
    ) -> Double? {
        let constants = biologicalSex.trimpConstants
        let x = MathSupport.clamp(reserveFraction, 0, 1)
        let perMinute = x * constants.b * exp(constants.c * x)
        guard perMinute > 0 else { return nil }
        return trimp / perMinute
    }

    /// Fraction of heart-rate reserve at a given beat rate. Clamped to 0…1.
    static func reserveFraction(
        heartRate: Double,
        restingHeartRate: Double,
        maxHeartRate: Double
    ) -> Double {
        let span = maxHeartRate - restingHeartRate
        guard span > 0 else { return 0 }
        return MathSupport.clamp((heartRate - restingHeartRate) / span, 0, 1)
    }
}
