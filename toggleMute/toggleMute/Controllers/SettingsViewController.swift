// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.k, modifiers: [.command, .option]))
}

class SettingsViewController: NSViewController {

    @IBOutlet var launchAtLoginCheckBox: NSButton!
    @IBOutlet var redMenuBarCheckBox: NSButton!
    @IBOutlet var quitButton: NSButton!
    @IBOutlet weak var shortcutSubView: NSView!
    private var preferences: Preferences!
    let defaults = UserDefaults.standard
    private var delegateController = NSApplication.shared.delegate as! AppDelegate

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

        launchAtLoginCheckBox.state = preferences.launchAtLoginEnabled ? .on : .off
        launchAtLoginCheckBox.title = NSLocalizedString("launchAtLogin", comment: "")
        
        if(isKeyPresentInUserDefaults(key: "redMenuBarIcon")) {
            redMenuBarCheckBox.state = defaults.bool(forKey: "redMenuBarIcon") ? .on : .off
        } else {
            redMenuBarCheckBox.state = .off
        }
        
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleMuteShortcut)
        shortcutSubView.addSubview(recorder)
        
        quitButton.title = NSLocalizedString("quit", comment: "")
        
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
        
        let checkBoxState = sender.state == .on ? true : false
        let isMuted = defaults.bool(forKey: "isMuted")
        defaults.set(checkBoxState, forKey: "redMenuBarIcon")

        if(checkBoxState && isMuted) {
            delegateController.statusItem.button?.layer?.backgroundColor = CGColor(red: 0.75, green: 0, blue: 0 , alpha: 0.75)
        } else {
            delegateController.statusItem.button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)
        }
        
    }

    @IBAction func didTouchClose(_ sender: Any) {
        NSApplication.shared.terminate(nil)
    }
    
}
