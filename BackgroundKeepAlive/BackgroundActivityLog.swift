import Foundation
import UserNotifications

/// Lightweight in-memory + persisted log of every background ping.
/// Observable so SwiftUI ContentView can display live updates.
final class BackgroundActivityLog: ObservableObject {

    static let shared = BackgroundActivityLog()

    struct Entry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let source: String

        var formattedTime: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let storageKey = "bg_activity_log"
    private let maxEntries = 200

    private init() {
        loadFromDisk()
    }

    // ── Public ────────────────────────────────────────────────────────────

    func recordPing(source: String) {
        let entry = Entry(id: UUID(), timestamp: Date(), source: source)

        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
            self.saveToDisk()
        }

        // Post a local notification so the user sees activity even with phone locked
        postLocalNotification(message: "[\(source)] ✓ Background ping @ \(entry.formattedTime)")
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
            self.saveToDisk()
        }
    }

    // Computed uptime from first recorded entry
    var uptimeString: String {
        guard let oldest = entries.last else { return "–" }
        let diff = Date().timeIntervalSince(oldest.timestamp)
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        let s = Int(diff) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // ── Persistence ───────────────────────────────────────────────────────

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    // ── Local Notifications ───────────────────────────────────────────────

    private var notifCount = 0

    private func postLocalNotification(message: String) {
        // Throttle: 1 notification per minute maximum
        notifCount += 1
        guard notifCount % 6 == 0 else { return } // ~every 6 pings

        let content = UNMutableNotificationContent()
        content.title = "Background Alive ✅"
        content.body  = message
        content.sound = .none

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "bg-ping-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
