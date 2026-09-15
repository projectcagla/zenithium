import Foundation

struct LabTrainingContext: Sendable, Equatable, Identifiable {
    let day: Date
    let hrv: Double?
    let hrvBaseline: Double?
    let hrvZ: Double?
    let hrvNights: Int
    let loadRatio: Double?
    let loadDays: Int
    var id: Date { day }
}
