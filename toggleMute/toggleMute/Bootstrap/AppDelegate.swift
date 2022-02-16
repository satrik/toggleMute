// Author: Sascha Petrik

import Cocoa
import KeyboardShortcuts

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
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
        refreshTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(runTimedCode), userInfo: nil, repeats: true)
        if let button = self.statusItem.button {
            button.image = imageUnmute
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        touchBarController.configureUI()
        
        KeyboardShortcuts.onKeyDown(for: .toggleMuteShortcut) {
            self.touchBarController.toggleMuteState()
        }
        
    }

    @objc func runTimedCode(){

        mainController.getCurrentVolume()
        
        if(defaults.integer(forKey: "currentSetVolume") < 5){
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

