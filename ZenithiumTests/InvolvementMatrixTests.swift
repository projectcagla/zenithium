//
//  InvolvementMatrixTests.swift
//  ZenithiumTests
//
//  Spec §5.4: the seven normative rows exactly, every row in range, and strength types
//  contributing no muscle impact from HealthKit (ASSUMPTION MUSCLE-2).
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Muscle involvement matrix")
struct InvolvementMatrixTests {

    // MARK: - §5.4 normative rows

    @Test("Running")
    func running() {
        let row = MuscleInvolvementMatrix.involvement(for: .running)
        expectClose(row[.quads] ?? .nan, 0.55, tolerance: 1e-9, "quads")
        expectClose(row[.hamstrings] ?? .nan, 0.50, tolerance: 1e-9, "hamstrings")
        expectClose(row[.calves] ?? .nan, 0.70, tolerance: 1e-9, "calves")
        expectClose(row[.glutes] ?? .nan, 0.45, tolerance: 1e-9, "glutes")
        expectClose(row[.core] ?? .nan, 0.25, tolerance: 1e-9, "core")
        expectClose(row[.lowerBack] ?? .nan, 0.20, tolerance: 1e-9, "lower back")
        #expect(row.count == 6)
    }

    @Test("Cycling")
    func cycling() {
        let row = MuscleInvolvementMatrix.involvement(for: .cycling)
        expectClose(row[.quads] ?? .nan, 0.75, tolerance: 1e-9, "quads")
        expectClose(row[.glutes] ?? .nan, 0.50, tolerance: 1e-9, "glutes")
        expectClose(row[.calves] ?? .nan, 0.35, tolerance: 1e-9, "calves")
        expectClose(row[.hamstrings] ?? .nan, 0.30, tolerance: 1e-9, "hamstrings")
        expectClose(row[.lowerBack] ?? .nan, 0.25, tolerance: 1e-9, "lower back")
        #expect(row.count == 5)
    }

    @Test("Swimming")
    func swimming() {
        let row = MuscleInvolvementMatrix.involvement(for: .swimming)
        expectClose(row[.lats] ?? .nan, 0.70, tolerance: 1e-9, "lats")
        expectClose(row[.shoulders] ?? .nan, 0.65, tolerance: 1e-9, "shoulders")
        expectClose(row[.upperBack] ?? .nan, 0.50, tolerance: 1e-9, "upper back")
        expectClose(row[.triceps] ?? .nan, 0.40, tolerance: 1e-9, "triceps")
        expectClose(row[.core] ?? .nan, 0.45, tolerance: 1e-9, "core")
        #expect(row.count == 5)
    }

    @Test("Rowing")
    func rowing() {
        let row = MuscleInvolvementMatrix.involvement(for: WorkoutActivity.rowing)
        expectClose(row[.lats] ?? .nan, 0.70, tolerance: 1e-9, "lats")
        expectClose(row[.upperBack] ?? .nan, 0.65, tolerance: 1e-9, "upper back")
        expectClose(row[.quads] ?? .nan, 0.50, tolerance: 1e-9, "quads")
        expectClose(row[.biceps] ?? .nan, 0.40, tolerance: 1e-9, "biceps")
        expectClose(row[.lowerBack] ?? .nan, 0.45, tolerance: 1e-9, "lower back")
        expectClose(row[.core] ?? .nan, 0.35, tolerance: 1e-9, "core")
        #expect(row.count == 6)
    }

    @Test("Hiking")
    func hiking() {
        let row = MuscleInvolvementMatrix.involvement(for: .hiking)
        expectClose(row[.quads] ?? .nan, 0.55, tolerance: 1e-9, "quads")
        expectClose(row[.glutes] ?? .nan, 0.55, tolerance: 1e-9, "glutes")
        expectClose(row[.calves] ?? .nan, 0.50, tolerance: 1e-9, "calves")
        expectClose(row[.hamstrings] ?? .nan, 0.40, tolerance: 1e-9, "hamstrings")
        expectClose(row[.core] ?? .nan, 0.20, tolerance: 1e-9, "core")
        #expect(row.count == 5)
    }

    @Test("Walking")
    func walking() {
        let row = MuscleInvolvementMatrix.involvement(for: .walking)
        expectClose(row[.calves] ?? .nan, 0.25, tolerance: 1e-9, "calves")
        expectClose(row[.quads] ?? .nan, 0.20, tolerance: 1e-9, "quads")
        expectClose(row[.glutes] ?? .nan, 0.20, tolerance: 1e-9, "glutes")
        #expect(row.count == 3)
    }

    // MARK: - ASSUMPTION MUSCLE-2

    @Test("Strength activity types contribute no muscle impact from HealthKit")
    func strengthTypesAreEmpty() {
        #expect(MuscleInvolvementMatrix.involvement(for: .traditionalStrengthTraining).isEmpty)
        #expect(MuscleInvolvementMatrix.involvement(for: .functionalStrengthTraining).isEmpty)
        #expect(!MuscleInvolvementMatrix.contributesMuscleImpact(.traditionalStrengthTraining))
        #expect(!MuscleInvolvementMatrix.contributesMuscleImpact(.functionalStrengthTraining))
        // The domain type agrees, so the two paths cannot drift.
        #expect(!WorkoutActivity.traditionalStrengthTraining.contributesMuscleImpactFromHealthKit)
        #expect(WorkoutActivity.traditionalStrengthTraining.invitesStrengthLogging)
    }

    // MARK: - ASSUMPTION MUSCLE-1 coverage

    @Test("Every activity has a row in range", arguments: WorkoutActivity.allCases)
    func rowsAreInRange(activity: WorkoutActivity) {
        let row = MuscleInvolvementMatrix.involvement(for: activity)
        for (muscle, value) in row {
            #expect(value > 0, "\(activity.rawValue) → \(muscle.rawValue) must be positive if present")
            #expect(value <= 1, "\(activity.rawValue) → \(muscle.rawValue) must not exceed 1")
        }
    }

    @Test("Only the strength types are empty")
    func onlyStrengthTypesEmpty() {
        let empty = WorkoutActivity.allCases.filter {
            MuscleInvolvementMatrix.involvement(for: $0).isEmpty
        }
        #expect(Set(empty) == [.traditionalStrengthTraining, .functionalStrengthTraining])
    }

    @Test("An unrecognised activity still registers load rather than discarding it")
    func fallbackRowIsNotEmpty() {
        let row = MuscleInvolvementMatrix.involvement(for: .other)
        #expect(!row.isEmpty)
        for value in row.values {
            #expect(value > 0 && value <= 1)
        }
    }

    // MARK: - §5.4 movement patterns

    @Test("Every movement pattern has a row in range", arguments: MovementPattern.compoundCases)
    func patternRowsInRange(pattern: MovementPattern) {
        let row = MuscleInvolvementMatrix.involvement(for: pattern)
        #expect(!row.isEmpty)
        for value in row.values {
            #expect(value > 0 && value <= 1)
        }
    }

    @Test("An isolation pattern loads exactly one group, fully")
    func isolationLoadsOneGroup() {
        for muscle in MuscleGroup.allCases {
            let row = MuscleInvolvementMatrix.involvement(for: .isolation(muscle))
            #expect(row.count == 1)
            expectClose(row[muscle] ?? .nan, 1.0, tolerance: 1e-9, muscle.rawValue)
        }
    }

    @Test("The compound patterns load the groups their names imply")
    func patternsMatchNames() {
        #expect(MuscleInvolvementMatrix.involvement(for: .push)[.chest] != nil)
        #expect(MuscleInvolvementMatrix.involvement(for: .pull)[.lats] != nil)
        #expect(MuscleInvolvementMatrix.involvement(for: .squat)[.quads] != nil)
        #expect(MuscleInvolvementMatrix.involvement(for: .hinge)[.hamstrings] != nil)
        #expect(MuscleInvolvementMatrix.involvement(for: .carry)[.forearms] != nil)

        // A push does not load the lats, and a pull does not load the chest — if these ever
        // become true the matrix has been edited carelessly.
        #expect(MuscleInvolvementMatrix.involvement(for: .push)[.lats] == nil)
        #expect(MuscleInvolvementMatrix.involvement(for: .pull)[.chest] == nil)
    }

    // MARK: - Storage order

    @Test("Muscle storage indices are unique and cover 0..<16")
    func storageIndicesAreStable() {
        let indices = MuscleGroup.allCases.map(\.storageIndex)
        #expect(Set(indices).count == MuscleGroup.allCases.count)
        #expect(indices.sorted() == Array(0..<MuscleGroup.allCases.count))
        for muscle in MuscleGroup.allCases {
            #expect(MuscleGroup.group(atStorageIndex: muscle.storageIndex) == muscle)
        }
    }

    @Test("Zone storage indices are unique and cover 0..<6")
    func zoneIndicesAreStable() {
        let indices = HeartRateZone.allCases.map(\.index)
        #expect(Set(indices).count == HeartRateZone.allCases.count)
        #expect(indices.sorted() == Array(0..<HeartRateZone.allCases.count))
    }
}
