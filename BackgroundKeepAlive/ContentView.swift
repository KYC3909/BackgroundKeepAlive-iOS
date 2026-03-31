import SwiftUI
import CoreLocation

struct ContentView: View {

    @ObservedObject private var log = BackgroundActivityLog.shared
    @State private var authStatus: String = checkAuthStatus()
    @State private var timer: Timer?

    // Refresh uptime label every second
    @State private var uptimeTick = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // ── Header status card ────────────────────────────────────
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(log.entries.isEmpty ? Color.orange : Color.green)
                            .frame(width: 10, height: 10)
                        Text(log.entries.isEmpty ? "Waiting for first ping…" : "Background ACTIVE")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        Label("Uptime", systemImage: "clock")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(log.uptimeString)
                            .font(.system(.caption, design: .monospaced))
                            .id(uptimeTick) // force redraw
                    }

                    HStack {
                        Label("Location Auth", systemImage: "location.fill")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(authStatus)
                            .font(.caption)
                            .foregroundColor(authStatus == "Always" ? .green : .orange)
                    }

                    HStack {
                        Label("Ping count", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("\(log.entries.count)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding()

                // ── Strategy explanation ──────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active strategies")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    StrategyRow(icon: "location.fill",
                                color: .blue,
                                title: "Continuous Location (3km accuracy)",
                                detail: "pausesAutomatically=false, allowsBackground=true")
                    StrategyRow(icon: "mappin.circle.fill",
                                color: .teal,
                                title: "Significant Location Change",
                                detail: "Survives force-quit, re-launches app")
                    StrategyRow(icon: "speaker.wave.1.fill",
                                color: .purple,
                                title: "Silent Audio Loop",
                                detail: "AVAudioSession .playback, mixWithOthers")
                    StrategyRow(icon: "arrow.clockwise.circle.fill",
                                color: .orange,
                                title: "BGAppRefreshTask (15 min chain)",
                                detail: "Reschedules itself on each execution")
                    StrategyRow(icon: "gearshape.2.fill",
                                color: .red,
                                title: "BGProcessingTask (30 min chain)",
                                detail: "Reschedules itself on each execution")
                    StrategyRow(icon: "bolt.fill",
                                color: .yellow,
                                title: "UIKit beginBackgroundTask",
                                detail: "30s grace on each background transition")
                }
                .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // ── Live ping log ─────────────────────────────────────────
                HStack {
                    Text("Background activity log")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { log.clear() }
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)

                List(log.entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.formattedTime)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(entry.source)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }
            .navigationTitle("Background Keep-Alive")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            startUptimeTicker()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthDowngraded)) { _ in
            authStatus = ContentView.checkAuthStatus()
        }
    }

    // MARK: - Helpers

    private func startUptimeTicker() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            uptimeTick += 1
            authStatus = Self.checkAuthStatus()
        }
    }

    private static func checkAuthStatus() -> String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways:      return "Always ✓"
        case .authorizedWhenInUse:   return "When In Use ⚠️"
        case .notDetermined:         return "Not Asked"
        case .denied:                return "Denied ✗"
        case .restricted:            return "Restricted"
        @unknown default:            return "Unknown"
        }
    }
}

// MARK: - Supporting View
struct StrategyRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold())
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
