// Author: Sascha Petrik

import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.k, modifiers: [.command, .option]))
}


/// Audio state shown in the popover. Refreshed by AppDelegate from the
/// CoreAudio listeners, so the popover follows changes made elsewhere.
final class InputState: ObservableObject {

    @Published private(set) var volume: Float32?
    @Published private(set) var restoreVolume: Float32?
    @Published private(set) var muted = false
    @Published private(set) var devices: [(uid: String, name: String, isVirtual: Bool)] = []

    /// The volume being dragged to. Shown over the hardware volume, which
    /// rounds to its own steps and would make the knob and label jitter.
    @Published private(set) var draggedVolume: Float32?

    var shownVolume: Float32? { draggedVolume ?? volume }

    func refresh() {
        volume = AudioInputController.volume()
        restoreVolume = AudioInputController.restoreVolume()
        muted = UserDefaults.standard.bool(forKey: "isMuted")
    }

    /// Shows the volume right away; the write reaches the hardware later.
    func setVolume(_ volume: Float32, dragging: Bool) {
        AudioInputController.setVolume(volume, dragging: dragging)
        draggedVolume = dragging ? volume : nil
        self.volume = volume
    }

    /// Shows the knob at the volume while dragging, but sets it as the
    /// volume unmuting restores on release, leaving the hardware alone.
    func setRestoreVolume(_ volume: Float32, dragging: Bool) {
        draggedVolume = dragging ? volume : nil
        // Restoring a volume below it would mute again.
        guard !dragging && volume >= AudioInputController.nearZeroVolume else { return }
        AudioInputController.setRestoreVolume(volume)
        restoreVolume = volume
    }

    func refreshDevices() {
        devices = AudioInputController.inputDevices()
        refresh()
    }

}


/// The single popover shown when right-clicking the menu bar icon.
final class MainController: NSHostingController<SettingsView> {

    init(state: InputState) {
        super.init(rootView: SettingsView(state: state))
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The popover focuses the first text field, the shortcut recorder,
        // which would grab the next key press as a new shortcut.
        view.window?.makeFirstResponder(nil)
    }

}


struct SettingsView: View {

    @ObservedObject var state: InputState

    @AppStorage("inputDeviceSelection") private var selection = AudioInputController.followDefault
    @AppStorage("inputDeviceName") private var selectionName: String?
    @AppStorage("pushToTalkEnabled") private var pushToTalk = false
    @AppStorage("muteInputVolumeEnabled") private var zeroVolume = false
    @AppStorage("hudEnabled") private var hudEnabled = false
    @AppStorage("hudAlwaysVisible") private var hudAlwaysVisible = false
    @AppStorage("hudShowDeviceName") private var hudShowDeviceName = false
    @AppStorage("hudRedIconEnabled") private var hudRedIcon = false
    @AppStorage("redMenuBarIcon") private var redMenuBarIcon = false
    @AppStorage("redMenuBarBackground") private var redMenuBarBackground = false
    @AppStorage("soundsEnabled") private var sounds = false

    private var delegate: AppDelegate { NSApplication.shared.delegate as! AppDelegate }
    private let repoUrl = URL(string: "https://github.com/satrik/toggleMute")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            section("Microphone") {
                PopUpPicker(items: deviceItems, selection: deviceSelection)
                    .help("Which microphones to mute and unmute. Default input follows the system setting.")

                HStack(spacing: 6) {
                    // As wide as a checkbox, so the icon centers above the ones below
                    Image(systemName: state.muted ? "mic.slash.fill" : "mic.fill")
                        .foregroundColor(state.muted ? .red : .secondary)
                        .frame(width: 16)
                    VolumeSlider(volume: state.shownVolume, restoreVolume: state.restoreVolume, muted: state.muted, onChange: setVolume)
                        .disabled(state.shownVolume == nil)
                    Text(state.shownVolume.map { "\(Int(($0 * 100).rounded()))%" } ?? "-")
                        .font(.system(size: 11))
                        .foregroundColor(state.muted ? .red : .secondary)
                        .frame(width: 30)
                }
                .padding(.vertical, 4)
                .help("Input volume of the selected microphone.")

                Toggle("Push to talk", isOn: $pushToTalk)
                    .help("Muted by default. Holding the shortcut or the menu bar icon unmutes until released.")
                Toggle("Set Input Volume to 0", isOn: $zeroVolume)
                    .help("Also sets the input volume to 0 when muting, for apps that ignore the mute. Unmuting restores the previous volume.")
            }

            section("HUD") {
                Toggle("Enabled", isOn: $hudEnabled)
                    .help("Shows an on-screen indicator when muting or unmuting.")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Always show", isOn: $hudAlwaysVisible)
                        .help("Keeps the indicator on screen instead of hiding it after a moment.")
                    Toggle("Show device name", isOn: $hudShowDeviceName)
                        .help("Shows the name of the microphone next to the indicator.")
                    Toggle("Red icon", isOn: $hudRedIcon)
                        .help("Shows the indicator icon in red while muted.")
                }
                .padding(.leading, 18)
                .disabled(!hudEnabled)
            }

            section("Menu bar when muted") {
                MenuBarStylePicker(style: menuBarStyle)
            }

            section("General") {
                Toggle("Play sounds", isOn: $sounds)
                    .help("Plays a sound when muting and unmuting.")
                LaunchAtLogin.Toggle()
                    .help("Starts toggleMute when logging in.")
            }

            section("Keyboard shortcut") {
                ShortcutRecorder()
                    // The field draws its border 1pt outside its frame, above and below
                    .padding(.vertical, 1)
                    .help("Shortcut that toggles the mute, or unmutes while held with push to talk.")
            }

            Divider()
            HStack {
                footer
                Spacer()
                QuitButton()
                    .frame(width: 30, height: 30)
                    .help("Quit toggleMute")
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 230)
        .onChange(of: pushToTalk) { enabled in
            // Push to talk rests muted; the mic only goes live while held.
            if enabled { delegate.muteController.toggleMuteStateHard(setMute: true) }
        }
        .onChange(of: zeroVolume) { enabled in
            guard delegate.muteController.isMuted else { return }
            if enabled { AudioInputController.setMuted(true, zeroVolume: true) } else { AudioInputController.restoreZeroedVolumes() }
            state.refresh()
        }
        .onChange(of: hudEnabled) { enabled in
            if enabled {
                HUDController.shared.requestAccessibilityPermissionIfNeeded()
                refreshAlwaysVisibleHUD()
            } else {
                HUDController.shared.hide()
            }
        }
        .onChange(of: hudAlwaysVisible) { enabled in
            if enabled { refreshAlwaysVisibleHUD() } else { HUDController.shared.hide() }
        }
        .onChange(of: hudShowDeviceName) { _ in refreshAlwaysVisibleHUD() }
        .onChange(of: hudRedIcon) { _ in refreshAlwaysVisibleHUD() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Version")
                Button((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "-") {
                    NSWorkspace.shared.open(repoUrl)
                }
                .buttonStyle(.plain)
                .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            HStack(spacing: 4) {
                Text("Made with")
                Image(systemName: "heart.fill").foregroundColor(.accentColor)
                Text("by satrik")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private var deviceItems: [PopUpPicker.Item?] {
        var items: [PopUpPicker.Item?] = [
            ("Default input", AudioInputController.followDefault),
            ("All microphones", AudioInputController.allMicrophones),
            ("All inputs (incl. virtual)", AudioInputController.allInputs),
            nil,
        ]
        items += state.devices.map { ($0.isVirtual ? "\($0.name) (virtual)" : $0.name, $0.uid) }
        if AudioInputController.isSpecificDevice(selection) && !state.devices.contains(where: { $0.uid == selection }) {
            items.append(("\(selectionName ?? "Device") (disconnected, using default)", selection))
        }
        return items
    }

    // Sets every controlled device, so the "all" modes share one level.
    private func setVolume(_ volume: Float32, dragging: Bool) {
        // Raising it from 0 would go live past push to talk, so the drag
        // only picks the volume push to talk unmutes with.
        if state.muted && pushToTalk && zeroVolume {
            state.setRestoreVolume(volume, dragging: dragging)
            return
        }
        let nearZero = AudioInputController.nearZeroVolume
        let raisedFromZero = (state.volume ?? 1) < nearZero && volume >= nearZero
        state.setVolume(volume, dragging: dragging)
        // Raising a muted mic from 0 unmutes it.
        let muteController = delegate.muteController
        if raisedFromZero && muteController.isMuted { muteController.toggleMuteStateHard(setMute: false) }
    }

    private var deviceSelection: Binding<String> {
        Binding(get: { selection }, set: { newSelection in
            guard newSelection != selection else { return }
            selectionName = state.devices.first { $0.uid == newSelection }?.name
            selection = newSelection
            AudioInputController.refreshWatchedDevices()
            delegate.inputDevicesChanged()
            refreshAlwaysVisibleHUD()
        })
    }

    enum MenuBarStyle: Int { case normal, redIcon, redBackground }

    // One style backed by the two stored flags
    private var menuBarStyle: Binding<MenuBarStyle> {
        Binding(get: {
            redMenuBarBackground ? .redBackground : redMenuBarIcon ? .redIcon : .normal
        }, set: { style in
            redMenuBarIcon = style == .redIcon
            redMenuBarBackground = style == .redBackground
            delegate.muteController.updateMenuBarIcon()
        })
    }

    // Re-shows the permanently visible HUD so a changed setting shows immediately
    private func refreshAlwaysVisibleHUD() {
        guard hudEnabled && hudAlwaysVisible else { return }
        let deviceName = hudShowDeviceName ? AudioInputController.deviceName() : nil
        HUDController.shared.show(muted: state.muted, sticky: true, red: hudRedIcon, deviceName: deviceName)
    }

}


struct ShortcutRecorder: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleMuteShortcut)
        recorder.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return recorder
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {}
}

struct PopUpPicker: NSViewRepresentable {

    /// nil item is separator.
    typealias Item = (title: String, tag: String)

    var items: [Item?]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        popUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.changed(_:))
        return popUp
    }

    func updateNSView(_ popUp: NSPopUpButton, context: Context) {
        context.coordinator.onChange = { selection = $0 }
        // Menu items directly, since addItem(withTitle:) drops duplicate
        // titles such as two identically named microphones.
        popUp.removeAllItems()
        for item in items {
            guard let item = item else { popUp.menu?.addItem(.separator()); continue }
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.representedObject = item.tag
            popUp.menu?.addItem(menuItem)
        }
        popUp.selectItem(at: popUp.itemArray.firstIndex { $0.representedObject as? String == selection } ?? -1)
    }

    final class Coordinator: NSObject {
        var onChange: ((String) -> Void)?
        @objc func changed(_ sender: NSPopUpButton) {
            if let tag = sender.selectedItem?.representedObject as? String { onChange?(tag) }
        }
    }

}

/// Segments showing the muted menu bar icon in each style.
/// AppKit, since SwiftUI segmented picker does not stretch image segments.
struct MenuBarStylePicker: NSViewRepresentable {

    @Binding var style: SettingsView.MenuBarStyle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let icon = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: nil)!
        // Same canvas for every segment, so all icons sit at the same spot.
        func segmentImage(_ color: NSColor, background: NSColor? = nil) -> NSImage {
            // Tinted via sourceAtop, since tint(color:) leaves a stripe where
            // the symbol does not cover its whole frame.
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            // 16pt high, the most a segment shows unscaled; scaling shifts
            // the icon off the middle of the background.
            return NSImage(size: NSSize(width: 26, height: 16), flipped: false) { rect in
                if let background = background {
                    background.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
                }
                tinted.draw(at: NSPoint(x: (rect.midX - icon.size.width / 2).rounded(), y: (rect.midY - icon.size.height / 2).rounded()),
                            from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
        }
        let segments = [
            (segmentImage(.controlTextColor), "Normal icon"),
            (segmentImage(MuteController.redColor), "Red icon"),
            (segmentImage(.white, background: MuteController.redColor), "Red background"),
        ]
        let control = NSSegmentedControl(images: segments.map { $0.0 }, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        for (index, segment) in segments.enumerated() {
            segment.0.accessibilityDescription = segment.1
            control.setToolTip(segment.1 + " while muted.", forSegment: index)
        }
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onChange = { style = $0 }
        control.selectedSegment = style.rawValue
    }

    final class Coordinator: NSObject {
        var onChange: ((SettingsView.MenuBarStyle) -> Void)?
        @objc func changed(_ sender: NSSegmentedControl) {
            SettingsView.MenuBarStyle(rawValue: sender.selectedSegment).map { onChange?($0) }
        }
    }

}

/// Square button with a red power icon.
/// AppKit, since SwiftUI bordered button keeps its side padding and fixed height.
struct QuitButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let symbol = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")!
        let icon = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.systemRed.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let button = NSButton(image: icon, target: NSApp, action: #selector(NSApplication.terminate(_:)))
        // Push buttons have a fixed height; this bezel takes any size.
        button.bezelStyle = .regularSquare
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}
}

/// AppKit slider, since SwiftUI cannot draw the restore marker or a red track on macOS 11.
struct VolumeSlider: NSViewRepresentable {

    var volume: Float32?
    var restoreVolume: Float32?
    var muted: Bool
    var onChange: (_ volume: Float32, _ dragging: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = MarkerSliderCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        let cell = slider.cell as? MarkerSliderCell
        slider.doubleValue = Double(volume ?? 0)
        let atZero = volume.map { $0 < AudioInputController.nearZeroVolume } ?? false
        cell?.marker = atZero ? restoreVolume.map(Double.init) : nil
        cell?.muted = muted
        slider.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var onChange: ((Float32, Bool) -> Void)?
        @objc func changed(_ sender: NSSlider) {
            // The state sync reads anything below it as muted.
            if sender.doubleValue < Double(AudioInputController.nearZeroVolume) { sender.doubleValue = 0 }
            onChange?(Float32(sender.doubleValue), (sender.cell as? MarkerSliderCell)?.isTracking == true)
        }
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
        // Spans the whole track rather than the knobs travel, which stops
        // half a knob short of each end and makes 100% look like 90%.
        let x = rect.minX + 3 + (rect.width - 6) * CGFloat(marker)
        (muted ? NSColor.systemRed : NSColor.secondaryLabelColor).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3, y: rect.midY - 3, width: 6, height: 6)).fill()
    }

}
