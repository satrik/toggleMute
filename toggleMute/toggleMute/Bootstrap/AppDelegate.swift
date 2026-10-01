// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var preferences = Preferences()
    lazy var muteController = MuteController()
    let repoUrl = URL(string: "https://github.com/satrik/toggleMute")!
    let popoverView = NSPopover()
    var eventMonitor: EventMonitor?
    var updateCheckTimer: Timer?

    // Tracks whether the last sync saw input volume near zero — used by
    // syncFromHardware() to detect a volume recovery (see there for why).
    private var lastPolledVolumeWasNearZero: Bool?

    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .badge, .sound])
    }


    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // click on notifiaction button
        // "showUpdate" because we set this as custom identifier
        // click on notification
        // "com.apple.UNNotificationDefaultActionIdentifier"
        // click on x to dismiss notification
        // "com.apple.UNNotificationDismissActionIdentifier"
        
        if (response.actionIdentifier == "showUpdate" && response.notification.request.content.categoryIdentifier == "updateAvailable") {
            if let url = URL(string: "https://github.com/satrik/toggleMute/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
        
        completionHandler()
        
    }
        
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        LaunchAtLogin.migrateIfNeeded()
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Checks at launch (if due) and re-evaluates hourly so a long-running
        // session still gets checked at least once a day — see
        // performUpdateCheckIfDue() for the actual 24h gating.
        performUpdateCheckIfDue()
        updateCheckTimer = Timer.scheduledTimer(timeInterval: 3600, target: self, selector: #selector(performUpdateCheckIfDue), userInfo: nil, repeats: true)

        // Only relevant to the HUD's fullscreen-aware positioning (see
        // HUDController.isFullScreenAppActive) — only asked of people who've
        // actually turned the HUD on, not every user. Without this, that
        // check just quietly returns false and the HUD keeps its normal
        // top-right spot, so declining here doesn't break anything else.
        if UserDefaults.standard.bool(forKey: "hudEnabled") {
            HUDController.shared.requestAccessibilityPermissionIfNeeded()
        }
        
        if let button = self.statusItem.button {
            
            button.image = muteController.imageUnmute?.tint(color: .selectedMenuItemTextColor)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])

            // Enable a backing layer once so the optional red background
            // (see MuteController/MainController) can have rounded
            // corners instead of a hard-edged rectangle, matching the pill
            // shape macOS uses elsewhere in the menu bar.
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.masksToBounds = true

        }
        
        popoverView.contentViewController = MainController.createController()
        popoverView.setValue(true, forKeyPath: "shouldHideAnchor")
        popoverView.behavior = .transient

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
          
            if let strongSelf = self, (strongSelf.popoverView.isShown) {
                strongSelf.popoverView.performClose((Any).self)
                strongSelf.eventMonitor?.stop()
            }
          
        }
        
        muteController.configureUI()

        AudioInputController.startMonitoring(
            devicesChanged: { [weak self] in self?.inputDevicesChanged() },
            stateChanged: { [weak self] in self?.syncFromHardware() }
        )
        
        KeyboardShortcuts.onKeyDown(for: .toggleMuteShortcut) {
            if self.preferences.pushToTalkEnabled {
                // Press: go live only while the key is held down. holdHUD
                // keeps the HUD on screen for as long as the key is held.
                self.muteController.toggleMuteStateHard(setMute: false, holdHUD: true)
            } else {
                self.muteController.toggleMuteState()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleMuteShortcut) {
            if self.preferences.pushToTalkEnabled {
                // Release: mute again immediately.
                self.muteController.toggleMuteStateHard(setMute: true)
            }
        }

    }


    // Leaves no microphone muted without the app around to unmute it. The
    // stored "isMuted" stays, so the next launch mutes again.
    func applicationWillTerminate(_ notification: Notification) {

        if muteController.isMuted { AudioInputController.setMuted(false) }

    }


    // Runs the actual check only if it's never run before, or it's been at
    // least a day since the last one — called at launch and then every hour
    // to re-evaluate, which (unlike a bare 24h timer) keeps working
    // correctly across sleep/wake since it's based on a stored timestamp
    // rather than elapsed timer ticks.
    @objc func performUpdateCheckIfDue() {

        let dayInSeconds: TimeInterval = 24 * 60 * 60
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date

        if lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= dayInSeconds {
            checkForUpdates()
        }

    }
    
    
    func checkForUpdates() {

        guard let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/satrik/toggleMute/releases/latest") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: request) { (data, response, error) in

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            // Only mark "checked" once we actually got a usable response, so
            // a transient network hiccup doesn't push the next attempt out
            // by a full day.
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckDate")

            let githubVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if githubVersion.isNewerVersion(than: localVersion) {
                DispatchQueue.main.async {
                    self.sendNotification()
                }
            }

        }

        task.resume()

    }
    
    
    func sendNotification() {

        // Homebrew Cask copies/moves the .app straight into /Applications —
        // its bundle path looks identical to a manual install, so checking
        // Bundle.main.bundlePath for anything Homebrew-specific never
        // matches. Homebrew does keep its own bookkeeping in a separate
        // Caskroom directory regardless of where the .app itself ends up,
        // so check for that instead.
        let installedViaBrew = ["/opt/homebrew/Caskroom/togglemute", "/usr/local/Caskroom/togglemute"]
            .contains { FileManager.default.fileExists(atPath: $0) }

        let msgBody = installedViaBrew
            ? "Run \"brew update && brew upgrade togglemute\" in your terminal to update"
            : "A new version is available on GitHub — click to view the release"

        let content = UNMutableNotificationContent()
        content.title = "toggleMute update available 🚀"
        content.body = msgBody
        content.sound = .default
        content.categoryIdentifier = "updateAvailable"
        
        let uuidString = UUID().uuidString
        let trigger = UNTimeIntervalNotificationTrigger.init(timeInterval: 3.0, repeats: false)
        let showUpdate = UNNotificationAction(identifier: "showUpdate", title: "Go to GitHub", options: .foreground)
        let category = UNNotificationCategory(identifier: "updateAvailable", actions: [showUpdate], intentIdentifiers: [], options: .customDismissAction)
        let notificationCenter = UNUserNotificationCenter.current()
        
        notificationCenter.setNotificationCategories([category])
        
        let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)
        notificationCenter.add(request)
        
    }
    
    
    // Brings newly controlled devices (plugged in, new default input, new
    // selection) to the apps current mute state.
    func inputDevicesChanged() {

        lastPolledVolumeWasNearZero = nil
        muteController.applyMuteStateToDevices()

    }


    func syncFromHardware() {

        // Sync UI to the actual device state so the icon reflects external mute
        // changes (e.g. from the system menu). Reads the real CoreAudio mute
        // property — falls back to "volume == 0" only when no mute property is
        // exposed. If we can't tell, leave the UI alone instead of flipping it.
        guard let muted = AudioInputController.isMuted() else { return }

        // Some hardware (many Bluetooth/USB headsets, e.g. Jabra) only has a
        // mute BUTTON that drives input volume — it never touches CoreAudio's
        // mute property at all. When we detect that kind of external mute
        // (via the volume-near-zero fallback in AudioInputController), we
        // also write the real mute property so Audio MIDI Setup reflects it
        // correctly. But since the hardware itself never clears that
        // property again, a second press that raises the volume back up
        // still reads back mutePropertyResult == true, and AudioInputController
        // trusts the property over volume — so the app stays stuck "muted".
        // A volume recovery (near-zero -> clearly non-zero) while we're
        // currently muted is an unambiguous "the hardware just unmuted"
        // signal, so it overrides a stuck property and forces a proper
        // unmute (which clears the property too).
        let volumeIsNearZero = (AudioInputController.volume() ?? 1) < 0.05
        let volumeJustRecovered = lastPolledVolumeWasNearZero == true && !volumeIsNearZero
        lastPolledVolumeWasNearZero = volumeIsNearZero

        if volumeJustRecovered && muteController.isMuted {
            muteController.toggleMuteStateHard(setMute: false)
        } else {
            muteController.toggleMuteStateHard(setMute: muted)
        }

    }
    
    
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {

        switch NSApp.currentEvent?.type {

        case .rightMouseUp:
            showMainController()

        case .leftMouseDown:
            if preferences.pushToTalkEnabled {
                // Press: go live only while the icon is held down. holdHUD
                // keeps the HUD on screen for as long as it's held.
                muteController.toggleMuteStateHard(setMute: false, holdHUD: true)
            }

        case .leftMouseUp:
            if preferences.pushToTalkEnabled {
                // Release: mute again immediately.
                muteController.toggleMuteStateHard(setMute: true)
            } else {
                muteController.toggleMuteState()
            }

        default:
            break

        }
    }
    
    
    @objc private func showMainController() {
        
        let mainController = MainController.instantiate(with: preferences)
        popoverView.contentViewController = mainController

        guard let button = statusItem.button else {
            fatalError("Couldn't find status item button.")
        }
        
        if(popoverView.isShown) {
            
            popoverView.close()
            eventMonitor?.stop()
            
        } else {
            
            popoverView.show(relativeTo: button.bounds.offsetBy(dx: 0, dy: -6), of: button, preferredEdge: NSRectEdge.minY)
            popoverView.contentViewController?.view.window?.becomeKey()
            
            eventMonitor?.start()
            NSApp.activate(ignoringOtherApps: true)

        }

    }

    
}


extension String {

    /// Component-wise numeric version comparison (e.g. "1.10.0" is newer
    /// than "1.9.0" — a plain string or Double comparison would get that
    /// wrong). Each dot-separated component is read as its leading run of
    /// digits, so "7b" contributes 7 and non-numeric suffixes are ignored;
    /// for fully reliable comparisons, GitHub release tags should stick to
    /// plain "X.Y.Z" numbers.
    func isNewerVersion(than other: String) -> Bool {

        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { part -> Int in
                let digits = part.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
        }

        let mine = components(self)
        let theirs = components(other)
        let count = max(mine.count, theirs.count)

        for i in 0..<count {
            let a = i < mine.count ? mine[i] : 0
            let b = i < theirs.count ? theirs[i] : 0
            if a != b { return a > b }
        }

        return false

    }

}
