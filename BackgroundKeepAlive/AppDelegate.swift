import UIKit
import BackgroundTasks
import CoreLocation
import AVFoundation
import UserNotifications

// MARK: - Background Task Identifiers
// These MUST match exactly what you register in Info.plist → BGTaskSchedulerPermittedIdentifiers
enum BGTaskID {
    static let refresh     = "com.yourapp.background.refresh"   // BGAppRefreshTask  (30s)
    static let processing  = "com.yourapp.background.processing" // BGProcessingTask (minutes)
}

class AppDelegate: NSObject, UIApplicationDelegate {

    // ── Singletons kept alive via strong references ──────────────────────────
    let locationManager  = LocationKeepAliveManager.shared
    let audioSession     = SilentAudioManager.shared
    let bgTaskScheduler  = BGTaskScheduler.shared

    // Background task handle (UIKit legacy API — still reliable)
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // ─────────────────────────────────────────────────────────────────────────
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // 1. Request notification permission (for status pings to user)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self

        // 2. Register BGTask identifiers (must be done before app finishes launching)
        registerBackgroundTasks()

        // 3. Start all keep-alive strategies
        locationManager.start()
        audioSession.start()

        // 4. Observe app lifecycle
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)

        return true
    }

    // MARK: - Background Task Registration
    private func registerBackgroundTasks() {
        // BGAppRefreshTask – lightweight, ~30s, fires periodically
        bgTaskScheduler.register(forTaskWithIdentifier: BGTaskID.refresh, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        // BGProcessingTask – longer work, requires charging + idle (optional)
        bgTaskScheduler.register(forTaskWithIdentifier: BGTaskID.processing, using: nil) { task in
            self.handleProcessing(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Lifecycle Observers
    @objc private func appDidEnterBackground() {
        // Begin UIKit background task — gives ~30s grace before suspension
        beginBackgroundTask()

        // Schedule next BGAppRefresh / BGProcessing runs
        scheduleBGRefresh()
        scheduleBGProcessing()

        // Keep location + silent audio running
        locationManager.beginBackgroundUpdate()
        audioSession.ensureActive()
    }

    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        locationManager.stopBackgroundUpdate()
    }

    // MARK: - UIKit Background Task (legacy, ~30s window)
    func beginBackgroundTask() {
        endBackgroundTask() // safety: never double-begin
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "KeepAliveTask") {
            // Expiration handler — system is about to suspend; clean up
            self.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - BGTask Scheduling
    private func scheduleBGRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskID.refresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? bgTaskScheduler.submit(request)
    }

    private func scheduleBGProcessing() {
        let request = BGProcessingTaskRequest(identifier: BGTaskID.processing)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 min
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false // set true to only run on charger
        try? bgTaskScheduler.submit(request)
    }

    // MARK: - BGTask Handlers
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Reschedule immediately so the chain never breaks
        scheduleBGRefresh()

        let workItem = DispatchWorkItem {
            // ── Do your lightweight background work here ──
            BackgroundActivityLog.shared.recordPing(source: "BGAppRefresh")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { workItem.cancel(); task.setTaskCompleted(success: false) }
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleBGProcessing()

        let workItem = DispatchWorkItem {
            // ── Do heavier background work here (sync, cleanup, etc.) ──
            BackgroundActivityLog.shared.recordPing(source: "BGProcessingTask")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { workItem.cancel(); task.setTaskCompleted(success: false) }
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
//Please try again later. Bundle at path /Users/developer/Library/Developer/CoreSimulator/Devices/1F27753A-150D-421F-8121-56D928B40122/data/Library/Caches/com.apple.mobile.installd.staging/temp.aQ8VFe/extracted/BackgroundKeepAlive.app has missing or invalid CFBundleExecutable in its Info.plist
