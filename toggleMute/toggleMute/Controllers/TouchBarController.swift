// Author: Sascha Petrik

import Cocoa

fileprivate extension NSTouchBarItem.Identifier {
    static let touchBarButtonIdentifier = NSTouchBarItem.Identifier("com.touchbar.toggleMute")
}


class TouchBarController {
    
    private var settingsController: SettingsController!
    private var delegateController = NSApplication.shared.delegate as! AppDelegate
    
    let defaults = UserDefaults.standard
    var isMuted = true || false
    var redMenuBarIconBackground = true || false
    var redMenuBarIcon = true || false
    let imageUnmute = NSImage(named: NSImage.touchBarAudioInputTemplateName)
    let imageMute = NSImage(named: NSImage.touchBarAudioInputMuteTemplateName)
    var touchBarButton: NSButton?

    
    private lazy var item: NSCustomTouchBarItem = {
        
        let touchbarButtonItem = NSCustomTouchBarItem(identifier: .touchBarButtonIdentifier)
        return touchbarButtonItem
        
    }()


    static func instantiate(with settingsController: SettingsController) -> TouchBarController {
        
        let touchBarController = TouchBarController()
        touchBarController.settingsController = settingsController
        return touchBarController
        
    }
    
    
    func configureUI() {
        
        touchBarButton = NSButton(image: imageUnmute!, target: self, action: #selector(toggleMuteStateObj))
        item.view = touchBarButton!
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.touchBarButtonIdentifier, true)
        
        if(isKeyPresentInUserDefaults(key: "isMuted")) {
            isMuted = defaults.bool(forKey: "isMuted")
        } else {
            isMuted = false
        }
                
        if(isMuted) {
            defaults.set(false, forKey: "isMuted")
            toggleMuteStateHard(setMute: true)
        } else {
            defaults.set(true, forKey: "isMuted")
            toggleMuteStateHard(setMute: false)
        }
    
    }
    
    
    func isKeyPresentInUserDefaults(key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) != nil
    }
    
    
    @objc func toggleMuteStateObj() {
        toggleMuteState()
    }
    
    
    func setNewVolume(newValue: Int) {
        // Drives the *gain* of the default input device (used when restoring the
        // user's preferred input volume on unmute, and when the slider moves).
        // AppleScript's `set volume input volume` is a no-op on Aggregate Devices,
        // so go through CoreAudio.
        let clamped = max(0, min(100, newValue))
        AudioInputController.setVolume(Float32(clamped) / 100.0)
    }
    

    func toggleMuteState() {

        if(touchBarButton?.image == imageMute){
            toggleMuteStateHard(setMute: false)
        } else {
            toggleMuteStateHard(setMute: true)
        }
    }
    
    
    func toggleMuteStateHard(setMute: Bool) {
        
        let button = delegateController.statusItem.button
        isMuted = defaults.bool(forKey: "isMuted")
        redMenuBarIconBackground = defaults.bool(forKey: "redMenuBarBackground")
        redMenuBarIcon = defaults.bool(forKey: "redMenuBarIcon")
                
        if(!setMute && isMuted){

            defaults.set(false, forKey: "isMuted")

            button?.image = imageUnmute?.tint(color: .alternateSelectedControlTextColor)

            button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)
            touchBarButton?.image = imageUnmute
            touchBarButton?.bezelColor = NSColor.clear

            AudioInputController.setMuted(false)

            var unmuteVal = 80
            if(isKeyPresentInUserDefaults(key: "defaultInputVol")){
                unmuteVal = defaults.integer(forKey: "defaultInputVol")
            }
            setNewVolume(newValue: unmuteVal)

        } else if(setMute && !isMuted) {

            defaults.set(true, forKey: "isMuted")

            button?.image = imageMute?.tint(color: .selectedMenuItemTextColor)
            button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)

            touchBarButton?.image = imageMute
            touchBarButton?.bezelColor = NSColor.red

            AudioInputController.setMuted(true)

            if(redMenuBarIcon){
                button?.image = imageMute?.tint(color: .red)
            }

            if(redMenuBarIconBackground){
                button?.layer?.backgroundColor = CGColor(red: 1.0, green: 0, blue: 0 , alpha: 1.0)
            }

        }
        
    }
    
}


extension NSImage {
    
    func tint(color: NSColor) -> NSImage {
    
        return NSImage(size: size, flipped: false) { (rect) -> Bool in
            color.set()
            rect.fill()
            self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .destinationIn, fraction: 1.0)
            return true
        }
        
    }
    
}
