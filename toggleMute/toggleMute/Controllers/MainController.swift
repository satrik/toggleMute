// Author: Sascha Petrik

import Cocoa
import UserNotifications

class MainController: NSViewController, UNUserNotificationCenterDelegate {

    @IBOutlet weak var settingsButton: NSButton!
    @IBOutlet weak var openGithubButton: NSButton!
    @IBOutlet weak var inputValueLabel: NSTextField!
    @IBOutlet weak var inputValueSlider: NSSlider!
    
    private var settingsController: SettingsController!
    private var preferences: Preferences!
    private lazy var touchBarController = TouchBarController()
    private var delegateController = NSApplication.shared.delegate as! AppDelegate

    let popoverSettingsView = NSPopover()
    
    let repoUrl = URL(string: "https://github.com/satrik/toggleMute")!
    let defaults = UserDefaults.standard
    var currentSetVolume = 0
        
    static func instantiate(with settingsController: SettingsController, and preferences: Preferences) -> MainController {
        
        let storyboard = NSStoryboard(name: "Controllers", bundle: nil)
        
        guard let mainController = storyboard.instantiateController(withIdentifier: "MainController") as? MainController else {
            fatalError("Unable to find MainController in the storyboard.")
        }
        
        mainController.settingsController = settingsController
        mainController.preferences = preferences
        return mainController
        
    }

    
    func isKeyPresentInUserDefaults(key: String) -> Bool {
        
        return UserDefaults.standard.object(forKey: key) != nil
        
    }
   
    
    override func viewDidLoad() {

        super.viewDidLoad()
        setupNotifications()
                
        if(isKeyPresentInUserDefaults(key: "defaultInputVol")) {
            inputValueSlider.integerValue = defaults.integer(forKey: "defaultInputVol")
        }
        
        let val = inputValueSlider.integerValue
        let label = inputValueLabel
        label?.stringValue = String(val)
        
        getCurrentVolume()
        
    }
    
    
    // no user notifications
    private func setupNotifications() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange), name: Preferences.didChangeNotification, object: nil)
        
    }
    
    
    @objc private func preferencesDidChange() {
        // nothing to do currently
    }
    
    
    @IBAction func didChangeSlider(_ sender: Any) {
        
        guard let slider = sender as? NSSlider,
              let event = NSApplication.shared.currentEvent else { return }
        let val = slider.integerValue
        let label = inputValueLabel
        
        switch event.type {
            
        case .leftMouseDown, .rightMouseDown:
            break
            // nothing to do if drag just started
            
        case .leftMouseUp, .rightMouseUp:
            label?.stringValue = String(val)
            defaults.set(val, forKey: "defaultInputVol")
            self.touchBarController.setNewVolume(newValue: val)
            
        case .leftMouseDragged, .rightMouseDragged:
            label?.stringValue = String(val)
            
        default:
            break
        }
        
    }

    
    func getCurrentVolume() {
        
        let setInputVolume = "return input volume of (get volume settings)"
        var error: NSDictionary?
                
        if let scriptObject = NSAppleScript(source: setInputVolume) {
            
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                
                currentSetVolume = Int(outputString)!
                defaults.set(currentSetVolume, forKey: "currentSetVolume")
                
            } else if (error != nil) {
                // no error handling currently as it just works always :D
            }
            
        }
        
    }
    
    
    @IBAction func didTouchSettings(_ sender: Any) {
        
        
        let settingsController = SettingsViewController.instantiate(with: preferences)
        popoverSettingsView.contentViewController = settingsController
        popoverSettingsView.behavior = .transient
        popoverSettingsView.show(relativeTo: settingsButton.bounds, of: settingsButton, preferredEdge: .maxY)
        delegateController.eventMonitor2?.start()
    }
    
    
    @IBAction func didTouchOpenGithub(_ sender: Any) {
        
        if NSWorkspace.shared.open(repoUrl) {}
        
    }
    
    
}



extension MainController {
  
  static func createController() -> MainController {
  
    let storyboard = NSStoryboard(name: "Controllers", bundle: nil)
    let identifier = "MainController"
    
    guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? MainController else {
      
      fatalError("Why cant i find MainController? - Check Controllers.storyboard")
      
    }
    
    return viewcontroller
    
  }
  
}
