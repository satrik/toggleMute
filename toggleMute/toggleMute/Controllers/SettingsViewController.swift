// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.k, modifiers: [.command, .option]))
}

class SettingsViewController: NSViewController {

    @IBOutlet var launchAtLoginCheckBox: NSButton!
    @IBOutlet weak var redMenuBarIconCheckBox: NSButton!
    @IBOutlet weak var redMenuBarBackgroundCheckBox: NSButton!
    @IBOutlet var quitButton: NSButton!
    @IBOutlet weak var shortcutSubView: NSView!
    @IBOutlet weak var versionLabel: NSTextField!
    private var preferences: Preferences!
    let defaults = UserDefaults.standard
    private var delegateController = NSApplication.shared.delegate as! AppDelegate
    private lazy var touchBarController = TouchBarController()

    func isKeyPresentInUserDefaults(key: String) -> Bool {

        return UserDefaults.standard.object(forKey: key) != nil

    }
    
    
    static func instantiate(with preferences: Preferences) -> SettingsViewController {
        
        let storyboard = NSStoryboard(name: "Controllers", bundle: nil)

        guard let settingsController = storyboard.instantiateController(withIdentifier: "SettingsController") as? SettingsViewController else {
            fatalError("Unable to find SettingsController in the storyboard.")
        }

        settingsController.preferences = preferences

        return settingsController

    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if(isKeyPresentInUserDefaults(key: "stringLocalVersion")) {
            let version = defaults.string(forKey: "stringLocalVersion") ?? "-"
            versionLabel.stringValue = "Version: \(version)"
        }
        
        launchAtLoginCheckBox.state = preferences.launchAtLoginEnabled ? .on : .off

        if(isKeyPresentInUserDefaults(key: "redMenuBarBackground")) {
            redMenuBarBackgroundCheckBox.state = defaults.bool(forKey: "redMenuBarBackground") ? .on : .off
        } else {
            redMenuBarBackgroundCheckBox.state = .off
        }
        
        if(isKeyPresentInUserDefaults(key: "redMenuBarIcon")) {
            redMenuBarIconCheckBox.state = defaults.bool(forKey: "redMenuBarIcon") ? .on : .off
        } else {
            redMenuBarIconCheckBox.state = .off
        }
        
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleMuteShortcut)

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        recorder.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        
        shortcutSubView.addSubview(recorder)
                
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        NSApp.activate(ignoringOtherApps: true)
        
    }
    
    
    @IBAction func didTouchLaunchAtLogin(_ sender: NSButton) {
    
        preferences.launchAtLoginEnabled = sender.state == .on ? true : false
        LaunchAtLogin.isEnabled = preferences.launchAtLoginEnabled

    }
    
    
    @IBAction func didTouchRedMenuBarIcon(_ sender: NSButton) {
                
        let isMuted = defaults.bool(forKey: "isMuted")
        let button = delegateController.statusItem.button

        if(sender.title == "Icon") {
            
            let checkBoxState = sender.state == .on ? true : false
            defaults.set(checkBoxState, forKey: "redMenuBarIcon")
            
            if(isMuted){
                if(checkBoxState) {
                    button?.image = touchBarController.imageMute?.tint(color: .red)
                } else {
                    button?.image = touchBarController.imageMute?.tint(color: .selectedMenuItemTextColor)
                }
            }

            
            
        } else if (sender.title == "Background") {
            
            let checkBoxState = sender.state == .on ? true : false
            defaults.set(checkBoxState, forKey: "redMenuBarBackground")
            
            if(isMuted) {
                
                if(checkBoxState) {
                    button?.layer?.backgroundColor = CGColor(red: 1.0, green: 0, blue: 0 , alpha: 1.0)
                } else {
                    button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)
                }
                
            }
            
        }

    }
    
    
    @IBAction func didTouchClose(_ sender: Any) {
        
        NSApplication.shared.terminate(nil)
        
    }
    
}
