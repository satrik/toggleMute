import Cocoa

final class MuteHUDWindowController {

    static let shared = MuteHUDWindowController()
    private var preferences = Preferences()

    private let hudSize = CGSize(width: 200, height: 200)

    private lazy var hudWindow: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hudSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = buildContentView()
        return panel
    }()

    private var iconView: NSImageView!
    private var label: NSTextField!

    private var dismissWork: DispatchWorkItem?

    private init() {}

    // MARK: - Public API

    func show(muted: Bool) {
        guard preferences.showHudEnabled else { return }

        let window = hudWindow

        // Update content (using contentTintColor for macOS 11 compatibility)
        let symbolName = muted ? "mic.slash.fill" : "mic.fill"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
            iconView.image = img.withSymbolConfiguration(cfg)
        }
        iconView.contentTintColor = muted ? .systemRed : .white
        label.stringValue = muted ? "Muted" : "Unmuted"

        positionWindow()

        dismissWork?.cancel()

        if let layer = window.contentView?.layer {
            layer.removeAllAnimations()
            layer.opacity = 1.0
        }
        
        // Immediately make visible
        window.alphaValue = 1.0
        window.orderFrontRegardless()

        // Schedule fade-out after 1.0 s
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - Private helpers

    private func buildContentView() -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: hudSize))
        container.wantsLayer = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18 
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        let iv = NSImageView(frame: NSRect(x: 0, y: 76, width: hudSize.width, height: 80))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.minXMargin, .maxXMargin]
        blur.addSubview(iv)
        iconView = iv

        let tf = NSTextField(frame: NSRect(x: 0, y: 32, width: hudSize.width, height: 24))
        tf.isEditable = false
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.alignment = .center
        tf.font = .systemFont(ofSize: 18, weight: .bold)
        tf.textColor = NSColor(white: 1.0, alpha: 0.85) 
        tf.autoresizingMask = [.minXMargin, .maxXMargin]
        blur.addSubview(tf)
        label = tf

        return container
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hudSize.width / 2
        let y = screenFrame.minY + 70
        hudWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func fadeOut() {
        guard let layer = hudWindow.contentView?.layer else { return }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // When animation completes naturally (not cancelled), hide the window
            if layer.opacity == 0 {
                self?.hudWindow.orderOut(nil)
            }
        }
        
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        
        layer.opacity = 0.0
        layer.add(anim, forKey: "fade")
        
        CATransaction.commit()
    }
}
