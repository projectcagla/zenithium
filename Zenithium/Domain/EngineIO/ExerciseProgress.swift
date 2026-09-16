import Foundation

struct ExerciseProgress: Sendable, Equatable, Identifiable {
    struct Point: Sendable, Equatable, Identifiable {
        let date: Date
        let sets: Int
        let repetitions: Int
        /// Nil if any working weight is unrecorded; missing weight is never zero.
        let volumeKilograms: Double?
        let estimatedMaximum: Double?
        var id: Date { date }
    }
    let name: String
    let points: [Point]
    var id: String { name }
}
