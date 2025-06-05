// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var preferences = Preferences()
    private lazy var settingsController = SettingsController()
    private lazy var mainController = MainController()
    private lazy var touchBarController = TouchBarController.instantiate(with: settingsController)
    let popoverView = NSPopover()
    var eventMonitor: EventMonitor?
    var eventMonitor2: EventMonitor?
    var refreshTimer: Timer?
    let defaults = UserDefaults.standard
    let imageUnmute = NSImage(named: NSImage.touchBarAudioInputTemplateName)
    let imageMute = NSImage(named: NSImage.touchBarAudioInputMuteTemplateName)

    
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
            if NSWorkspace.shared.open(mainController.repoUrl) {}
        }
        
        completionHandler()
        
    }
        
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        imageUnmute?.size.height = 18.0
        imageUnmute?.size.width = 15.0
        imageMute?.size.height = 18.0
        imageMute?.size.width = 15.0
        LaunchAtLogin.migrateIfNeeded()
        
        refreshTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(runTimedCode), userInfo: nil, repeats: true)
        
        UNUserNotificationCenter.current().delegate = self
        
        let current = UNUserNotificationCenter.current()
        
        current.getNotificationSettings(completionHandler: { (settings) in
        
            if settings.authorizationStatus == .notDetermined {
            
                // notifications not granted yet, asking user
                current.requestAuthorization(options: [.alert, .sound]){ (granted, error) in
                
                    guard error == nil && granted else {
                        // user denied permissions or an error occured
                        return
                    }
                    // user granted permissions
                    self.checkForUpdates()
                }
                
            } else if settings.authorizationStatus == .denied {
                // notification permission was previously denied
                // could show a hint inside the popover now
            } else if settings.authorizationStatus == .authorized {
                // notification permission was already granted
                self.checkForUpdates()
            }
            
        })
        
        if let button = self.statusItem.button {
            
            button.image = touchBarController.imageUnmute?.tint(color: .selectedMenuItemTextColor)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

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
        
        eventMonitor2 = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
          
            if let strongSelf = self, (strongSelf.popoverView.isShown) {
                strongSelf.mainController.popoverSettingsView.close()
                strongSelf.eventMonitor2?.stop()
                
                strongSelf.popoverView.close()
                strongSelf.eventMonitor?.stop()
            }
          
        }
        
        touchBarController.configureUI()
        
        KeyboardShortcuts.onKeyDown(for: .toggleMuteShortcut) {
            self.touchBarController.toggleMuteState()
            print("start")
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleMuteShortcut) {
            print("stop")
        }
        
    }
    
    
    func checkForUpdates() {
        
        let getlocalVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let stringLocalVersion = getlocalVersion! as NSString
        defaults.set(stringLocalVersion, forKey: "stringLocalVersion")
        let localVersion = stringLocalVersion.doubleValue
        
        let url = URL(string: "https://raw.githubusercontent.com/satrik/toggleMute/main/toggleMute/toggleMute.xcodeproj/project.pbxproj")!
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: url) {(data, response, error) in
            guard let data = data, error == nil else { return }
            let getString = String(data: data, encoding: .utf8)!
            
            let firstIndex = "MARKETING_VERSION = "
            let secondIndex = ";"
            let stringVersion = getString.slice(from: firstIndex, to: secondIndex)
            let githubVersion = Double(stringVersion!)!

            if githubVersion > localVersion {
                self.sendNotification()
            }
            
        }
        
        task.resume()
        
    }
    
    
    func sendNotification() {
        
        let checkInstallMethod = try? safeShell("brew list togglemute > /dev/null")
        
        var msgBody = "Just download the latest release"
        let btnTitle = "Go to github"
        
        if (checkInstallMethod == "") {
            msgBody = "Just run \"brew update && brew upgrade togglemute\" in your terminal to update"
        }
        
        let content = UNMutableNotificationContent()
        content.title = "toggleMute update available 🚀"
        content.body = msgBody
        content.sound = .default
        content.categoryIdentifier = "updateAvailable"
        
        let uuidString = UUID().uuidString
        let trigger = UNTimeIntervalNotificationTrigger.init(timeInterval: 3.0, repeats: false)
        let showUpdate = UNNotificationAction(identifier: "showUpdate", title: btnTitle, options: .foreground)
        let category = UNNotificationCategory(identifier: "updateAvailable", actions: [showUpdate], intentIdentifiers: [], options: .customDismissAction)
        let notificationCenter = UNUserNotificationCenter.current()
        
        notificationCenter.setNotificationCategories([category])
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)
        notificationCenter.add(request)
        
    }
    
    
    @objc func runTimedCode(){

        mainController.getCurrentVolume()
                
        if(defaults.integer(forKey: "currentSetVolume") < 5) {
            touchBarController.toggleMuteStateHard(setMute: true)
        } else {
            touchBarController.toggleMuteStateHard(setMute: false)
        }

    }
    
    
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.rightMouseUp {
            showMainController()
        } else {
            touchBarController.toggleMuteState()
        }
    }
    
    
    @objc private func showMainController() {
        
        let mainController = MainController.instantiate(with: settingsController, and: preferences)
        popoverView.contentViewController = mainController

        guard let button = statusItem.button else {
            fatalError("Couldn't find status item button.")
        }
        
        print(popoverView.isShown)
        
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
    
    
    // Add to suppress warnings when you don't want/need a result
    @discardableResult
    func safeShell(_ command: String) throws -> String {
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["--login", "-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.standardInput = nil

        try task.run()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
        
    }

    
}


func isKeyPresentInUserDefaults(key: String) -> Bool {
    
    return UserDefaults.standard.object(forKey: key) != nil
    
}


extension String {
    
    func slice(from: String, to: String) -> String? {
        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}
