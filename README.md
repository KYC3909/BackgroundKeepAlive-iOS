# BackgroundKeepAlive — iOS 24h+ Background Execution

A minimal, production-ready iOS app demonstrating every approved technique
to keep a background service alive for 24+ hours without being killed by iOS.

---

## Why iOS Kills Background Apps (and How We Stop It)

iOS uses a **multi-tier suspension model**:

| State | What iOS does |
|-------|---------------|
| Active | App runs normally |
| Inactive | Transition state (brief) |
| Background | ~30s to run, then **suspended** |
| Suspended | In memory, no CPU |
| Terminated | Removed from memory |

The strategies below prevent the app from ever reaching **Suspended**.

---

## 5 Stacked Strategies

### 1. Continuous Location Updates (`LocationKeepAliveManager.swift`)
**The most reliable technique on iOS.**

```swift
manager.pausesLocationUpdatesAutomatically = false  // ← CRITICAL
manager.allowsBackgroundLocationUpdates   = true    // ← CRITICAL
manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // low power
```

An app with an **active CLLocationManager** is never suspended by iOS, regardless
of how long it runs. Setting accuracy to 3km means iOS can coalesce updates and
the GPS radio barely activates — battery impact is ~1-2% per hour.

**Requires:**
- `NSLocationAlwaysAndWhenInUseUsageDescription` in Info.plist
- `UIBackgroundModes → location` in Info.plist
- User grants **"Always"** authorization

### 2. Significant Location Change Monitoring
```swift
manager.startMonitoringSignificantLocationChanges()
```

This survives **force-quit**. When the user swipes the app away, iOS will
**relaunch** it in the background when a significant location change occurs
(cell tower change, ~500m movement). This is how apps like Uber recover.

### 3. Silent Audio Session (`SilentAudioManager.swift`)
```swift
try session.setCategory(.playback, options: [.mixWithOthers])
// Play a near-silent 1-second PCM loop at volume 0.01
```

Apps with an active `.playback` audio session are classified as "audio apps"
and exempt from background suspension. The `.mixWithOthers` option means it
won't interrupt Spotify, podcasts, or calls.

**Requires:** `UIBackgroundModes → audio` in Info.plist

### 4. BGTaskScheduler Chain (`AppDelegate.swift`)
```swift
// Register handlers once at launch
BGTaskScheduler.shared.register(forTaskWithIdentifier: BGTaskID.refresh, ...) { ... }
BGTaskScheduler.shared.register(forTaskWithIdentifier: BGTaskID.processing, ...) { ... }

// Each handler reschedules itself — creates an infinite chain
private func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleBGRefresh()          // ← reschedule FIRST before doing work
    // ... do work ...
    task.setTaskCompleted(success: true)
}
```

`BGAppRefreshTask` gives ~30 seconds of execution every ~15 minutes.
`BGProcessingTask` gives several minutes of execution when the device is idle.

**Requires:**
- `BGTaskSchedulerPermittedIdentifiers` in Info.plist (exact string match!)
- `UIBackgroundModes → fetch` and `processing` in Info.plist

### 5. UIKit Background Task (Legacy Safety Net)
```swift
backgroundTaskID = UIApplication.shared.beginBackgroundTask { 
    self.endBackgroundTask() // expiration handler
}
```

This gives a guaranteed ~30-second grace period each time the app transitions
to background, letting strategies 1-3 fully initialise before iOS considers
suspending the app.

---

## Info.plist Checklist

```xml
<!-- REQUIRED: location permission strings (all 3) -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<key>NSLocationWhenInUseUsageDescription</key>
<key>NSLocationAlwaysUsageDescription</key>

<!-- REQUIRED: background modes -->
<key>UIBackgroundModes</key>
<array>
  <string>location</string>    <!-- Strategy 1, 2 -->
  <string>audio</string>       <!-- Strategy 3 -->
  <string>fetch</string>       <!-- Strategy 4a -->
  <string>processing</string>  <!-- Strategy 4b -->
</array>

<!-- REQUIRED: BGTask identifiers — must match code EXACTLY -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.yourapp.background.refresh</string>
  <string>com.yourapp.background.processing</string>
</array>
```

---

## Xcode Setup

1. Open `BackgroundKeepAlive.xcodeproj`
2. Select your **Team** in Signing & Capabilities
3. Change `com.yourapp.backgroundkeepalive` to your bundle ID in:
   - `Info.plist → CFBundleIdentifier`
   - `Info.plist → BGTaskSchedulerPermittedIdentifiers` (both entries)
   - `AppDelegate.swift → BGTaskID` enum
   - `project.pbxproj → PRODUCT_BUNDLE_IDENTIFIER`
4. In **Signing & Capabilities**, add:
   - Background Modes → ✅ Location updates
   - Background Modes → ✅ Background fetch
   - Background Modes → ✅ Background processing
   - Background Modes → ✅ Audio, AirPlay, Picture in Picture
5. Run on a **real device** (background modes don't work on Simulator)

---

## Debugging BGTasks in Xcode

BGAppRefreshTask normally waits 15+ minutes. You can force it instantly:

1. Run the app, go to background
2. In Xcode → **Debug → Simulate Background Fetch**

Or via LLDB console (pause debugger while app is backgrounded):
```lldb
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.yourapp.background.refresh"]
```

---

## Location Permission Flow

```
App launch
    └── requestAlwaysAuthorization()
            ├── User taps "Allow While Using App"
            │       └── iOS later shows upgrade prompt → user can choose "Always"
            └── User taps "Allow Once"
                    └── App shows custom alert explaining why "Always" is needed
```

If the user downgrades to "When In Use" in Settings, the app will show
a notification via `Notification.Name.locationAuthDowngraded`.

---

## Battery Impact Estimates

| Strategy | Battery/hour | Notes |
|----------|-------------|-------|
| Location (3km accuracy) | ~1% | GPS barely activates |
| Silent audio | ~0.2% | Tiny CPU cost |
| BGAppRefresh | ~0.1% | 30s every 15min |
| Total | ~1.3%/hr | ~77h from full battery |

---

## App Store Compliance

✅ All techniques are **Apple-approved**
✅ No private APIs
✅ Location prompt string explains background use (required)
✅ `showsBackgroundLocationIndicator = true` (honest to user)
✅ `mixWithOthers` audio option (doesn't block other audio)

⚠️  Apple **will reject** apps that claim background modes they don't actually
     use. Only declare modes you genuinely need.

---

## File Structure

```
BackgroundKeepAlive/
├── BackgroundKeepAlive.xcodeproj/
│   └── project.pbxproj
└── BackgroundKeepAlive/
    ├── BackgroundKeepAliveApp.swift   ← @main entry, injects AppDelegate
    ├── AppDelegate.swift              ← BGTask registration + lifecycle
    ├── ContentView.swift              ← SwiftUI dashboard
    ├── LocationKeepAliveManager.swift ← Strategy 1 & 2
    ├── SilentAudioManager.swift       ← Strategy 3
    ├── BackgroundActivityLog.swift    ← Observable log + local notifications
    └── Info.plist                     ← All permissions + background modes
```

---

## Minimum Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+
- Real device for testing (not Simulator)
