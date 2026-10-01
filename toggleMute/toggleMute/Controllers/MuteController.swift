// Author: Sascha Petrik

import Cocoa

class MuteController {
    
    private var delegateController = NSApplication.shared.delegate as! AppDelegate
    
    let defaults = UserDefaults.standard
    var isMuted = false
    var redMenuBarIconBackground = false
    var redMenuBarIcon = false
    let imageMute = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: "Mute")
    let imageUnmute = NSImage(systemSymbolName: "mic", accessibilityDescription: "Unmute")

    // Loaded once and held here — a fresh, unretained NSSound(named:) per
    // call gets deallocated by ARC as soon as the statement finishes, which
    // can cut playback short before it's audible (especially noticeable
    // when toggling quickly, since more churn means dealloc races the
    // sound more often). Keeping a persistent instance per sound avoids that.
    private let unmuteSound = NSSound(named: "Tink")
    private let muteSound = NSSound(named: "Bottle")

    // Single source of truth for "the app's red" so the menu bar icon tint
    // and the optional red background are always exactly the same color.
    static let redColor = NSColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)


    func configureUI() {
        
        if(isKeyPresentInUserDefaults(key: "isMuted")) {
            isMuted = defaults.bool(forKey: "isMuted")
        } else {
            isMuted = false
        }
                
        if(isMuted) {
            defaults.set(false, forKey: "isMuted")
            toggleMuteStateHard(setMute: true, notify: false)
        } else {
            defaults.set(true, forKey: "isMuted")
            toggleMuteStateHard(setMute: false, notify: false)
        }

        // configureUI() runs at launch with notify:false (this is a restore
        // of prior session state, not a user action — see notify's doc at
        // its call site). "Always show HUD" is an exception: it wants the
        // HUD on screen from the moment the app starts, not just after the
        // first mute/unmute.
        if(defaults.bool(forKey: "hudEnabled") && defaults.bool(forKey: "hudAlwaysVisible")) {
            let redHUD = defaults.bool(forKey: "hudRedIconEnabled")
            let deviceName = defaults.bool(forKey: "hudShowDeviceName") ? AudioInputController.deviceName() : nil
            HUDController.shared.show(muted: isMuted, sticky: true, red: redHUD, deviceName: deviceName)
        }
    
    }
    
    
    func isKeyPresentInUserDefaults(key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) != nil
    }
    
    
    func toggleMuteState() {
        toggleMuteStateHard(setMute: !isMuted)
    }
    
    
    func toggleMuteStateHard(setMute: Bool, notify: Bool = true, holdHUD: Bool = false) {
        
        let button = delegateController.statusItem.button
        isMuted = defaults.bool(forKey: "isMuted")
        redMenuBarIconBackground = defaults.bool(forKey: "redMenuBarBackground")
        redMenuBarIcon = defaults.bool(forKey: "redMenuBarIcon")
                
        if(!setMute && isMuted){

            defaults.set(false, forKey: "isMuted")
            isMuted = false

            button?.image = imageUnmute?.tint(color: .controlTextColor)

            button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)

            AudioInputController.setMuted(false)

            if notify { notifyStateChange(muted: false, holdHUD: holdHUD) }

        } else if(setMute && !isMuted) {

            defaults.set(true, forKey: "isMuted")
            isMuted = true

            button?.image = imageMute?.tint(color: .controlTextColor)
            button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)

            AudioInputController.setMuted(true, zeroVolume: defaults.bool(forKey: "muteInputVolumeEnabled"))

            if(redMenuBarIcon){
                button?.image = imageMute?.tint(color: MuteController.redColor)
            }

            if(redMenuBarIconBackground){
                button?.layer?.backgroundColor = MuteController.redColor.cgColor
            }

            if notify { notifyStateChange(muted: true, holdHUD: holdHUD) }

        }
        
    }


    func applyMuteStateToDevices() {

        let muted = defaults.bool(forKey: "isMuted")
        AudioInputController.setMuted(muted, zeroVolume: defaults.bool(forKey: "muteInputVolumeEnabled"))

    }


    // Only called from the two branches above, i.e. only on an actual state
    // change — never on the hardware-sync no-ops in syncFromHardware().
    // `holdHUD` keeps the HUD on screen without auto-dismissing, used while
    // push-to-talk is being held down.
    private func notifyStateChange(muted: Bool, holdHUD: Bool) {

        if(defaults.bool(forKey: "hudEnabled")) {
            let redHUD = defaults.bool(forKey: "hudRedIconEnabled")
            let alwaysVisible = defaults.bool(forKey: "hudAlwaysVisible")
            let deviceName = defaults.bool(forKey: "hudShowDeviceName") ? AudioInputController.deviceName() : nil
            HUDController.shared.show(muted: muted, sticky: holdHUD || alwaysVisible, red: redHUD, deviceName: deviceName)
        }

        if(defaults.bool(forKey: "soundsEnabled")) {
            let sound = muted ? muteSound : unmuteSound
            // .play() is a no-op if the same NSSound instance is already
            // playing — .stop() first forces it to restart from frame 0,
            // so rapid back-to-back toggles each get an audible click
            // instead of the retrigger being silently ignored.
            sound?.stop()
            sound?.play()
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
