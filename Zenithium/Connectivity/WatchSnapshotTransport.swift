import Foundation
import WatchConnectivity

/// App Group files belong to one device. Transfer the encoded snapshot explicitly.
enum WatchSnapshotTransport {
    static func publish(_ snapshot: WidgetSnapshot, eraseBefore: Date? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        var context: [String: Any] = ["zenithiumSnapshot": data]
        if let eraseBefore { context["zenithiumEraseBefore"] = eraseBefore.timeIntervalSince1970 }
        else if let cutoff = AppGroup.defaults?.object(forKey: "watchEraseBefore") as? Date {
            context["zenithiumEraseBefore"] = cutoff.timeIntervalSince1970
        }
        do { try session.updateApplicationContext(context) }
        catch { ZenithiumLog.widget.error("Watch snapshot could not be queued: \(error.localizedDescription, privacy: .public)") }
    }
}
