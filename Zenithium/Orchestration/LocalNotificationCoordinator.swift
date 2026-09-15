import Foundation
import UserNotifications

struct LocalReminderPlan: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let weekday: Int?
}

actor LocalNotificationCoordinator {
    private let center = UNUserNotificationCenter.current()
    private static let morningID = "zenithium.morning"
    private static let weeklyID = "zenithium.weekly"
    private static let missingID = "zenithium.missingNight"

    func authorizationLabel() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized: return "İzin açık"
        case .provisional, .ephemeral: return "Sessiz bildirim izni"
        case .denied: return "Sistem ayarlarında kapalı"
        case .notDetermined: return "Henüz izin istenmedi"
        @unknown default: return "Durum okunamadı"
        }
    }

    func apply(_ preferences: PersonalPreferences, requestingPermission: Bool = false) async throws {
        if requestingPermission && (preferences.morningReminder || preferences.weeklyReminder || preferences.missingNightReminder) {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw ZenithiumError.invalidEngineInput(reason: "Bildirim izni kapalı. iPhone Ayarları'ndan Zenithium bildirimlerini açabilirsin.")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningID, Self.weeklyID])
        if !preferences.missingNightReminder { center.removePendingNotificationRequests(withIdentifiers: [Self.missingID]) }
        for plan in Self.plans(for: preferences) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            var components = DateComponents()
            components.hour = plan.hour
            components.minute = plan.minute
            components.weekday = plan.weekday
            try await center.add(UNNotificationRequest(identifier: plan.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
    }

    nonisolated static func plans(for preferences: PersonalPreferences) -> [LocalReminderPlan] {
        var result: [LocalReminderPlan] = []
        if preferences.morningReminder {
            let minute = (preferences.wakeMinute + 15) % 1440
            result.append(LocalReminderPlan(id: morningID, title: "Gününe bir bakış",
                body: "Uyku, toparlanma ve günlük kararını Zenithium'da gözden geçir.",
                hour: minute / 60, minute: minute % 60, weekday: nil))
        }
        if preferences.weeklyReminder {
            result.append(LocalReminderPlan(id: weeklyID, title: "Haftana dönüp bak",
                body: "Haftalık uyku ve antrenman eğilimlerini Zenithium'da inceleyebilirsin.",
                hour: 18, minute: 0, weekday: 1))
        }
        return result
    }

    func checkNight(_ record: BiometricDaySnapshot, preferences: PersonalPreferences, now: Date) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [Self.missingID])
        guard preferences.missingNightReminder else { return }
        let calendar = Calendar.autoupdatingCurrent
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard calendar.isDate(record.dayStart, inSameDayAs: now), minute >= preferences.wakeMinute + 120,
              record.heartRateVariability == nil || record.sleepDurationSeconds <= 0 else { return }
        // One notification per observation date, even if a foreground refresh repeats.
        let delivered = await center.deliveredNotifications()
        guard !delivered.contains(where: { $0.request.identifier == Self.missingID && calendar.isDate($0.date, inSameDayAs: now) }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Gece kaydını kontrol et"
        content.body = "Son okumada uyku veya HRV kaydı eksikti. Saatinin eşitlendiğini ve Sağlık erişimini kontrol edebilirsin."
        try await center.add(UNNotificationRequest(identifier: Self.missingID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
