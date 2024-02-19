// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
    private lazy var preferences = Preferences()
    private lazy var settingsController = SettingsController()
    private lazy var mainController = MainController()
    private lazy var touchBarController = TouchBarController.instantiate(with: settingsController)
    private weak var popoverView: NSPopover?
    var refreshTimer: Timer?
    let defaults = UserDefaults.standard

    let imageUnmute = NSImage(named: NSImage.touchBarAudioInputTemplateName)
    let imageMute = NSImage(named: NSImage.touchBarAudioInputMuteTemplateName)

    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
                
        LaunchAtLogin.migrateIfNeeded()
        
        refreshTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(runTimedCode), userInfo: nil, repeats: true)
        
        if let button = self.statusItem.button {
            button.image = touchBarController.imageUnmute?.tint(color: .selectedMenuItemTextColor)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        touchBarController.configureUI()
        
        KeyboardShortcuts.onKeyDown(for: .toggleMuteShortcut) {
            self.touchBarController.toggleMuteState()
        }
        
        defaults.set(false, forKey: "updateAvailable")
        defaults.set(true, forKey: "firstStart")
        
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
                self.defaults.set(true, forKey: "updateAvailable")
            }
            
        }
        
        task.resume()
        
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
        
        guard let button = statusItem.button else {
            fatalError("Couldn't find status item button.")
        }

        guard popoverView == nil else {
            popoverView?.close()
            return
        }

        let mainController = MainController.instantiate(with: settingsController, and: preferences)

        let popoverView = NSPopover()
        popoverView.contentViewController = mainController
        popoverView.behavior = .transient
        popoverView.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        self.popoverView = popoverView

        NSApp.activate(ignoringOtherApps: true)
    }

}


func isKeyPresentInUserDefaults(key: String) -> Bool {
    
    return UserDefaults.standard.object(forKey: key) != nil
    
}


func dialogOKCancel(question: String, text: String) -> Bool {
    
    let alert = NSAlert()
    alert.messageText = question
    alert.informativeText = text
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open github")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn

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
