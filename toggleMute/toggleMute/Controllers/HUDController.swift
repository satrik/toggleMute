// Author: Sascha Petrik

import Cocoa
import ApplicationServices

/// A small always-on-top overlay, similar in spirit to the system volume/
/// brightness HUD, that briefly shows whether the mic just got muted or
/// unmuted. Purely visual — never intercepts clicks (ignoresMouseEvents).
final class HUDController {

    static let shared = HUDController()

    private var panel: NSPanel?
    private var effectView: NSVisualEffectView?
    private var imageView: NSImageView?
    private var deviceNameLabel: NSTextField?
    private var dismissWorkItem: DispatchWorkItem?

    // Compact (icon only) size — used whenever the device name isn't shown.
    private let compactSize = NSSize(width: 64, height: 64)
    private let iconDisplaySize: CGFloat = 32

    // Extra layout for the optional device name: only the width grows (t´ßhe
    // height always stays compactSize.height) — icon stays on the left at
    // its usual size/position, name sits to its right.
    private let iconLeftMargin: CGFloat = 16
    private let iconTextGap: CGFloat = 8
    private let deviceNameRightMargin: CGFloat = 26
    private let deviceNameMinWidth: CGFloat = 120
    private let deviceNameMaxWidth: CGFloat = 294
    private let deviceNameFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    private let cornerRadius: CGFloat = 25
    private let displayDuration: TimeInterval = 1.0
    private let fadeDuration: TimeInterval = 0.25
    private let screenMarginTop: CGFloat = 10
    private let screenMarginRight: CGFloat = 19

    private init() {}


    /// Prompts for Accessibility permission if it's not already granted
    /// (needed only for the fullscreen-aware positioning in
    /// isFullScreenAppActive below — everything else about the HUD works
    /// fine without it). Safe to call repeatedly; the system only actually
    /// shows the dialog once per grant/decline.
    func requestAccessibilityPermissionIfNeeded() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }


    /// - Parameter sticky: When true, the HUD is shown but no auto-dismiss
    ///   timer is armed — used while push-to-talk is being held down, so it
    ///   stays on screen for as long as the key/icon is pressed. A later
    ///   non-sticky call (the PTT release) re-arms the normal fade-out.
    /// - Parameter red: When true (and muted), tints the icon (and device
    ///   name text) MuteController.redColor instead of white — mirrors the
    ///   optional red menu bar icon.
    /// - Parameter deviceName: When non-nil/non-empty, the HUD widens to show
    ///   this next to the icon (the current default input device's name).
    func show(muted: Bool, sticky: Bool = false, red: Bool = false, deviceName: String? = nil) {

        DispatchQueue.main.async { [weak self] in
            self?.present(muted: muted, sticky: sticky, red: red, deviceName: deviceName)
        }

    }


    /// Fades the HUD out immediately, regardless of whether it's currently
    /// sticky. Used when "Always show HUD" gets turned off while the
    /// permanent HUD is on screen — otherwise it would just sit there until
    /// the next mute/unmute event happened to re-arm the fade timer.
    func hide() {

        DispatchQueue.main.async { [weak self] in
            self?.dismissWorkItem?.cancel()
            self?.dismissWorkItem = nil
            self?.fadeOutAndHide()
        }

    }


    private func present(muted: Bool, sticky: Bool, red: Bool, deviceName: String?) {

        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        let panel = panelInstance()
        let trimmedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsDeviceName = !(trimmedName?.isEmpty ?? true)
        let panelSize = size(showingDeviceName: showsDeviceName, deviceName: trimmedName)

        layout(size: panelSize, showingDeviceName: showsDeviceName, deviceName: trimmedName)
        panel.setContentSize(panelSize)
        positionOnScreen(panel, size: panelSize)

        let tint: NSColor = (muted && red) ? MuteController.redColor : .controlTextColor
        imageView?.image = symbolImage(muted: muted)
        imageView?.contentTintColor = tint
        deviceNameLabel?.textColor = tint

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        guard !sticky else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutAndHide()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: workItem)

    }


    private func size(showingDeviceName: Bool, deviceName: String?) -> NSSize {

        guard showingDeviceName, let deviceName = deviceName, let label = deviceNameLabel else {
            return compactSize
        }

        // sizeToFit() (via the actual NSTextField/cell) is what correctly
        // accounts for the field's own internal metrics — a plain
        // boundingRect(withAttributes:) string measurement was tried here
        // instead (to sidestep a first-launch-only sizing quirk, see below)
        // but it measures raw text only, missing the field's own layout
        // margins, which brought back truncation on every single display.
        // Truncated text is a much worse failure mode than a very minor,
        // once-per-session cosmetic quirk, so this stays.
        label.stringValue = deviceName
        label.sizeToFit()
        let textWidth = label.frame.width

        let contentWidth = iconLeftMargin + iconDisplaySize + iconTextGap + textWidth + deviceNameRightMargin
        let width = min(deviceNameMaxWidth, max(deviceNameMinWidth, contentWidth))

        return NSSize(width: width, height: compactSize.height)

    }


    private func panelInstance() -> NSPanel {

        if let panel = panel {
            return panel
        }

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .statusBar
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        newPanel.isReleasedWhenClosed = false
        newPanel.canHide = false

        let newEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: compactSize))
        newEffectView.material = .hudWindow
        newEffectView.blendingMode = .behindWindow
        newEffectView.state = .active
        newEffectView.maskImage = Self.roundedCornerMaskImage(cornerRadius: cornerRadius)
        
        let newImageView = NSImageView()
        newImageView.imageScaling = .scaleProportionallyUpOrDown
        // The rendered image is a template (see symbolImage(muted:)); this
        // tint is what actually makes it white/red — see present(...).
        newImageView.contentTintColor = .white

        let newLabel = NSTextField(labelWithString: "")
        newLabel.font = deviceNameFont
        // Set once here, matching what layout() always uses — sizeToFit()'s
        // computed natural width turned out to differ depending on the
        // cell's current alignment, and this used to default to .center at
        // creation, only getting switched to .left afterward (by layout(),
        // which runs after size() already measured). That mismatch was
        // exactly why the very first HUD display of a session measured a
        // different width than every one after it.
        newLabel.alignment = .left
        newLabel.textColor = .white
        newLabel.lineBreakMode = .byTruncatingTail
        newLabel.isHidden = true

        newEffectView.addSubview(newImageView)
        newEffectView.addSubview(newLabel)
        newPanel.contentView = newEffectView

        panel = newPanel
        effectView = newEffectView
        imageView = newImageView
        deviceNameLabel = newLabel

        return newPanel

    }

    private static func roundedCornerMaskImage(cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(
            size: NSSize(width: cornerRadius * 2, height: cornerRadius * 2),
            flipped: false
        ) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            NSColor.black.set()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }
    
    private func layout(size: NSSize, showingDeviceName: Bool, deviceName: String?) {

        effectView?.frame = NSRect(origin: .zero, size: size)

        if showingDeviceName {

            imageView?.frame = NSRect(
                x: iconLeftMargin,
                y: (size.height - iconDisplaySize) / 2,
                width: iconDisplaySize,
                height: iconDisplaySize
            )

            let textX = iconLeftMargin + iconDisplaySize + iconTextGap
            let textWidth = size.width - textX - deviceNameRightMargin

            deviceNameLabel?.stringValue = deviceName ?? ""
            deviceNameLabel?.alignment = .left
            deviceNameLabel?.frame = NSRect(x: textX, y: (size.height - 16) / 2, width: textWidth, height: 16)
            deviceNameLabel?.isHidden = false

        } else {

            imageView?.frame = NSRect(
                x: (size.width - iconDisplaySize) / 2,
                y: (size.height - iconDisplaySize) / 2,
                width: iconDisplaySize,
                height: iconDisplaySize
            )

            deviceNameLabel?.isHidden = true

        }

    }


    private func symbolImage(muted: Bool) -> NSImage? {

        // Always draw the same "mic" glyph — mic vs mic.slash are two
        // different SF Symbol designs with slightly different internal
        // metrics, which visibly shifted the icon between states. Drawing a
        // fixed diagonal strike-through ourselves on mute keeps the mic body
        // pixel-identical between both states; only the line is added.
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)

        guard let mic = NSImage(systemSymbolName: "mic", accessibilityDescription: muted ? "Muted" : "Unmuted")?
            .withSymbolConfiguration(config) else { return nil }

        let canvasSize = NSSize(width: 48, height: 48)
        let canvas = NSImage(size: canvasSize)

        canvas.lockFocus()

        let micSize = mic.size
        let micOrigin = NSPoint(
            x: (canvasSize.width - micSize.width) / 2,
            y: (canvasSize.height - micSize.height) / 2
        )
        mic.draw(at: micOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

        if muted {
            let line = NSBezierPath()
            line.lineWidth = 2
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 32, y: 18))
            line.line(to: NSPoint(x: canvasSize.width - 31, y: canvasSize.height - 16))
            NSColor.black.setStroke()
            line.stroke()
        }

        canvas.unlockFocus()

        // Re-mark as a template so contentTintColor (set on the image view)
        // tints the whole thing uniformly — lockFocus drawing bakes in flat
        // pixels and clears this flag, which is why the icon rendered black
        // instead of adapting like the other HUDs.
        canvas.isTemplate = true

        return canvas

    }


    private func positionOnScreen(_ panel: NSPanel, size: NSSize) {

        // NSScreen.main can transiently be nil very early in a background
        // (LSUIElement) app's lifecycle — before the window server has
        // fully registered it, since there's no window to anchor to yet.
        // This is most likely to bite on the very first HUD trigger right
        // after a cold launch. Falling back to the first available screen
        // (rather than silently skipping positioning, which left the panel
        // shown at its default near-origin position) keeps the HUD visible
        // and correctly placed even in that race.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let x = isFullScreenAppActive(on: screen)
            ? screen.visibleFrame.midX - size.width / 2
            : screen.visibleFrame.maxX - size.width - screenMarginRight

        let y = screen.visibleFrame.maxY - size.height - screenMarginTop

        panel.setFrameOrigin(NSPoint(x: x, y: y))

    }


    /// A window's reported size can't reliably distinguish "genuinely
    /// fullscreen" from "an ordinary window that's simply maximized" — both
    /// end up roughly the same size (screen size minus the menu bar strip),
    /// which is exactly what broke the earlier CGWindowList-bounds-based
    /// version of this check. Asking the Accessibility API directly whether
    /// the frontmost app's focused window has its AXFullScreen attribute
    /// set is unambiguous. Requires Accessibility permission (System
    /// Settings → Privacy & Security → Accessibility, requested once at
    /// launch — see AppDelegate); without it, this simply returns false and
    /// the HUD keeps using its normal top-right position.
    private func isFullScreenAppActive(on screen: NSScreen) -> Bool {

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }

        let axApp = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindow = focusedWindowRef else {
            return false
        }

        var fullScreenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, "AXFullScreen" as CFString, &fullScreenRef) == .success,
              let isFullScreen = fullScreenRef as? Bool else {
            return false
        }

        return isFullScreen

    }


    private func fadeOutAndHide() {

        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })

    }

}
