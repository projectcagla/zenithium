import SwiftUI
import WatchKit

struct WatchStrengthView: View {
    @State private var exercise = "Squat"
    @State private var pattern: MovementPattern = .squat
    @State private var repetitions = 8
    @State private var effort = 7
    @State private var usesWeight = false
    @State private var weight = 20.0
    @State private var message: String?
    @State private var sender = WatchSessionSender.shared

    var body: some View {
        Form {
            TextField("Egzersiz", text: $exercise)
            Picker("Hareket", selection: $pattern) {
                ForEach(MovementPattern.compoundCases, id: \.self) { item in Text(item.displayName).tag(item) }
                ForEach(MuscleGroup.allCases) { muscle in Text(muscle.displayName).tag(MovementPattern.isolation(muscle)) }
            }
            Stepper("\(repetitions) tekrar", value: $repetitions, in: 1...100)
            Stepper("Zorluk: \(effort)/10", value: $effort, in: 1...10)
            Toggle("Ağırlık ekle", isOn: $usesWeight)
            if usesWeight { Stepper("\(ZenithiumFormat.metric(weight, digits: 1)) kg", value: $weight, in: 0...500, step: 2.5) }
            Button("Seti kaydet") { save() }
                .handGestureShortcut(.primaryAction)
                .tint(ZenithiumColor.accent)
            if let message { Text(message).font(.caption2) }
            Text("\(sender.pendingLogs.count) kayıt telefondan onay bekliyor. Telefon bağlı olmasa da kayıt saatte korunur.")
                .font(.caption2)
            if let error = sender.logError { Text(error).font(.caption2) }
        }
        .navigationTitle("Set kaydı")
    }

    private func save() {
        let entry = StrengthEntry(id: UUID(), exerciseName: exercise.trimmingCharacters(in: .whitespacesAndNewlines),
            sets: 1, reps: repetitions, rpe: Double(effort), weightKilograms: usesWeight ? weight : nil)
        do {
            try sender.queue(WatchLogMessage(id: UUID(), createdAt: Date(), timeZoneIdentifier: TimeZone.current.identifier,
                payload: .strength(pattern: pattern, entries: [entry])))
            message = "Set saatte kaydedildi."
            WKInterfaceDevice.current().play(.success)
        } catch { message = error.localizedDescription }
    }
}
