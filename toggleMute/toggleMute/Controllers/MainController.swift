// Author: Sascha Petrik

import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.k, modifiers: [.command, .option]))
}


/// A plain, label-styled NSTextField that's still clickable — used for the
/// version number, which should look exactly like ordinary text (no
/// underline, no color change) but open a link when clicked, with a
/// pointing-hand cursor on hover to signal that it's interactive.
final class ClickableLabel: NSTextField {

    var onClick: (() -> Void)?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

}


/// Marks a position on the track with a dot, and tints the track red while
/// muted; the input volume slider uses them for the volume unmuting restores
/// and for the mute state.
final class MarkerSliderCell: NSSliderCell {

    var marker: Double?
    var muted = false
    private(set) var isTracking = false

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        isTracking = true
        return super.startTracking(at: startPoint, in: controlView)
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        isTracking = false
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        // Reports the release, which a continuous slider may send before this.
        (controlView as? NSControl)?.sendAction(action, to: target)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        if muted {
            let radius = rect.height / 2
            NSColor.systemRed.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            var filled = rect
            filled.size.width = knobRect(flipped: flipped).midX - rect.minX
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
        } else {
            super.drawBar(inside: rect, flipped: flipped)
        }
        guard let marker = marker else { return }
        let knobWidth = knobRect(flipped: flipped).width
        let x = rect.minX + knobWidth / 2 + (rect.width - knobWidth) * CGFloat(marker)
        (muted ? NSColor.systemRed : NSColor.secondaryLabelColor).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3, y: rect.midY - 3, width: 6, height: 6)).fill()
    }

}


/// The single popover shown when clicking the menu bar icon (or right-
/// clicking it). Combines volume, all toggles, the shortcut recorder, and
/// the footer actions in one native-feeling view instead of a separate
/// nested settings popover.
class MainController: NSViewController {

    // Input device
    @IBOutlet weak var inputDevicePopUp: NSPopUpButton!
    @IBOutlet weak var inputVolumeLabel: NSTextField!
    @IBOutlet weak var inputVolumeSlider: NSSlider!

    // General toggles
    @IBOutlet var launchAtLoginCheckBox: NSButton!
    @IBOutlet weak var pushToTalkCheckBox: NSButton!
    @IBOutlet weak var playSoundsCheckBox: NSButton!
    @IBOutlet weak var showHUDCheckBox: NSButton!
    @IBOutlet weak var hudAlwaysVisibleCheckBox: NSButton!
    @IBOutlet weak var redHUDIconCheckBox: NSButton!
    @IBOutlet weak var showDeviceNameCheckBox: NSButton!
    @IBOutlet weak var muteInputVolumeCheckBox: NSButton!

    // Red menu bar
    @IBOutlet weak var redMenuBarIconCheckBox: NSButton!
    @IBOutlet weak var redMenuBarBackgroundCheckBox: NSButton!

    // Shortcut
    @IBOutlet weak var shortcutSubView: NSView!

    // Footer
    @IBOutlet var quitButton: NSButton!
    @IBOutlet weak var versionPrefixLabel: NSTextField!
    @IBOutlet weak var versionNumberLabel: ClickableLabel!

    private var preferences: Preferences!
    private lazy var muteController = MuteController()
    private var delegateController = NSApplication.shared.delegate as! AppDelegate

    let repoUrl = URL(string: "https://github.com/satrik/toggleMute")!
    let defaults = UserDefaults.standard

    static func instantiate(with preferences: Preferences) -> MainController {

        let storyboard = NSStoryboard(name: "Controllers", bundle: nil)

        guard let mainController = storyboard.instantiateController(withIdentifier: "MainController") as? MainController else {
            fatalError("Unable to find MainController in the storyboard.")
        }

        mainController.preferences = preferences
        return mainController

    }


    func isKeyPresentInUserDefaults(key: String) -> Bool {

        return UserDefaults.standard.object(forKey: key) != nil

    }


    override func viewDidLoad() {

        super.viewDidLoad()
        setupNotifications()

        setupInputDevicePopUp()
        updateInputVolume()

        // Version. Only the number is clickable — see ClickableLabel. The
        // two labels are centered together as a pair at runtime since the
        // version string's width varies between builds.
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "-"
        versionNumberLabel.stringValue = version
        versionNumberLabel.onClick = { [weak self] in
            guard let self = self else { return }
            if NSWorkspace.shared.open(self.repoUrl) {}
        }
        layoutVersionRow()

        // General toggles
        launchAtLoginCheckBox.state = preferences.launchAtLoginEnabled ? .on : .off
        pushToTalkCheckBox.state = preferences.pushToTalkEnabled ? .on : .off
        playSoundsCheckBox.state = preferences.soundsEnabled ? .on : .off
        showHUDCheckBox.state = preferences.hudEnabled ? .on : .off
        updateHUDOptionsEnabled()
        hudAlwaysVisibleCheckBox.state = preferences.hudAlwaysVisible ? .on : .off
        redHUDIconCheckBox.state = preferences.hudRedIconEnabled ? .on : .off
        showDeviceNameCheckBox.state = preferences.hudShowDeviceName ? .on : .off
        muteInputVolumeCheckBox.state = preferences.muteInputVolumeEnabled ? .on : .off

        // Red menu bar
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

        // Shortcut recorder. The min-width/min-height-only constraints used
        // previously let the recorder fall back to its own intrinsic size
        // (much narrower than shortcutSubView) at runtime, even though the
        // empty placeholder view looked full-width in the Interface Builder
        // canvas. Pinning all four edges makes it actually fill its
        // container, matching every other row's width.
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleMuteShortcut)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        shortcutSubView.addSubview(recorder)
        recorder.toolTip = shortcutSubView.toolTip
        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: shortcutSubView.leadingAnchor),
            recorder.trailingAnchor.constraint(equalTo: shortcutSubView.trailingAnchor),
            recorder.topAnchor.constraint(equalTo: shortcutSubView.topAnchor),
            recorder.bottomAnchor.constraint(equalTo: shortcutSubView.bottomAnchor)
        ])

    }


    override func viewDidDisappear() {

        super.viewDidDisappear()
        NSApp.activate(ignoringOtherApps: true)

    }


    // no user notifications
    private func setupNotifications() {

        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange), name: Preferences.didChangeNotification, object: nil)

    }


    @objc private func preferencesDidChange() {
        // nothing to do currently
    }


    /// Centers "Version:" and the clickable version number together as one
    /// unit within the row's original bounds (the row itself never moves;
    /// only how the two labels split it changes with version string length).
    private func layoutVersionRow() {

        let rowX: CGFloat = 20
        let rowWidth: CGFloat = 190
        let spacing: CGFloat = 4

        versionPrefixLabel.sizeToFit()
        versionNumberLabel.sizeToFit()

        let totalWidth = versionPrefixLabel.frame.width + spacing + versionNumberLabel.frame.width
        let startX = rowX + max(0, (rowWidth - totalWidth) / 2)

        var prefixFrame = versionPrefixLabel.frame
        prefixFrame.origin.x = startX
        versionPrefixLabel.frame = prefixFrame

        var numberFrame = versionNumberLabel.frame
        numberFrame.origin.x = startX + versionPrefixLabel.frame.width + spacing
        numberFrame.origin.y = versionPrefixLabel.frame.origin.y
        versionNumberLabel.frame = numberFrame

    }


    /// The controlled volume as last read or written; reading it mid-drag would wait for the writes.
    private var inputVolume: Float32?


    /// Volume of the selected device, or of the default input in the "all"
    /// modes.
    /// Takes the slider value while dragging, as the write lands later.
    func updateInputVolume(_ volume: Float32? = AudioInputController.volume()) {

        inputVolume = volume
        let cell = inputVolumeSlider.cell as? MarkerSliderCell
        // Hardware rounds volumes to its own steps; reading them back mid-drag makes the knob jitter.
        if cell?.isTracking != true { inputVolumeSlider.doubleValue = Double(volume ?? 0) }
        let atZero = volume.map { $0 < AudioInputController.nearZeroVolume } ?? false
        let muted = delegateController.muteController.isMuted
        inputVolumeSlider.isEnabled = volume != nil
        cell?.marker = atZero ? AudioInputController.restoreVolume().map(Double.init) : nil
        cell?.muted = muted
        inputVolumeSlider.needsDisplay = true
        inputVolumeLabel.stringValue = "Input volume: " + (volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "not adjustable") + (muted ? " (muted)" : "")

    }


    // Sets every controlled device, so the "all" modes share one level.
    @IBAction func didChangeInputVolume(_ sender: NSSlider) {

        let nearZero = AudioInputController.nearZeroVolume
        // The state sync reads anything below it as muted.
        if sender.doubleValue < Double(nearZero) { sender.doubleValue = 0 }
        let volume = Float32(sender.doubleValue)
        let dragging = (sender.cell as? MarkerSliderCell)?.isTracking == true
        let muteController = delegateController.muteController
        // Raising it from 0 would go live past push to talk, so the drag
        // only picks the volume push to talk unmutes with.
        if muteController.isMuted && preferences.pushToTalkEnabled && preferences.muteInputVolumeEnabled {
            guard !dragging else { return }
            // Restoring a volume below it would mute again.
            if volume >= nearZero { AudioInputController.setRestoreVolume(volume) }
            updateInputVolume()
            return
        }
        let raisedFromZero = (inputVolume ?? 1) < nearZero && volume >= nearZero
        AudioInputController.setVolume(volume, dragging: dragging)
        // Raising a muted mic from 0 unmutes it.
        if raisedFromZero && muteController.isMuted { muteController.toggleMuteStateHard(setMute: false) }
        updateInputVolume(volume)

    }


    private func setupInputDevicePopUp() {

        let menu = inputDevicePopUp.menu!
        menu.removeAllItems()

        func addItem(_ title: String, _ selection: String) {
            let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.representedObject = selection
        }

        addItem("Default input", AudioInputController.followDefault)
        addItem("All microphones", AudioInputController.allMicrophones)
        addItem("All inputs (incl. virtual)", AudioInputController.allInputs)
        menu.addItem(.separator())
        let devices = AudioInputController.inputDevices()
        for device in devices {
            addItem(device.isVirtual ? "\(device.name) (virtual)" : device.name, device.uid)
        }

        let selection = preferences.inputDeviceSelection
        if AudioInputController.isSpecificDevice(selection) && !devices.contains(where: { $0.uid == selection }) {
            addItem("\(preferences.inputDeviceName ?? "Device") (disconnected, using default)", selection)
        }
        inputDevicePopUp.selectItem(at: menu.items.firstIndex { $0.representedObject as? String == selection } ?? 0)

    }


    @IBAction func didChangeInputDevice(_ sender: NSPopUpButton) {

        guard let selection = sender.selectedItem?.representedObject as? String,
              selection != preferences.inputDeviceSelection else { return }

        // Unmute the devices that stop being controlled
        let muteController = delegateController.muteController
        let wasMuted = muteController.isMuted
        if(wasMuted) { muteController.toggleMuteStateHard(setMute: false, notify: false) }
        preferences.inputDeviceName = sender.selectedItem?.title
        preferences.inputDeviceSelection = selection
        AudioInputController.refreshWatchedDevices()
        if(wasMuted) { muteController.toggleMuteStateHard(setMute: true, notify: false) }
        delegateController.inputDevicesChanged()

        if(preferences.hudEnabled && preferences.hudAlwaysVisible) {
            refreshAlwaysVisibleHUD()
        }

    }


    @IBAction func didTouchLaunchAtLogin(_ sender: NSButton) {

        preferences.launchAtLoginEnabled = sender.state == .on ? true : false

    }


    @IBAction func didTouchPushToTalk(_ sender: NSButton) {

        let enabled = sender.state == .on
        preferences.pushToTalkEnabled = enabled

        if(enabled) {
            // Push-to-talk's resting state is muted; the mic only goes live
            // while the shortcut or menu bar icon is held down. Route this
            // through AppDelegate's single MuteController instance so its
            // in-memory isMuted stays in sync with the one press/release uses.
            delegateController.muteController.toggleMuteStateHard(setMute: true)
        }
        updateInputVolume()

    }


    @IBAction func didTouchPlaySounds(_ sender: NSButton) {

        preferences.soundsEnabled = sender.state == .on

    }


    @IBAction func didTouchShowHUD(_ sender: NSButton) {

        let enabled = sender.state == .on
        preferences.hudEnabled = enabled
        updateHUDOptionsEnabled()

        if(!enabled) {
            HUDController.shared.hide()
        } else {
            HUDController.shared.requestAccessibilityPermissionIfNeeded()
            if(preferences.hudAlwaysVisible) {
                refreshAlwaysVisibleHUD()
            }
        }

    }


    private func updateHUDOptionsEnabled() {

        for checkBox in [hudAlwaysVisibleCheckBox, showDeviceNameCheckBox, redHUDIconCheckBox] {
            checkBox?.isEnabled = preferences.hudEnabled
        }

    }


    @IBAction func didTouchHudAlwaysVisible(_ sender: NSButton) {

        let enabled = sender.state == .on
        preferences.hudAlwaysVisible = enabled

        if(enabled) {
            if(preferences.hudEnabled) {
                refreshAlwaysVisibleHUD()
            }
        } else {
            HUDController.shared.hide()
        }

    }


    @IBAction func didTouchRedHUDIcon(_ sender: NSButton) {

        preferences.hudRedIconEnabled = sender.state == .on

        if(preferences.hudEnabled && preferences.hudAlwaysVisible) {
            refreshAlwaysVisibleHUD()
        }

    }


    @IBAction func didTouchShowDeviceName(_ sender: NSButton) {

        preferences.hudShowDeviceName = sender.state == .on

        if(preferences.hudEnabled && preferences.hudAlwaysVisible) {
            refreshAlwaysVisibleHUD()
        }

    }


    // Re-shows the permanently-visible HUD with current settings applied —
    // used whenever a setting that affects its appearance changes while
    // "Always show HUD" is already active, so the change is reflected
    // immediately instead of only on the next mute/unmute.
    private func refreshAlwaysVisibleHUD() {

        let deviceName = preferences.hudShowDeviceName ? AudioInputController.deviceName() : nil
        HUDController.shared.show(muted: defaults.bool(forKey: "isMuted"), sticky: true, red: preferences.hudRedIconEnabled, deviceName: deviceName)

    }


    @IBAction func didTouchMuteInputVolume(_ sender: NSButton) {

        preferences.muteInputVolumeEnabled = sender.state == .on
        updateInputVolume()
        guard delegateController.muteController.isMuted else { return }
        if preferences.muteInputVolumeEnabled {
            AudioInputController.setMuted(true, zeroVolume: true)
        } else {
            AudioInputController.restoreZeroedVolumes()
        }

    }


    @IBAction func didTouchRedMenuBarIcon(_ sender: NSButton) {

        let isMuted = defaults.bool(forKey: "isMuted")
        let button = delegateController.statusItem.button

        let checkBoxState = sender.state == .on ? true : false
        defaults.set(checkBoxState, forKey: "redMenuBarIcon")

        if(isMuted){
            if(checkBoxState) {
                button?.image = muteController.imageMute?.tint(color: MuteController.redColor)
            } else {
                button?.image = muteController.imageMute?.tint(color: .selectedMenuItemTextColor)
            }
        }

    }


    @IBAction func didTouchRedMenuBarBackground(_ sender: NSButton) {

        let isMuted = defaults.bool(forKey: "isMuted")
        let button = delegateController.statusItem.button

        let checkBoxState = sender.state == .on ? true : false
        defaults.set(checkBoxState, forKey: "redMenuBarBackground")

        if(isMuted) {
            if(checkBoxState) {
                button?.layer?.backgroundColor = MuteController.redColor.cgColor
            } else {
                button?.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0 , alpha: 0)
            }
        }

    }


    @IBAction func didTouchClose(_ sender: Any) {

        NSApplication.shared.terminate(nil)

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
