import Foundation
import WidgetKit
import ActivityKit
import WatchConnectivity

struct IntegrationStatus: Sendable, Equatable {
    var widgets = "Kontrol ediliyor"
    var liveActivities = "Kontrol ediliyor"
    var watch = "Kontrol ediliyor"
    var lastSummary: Date?
}

@MainActor
enum IntegrationStatusCoordinator {
    static func read() async -> IntegrationStatus {
        var status = IntegrationStatus()
        do {
            let configurations = try await WidgetCenter.shared.currentConfigurations()
            status.widgets = configurations.isEmpty ? "Henüz widget eklenmemiş" : "\(configurations.count) widget ekli"
        } catch { status.widgets = "Widget durumu okunamadı" }
        status.liveActivities = ActivityAuthorizationInfo().areActivitiesEnabled ? "Sistem izni açık" : "Sistem ayarlarında kapalı"
        if WCSession.isSupported() {
            let session = WCSession.default
            if !session.isPaired { status.watch = "Eşlenmiş saat yok" }
            else if !session.isWatchAppInstalled { status.watch = "Saat uygulaması kurulu değil" }
            else if session.activationState != .activated { status.watch = "Bağlantı hazırlanıyor" }
            else { status.watch = session.isReachable ? "Saat şu anda erişilebilir" : "Saat eşli; aktarım bağlantı bekliyor" }
        } else { status.watch = "Bu cihazda desteklenmiyor" }
        let snapshot = WidgetSnapshotStore.read()
        status.lastSummary = snapshot.generatedAt > Date(timeIntervalSince1970: 0) ? snapshot.generatedAt : nil
        return status
    }
}
