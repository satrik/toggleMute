// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin

fileprivate extension NSTouchBarItem.Identifier {
    static let touchBarButtonIdentifier = NSTouchBarItem.Identifier("com.foofoo.touchbarMute")
}

class TouchBarController {
    
    private var settingsController: SettingsController!
    private var delegateController = NSApplication.shared.delegate as! AppDelegate
    
    
    let defaults = UserDefaults.standard
    var isMuted = true || false
    
    let imageUnmute = NSImage(named: NSImage.touchBarAudioInputTemplateName)
    let imageMute = NSImage(named: NSImage.touchBarAudioInputMuteTemplateName)
    var touchBarButton: NSButton?

    
    private lazy var item: NSCustomTouchBarItem = {
        let i = NSCustomTouchBarItem(identifier: .touchBarButtonIdentifier)
        return i
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
        
        if(isKeyPresentInUserDefaults(key: "isMuted")){
            isMuted = defaults.bool(forKey: "isMuted")
        } else {
            isMuted = false
        }
    
    }
    
    func isKeyPresentInUserDefaults(key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) != nil
    }
    
    @objc func toggleMuteStateObj() {
        
        toggleMuteState()

    }
    
    func setNewVolume(newValue: Int) {

       let setInputAndResetOutputVolume =
            """
            set volume input volume \(newValue)
            set currentVol to output volume of (get volume settings)
            set volume output volume currentVol
            """
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: setInputAndResetOutputVolume) {
           scriptObject.executeAndReturnError(&error)
        }
        
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

        if(!setMute && isMuted){
            defaults.set(false, forKey: "isMuted")
            button?.image = imageUnmute
            touchBarButton?.image = imageUnmute
            touchBarButton?.bezelColor = NSColor.clear
            var unmuteVal = 80
            if(isKeyPresentInUserDefaults(key: "defaultInputVol")){
                unmuteVal = defaults.integer(forKey: "defaultInputVol")
            }
            setNewVolume(newValue: unmuteVal)
        } else if(setMute && !isMuted) {
            defaults.set(true, forKey: "isMuted")
            button?.image = imageMute
            touchBarButton?.image = imageMute
            touchBarButton?.bezelColor = NSColor.red
            setNewVolume(newValue: 0)
        }
    }
}
