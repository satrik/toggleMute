import Foundation
import LaunchAtLogin

struct Preferences {

    static let didChangeNotification = Notification.Name("com.toggleMute.PreferencesChanged")

    private var defaults = UserDefaults.standard

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    var launchAtLoginEnabled: Bool {
        get { LaunchAtLogin.isEnabled }
        set {
            LaunchAtLogin.isEnabled = newValue
            didChange()
        }
    }

    var pushToTalkEnabled: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var hudEnabled: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var hudAlwaysVisible: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var hudRedIconEnabled: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var hudShowDeviceName: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var muteInputVolumeEnabled: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    /// A device UID, or AudioInputController.followDefault / .allMicrophones / .allInputs.
    var inputDeviceSelection: String {
        get { defaults.string(forKey: #function) ?? AudioInputController.followDefault }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    /// Display name of the selected device, shown while it is disconnected.
    var inputDeviceName: String? {
        get { defaults.string(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }

    var soundsEnabled: Bool {
        get { defaults.bool(forKey: #function) }
        set {
            defaults.set(newValue, forKey: #function)
            didChange()
        }
    }
}
