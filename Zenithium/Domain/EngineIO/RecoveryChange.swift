import Foundation

struct RecoveryChange: Sendable, Equatable {
    struct Contribution: Sendable, Equatable, Identifiable {
        let driver: RecoveryDriver
        let points: Double
        let coverageChanged: Bool
        var id: RecoveryDriver { driver }
    }
    let previousScore: Double
    let currentScore: Double
    let contributions: [Contribution]
    let baselineAndModelPoints: Double
    var delta: Double { currentScore - previousScore }
}
