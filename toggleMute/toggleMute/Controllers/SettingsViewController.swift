// Author: Sascha Petrik

import Cocoa
import LaunchAtLogin
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.k, modifiers: [.command, .option]))
}

class SettingsViewController: NSViewController {

    @IBOutlet var launchAtLoginCheckBox: NSButton!
    @IBOutlet var quitButton: NSButton!
    @IBOutlet weak var shortcutSubView: NSView!
    private var preferences: Preferences!

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

    @IBAction func didTouchRandom(_ sender: NSButton) {
        preferences.randomNootNootEnabled = sender.state == .on ? true : false
    }

    @IBAction func didTouchClose(_ sender: Any) {
        NSApplication.shared.terminate(nil)
    }
    
}
