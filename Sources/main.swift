import Cocoa
import ServiceManagement
import Carbon.HIToolbox

// MARK: - Settings

enum Settings {
    private static let store = UserDefaults.standard

    /// Delay between two breaks. Restarted from the moment Skip or Go is hit.
    static var interval: TimeInterval {
        get { store.object(forKey: "interval") as? TimeInterval ?? 20 * 60 }
        set { store.set(newValue, forKey: "interval") }
    }

    /// Length of the countdown started by "Go".
    static var breakLength: TimeInterval {
        get { store.object(forKey: "breakLength") as? TimeInterval ?? 2 * 60 }
        set { store.set(newValue, forKey: "breakLength") }
    }

    static let borderWidth: CGFloat = 12
    /// Applies to the INNER edge of the border only. The outer edge follows the
    /// display, whose bottom corners are square.
    static let borderInnerRadius: CGFloat = 22
    static let borderColor = NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.06, alpha: 1.0)
    static let blinkPeriod: CFTimeInterval = 1.1

    static let pillRadius: CGFloat = 16
    static let pillHeight: CGFloat = 60
    static let pillBottomMargin: CGFloat = 15

    static let intervalPresets = [1, 10, 15, 20, 25, 30, 45, 60, 120].map { $0 * 60 }
    static let breakPresets = [20, 30, 60, 90, 120, 180, 300]
}

// MARK: - Log

/// Appends to ~/Library/Logs/eyesaver.log. Without it, a shortcut that fails to
/// register is indistinguishable from one that is simply never pressed.
enum Log {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/eyesaver.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Shortcuts

let keyEscape: UInt16 = 53
let keySpace: UInt16 = 49
let keyReturn: UInt16 = 36

/// The active shortcut pair.
///
/// Bare keys are no longer the default: the break interrupts you mid-sentence,
/// and swallowing `space` stops you from finishing it before you look away.
enum Shortcut: String, CaseIterable {
    case command, control, option, bare

    static var current: Shortcut {
        get { Shortcut(rawValue: UserDefaults.standard.string(forKey: "shortcut") ?? "") ?? .command }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcut") }
    }

    /// Everything that differs between presets, in one place. Five accessors
    /// used to repeat the same four-case switch.
    private struct Spec {
        let name: String
        let carbonModifiers: Int
        let goKey: UInt16
        let skipLabel: String
        let goLabel: String
    }

    private var spec: Spec {
        switch self {
        // ⌘space is Spotlight, so the command preset uses return instead.
        case .command: return Spec(name: "⌘ esc  /  ⌘ return", carbonModifiers: cmdKey,
                                   goKey: keyReturn, skipLabel: "⌘esc", goLabel: "⌘↩")
        case .control: return Spec(name: "⌃ esc  /  ⌃ space", carbonModifiers: controlKey,
                                   goKey: keySpace, skipLabel: "⌃esc", goLabel: "⌃space")
        case .option:  return Spec(name: "⌥ esc  /  ⌥ space", carbonModifiers: optionKey,
                                   goKey: keySpace, skipLabel: "⌥esc", goLabel: "⌥space")
        case .bare:    return Spec(name: "esc  /  space  (no modifier)", carbonModifiers: 0,
                                   goKey: keySpace, skipLabel: "esc", goLabel: "space")
        }
    }

    var name: String { spec.name }
    /// Carbon-style modifier mask, as expected by RegisterEventHotKey.
    var carbonModifiers: UInt32 { UInt32(spec.carbonModifiers) }
    var skipKey: UInt16 { keyEscape }
    var goKey: UInt16 { spec.goKey }
    var skipLabel: String { spec.skipLabel }
    var goLabel: String { spec.goLabel }

    enum Action: UInt32 { case skip = 1, go = 2 }
}

/// System-wide shortcuts through `RegisterEventHotKey` (Carbon).
///
/// This is the API app launchers use, and the only way to catch a global
/// shortcut with **no TCC permission at all** — neither Accessibility nor Input
/// Monitoring. A `CGEventTap` needs both, and the grant dies on every rebuild
/// because an ad-hoc signature changes identity each time.
///
/// Shortcuts are registered only while an alert is on screen and removed right
/// after, so they belong to other apps the rest of the time.
final class GlobalShortcuts {
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var onAction: ((Shortcut.Action) -> Void)?

    private static let signature: OSType = 0x45594553  // 'EYES'

    init() { installHandler() }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, let action = Shortcut.Action(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func enable(_ shortcut: Shortcut, onAction: @escaping (Shortcut.Action) -> Void) {
        disable()
        self.onAction = onAction
        for (key, action) in [(shortcut.skipKey, Shortcut.Action.skip),
                              (shortcut.goKey, Shortcut.Action.go)] {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: GlobalShortcuts.signature, id: action.rawValue)
            let status = RegisterEventHotKey(UInt32(key), shortcut.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                refs.append(ref)
            } else {
                Log.write("RegisterEventHotKey FAILED (key \(key), status \(status))")
            }
        }
        Log.write("shortcuts registered: \(shortcut.name) — \(refs.count)/2")
    }

    func disable() {
        refs.forEach { if let ref = $0 { UnregisterEventHotKey(ref) } }
        refs.removeAll()
    }
}

// MARK: - Updates

/// Asks GitHub whether a newer release exists, and points the user at it.
///
/// Deliberately does not download or install anything: Eyesaver is built from
/// source, so the update is a `git pull`. One anonymous HTTPS GET, no payload,
/// no identifier, nothing stored beyond the date of the last check.
enum Updater {
    static let repository = "GNRNicolas/eyesaver"
    private static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate") }
    }

    private static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `manual` is a user-initiated check: it reports "up to date" too, and
    /// ignores both the automatic setting and the once-a-day throttle.
    static func check(manual: Bool) {
        if !manual {
            guard automatic else { return }
            if let last = lastCheck, Date().timeIntervalSince(last) < checkInterval { return }
        }
        lastCheck = Date()

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                Log.write("update check failed: \(error.localizedDescription)")
                if manual { DispatchQueue.main.async { report(failure: error.localizedDescription) } }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else {
                Log.write("update check: unreadable response")
                if manual { DispatchQueue.main.async { report(failure: "Unreadable response from GitHub.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            // Only follow a link GitHub itself served, and only over HTTPS.
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            let safePage = page?.scheme == "https" && (page?.host?.hasSuffix("github.com") ?? false)
                ? page : URL(string: "https://github.com/\(repository)/releases/latest")

            Log.write("update check: local \(currentVersion), latest \(latest)")
            DispatchQueue.main.async {
                if isNewer(latest, than: currentVersion) {
                    offer(version: latest, page: safePage)
                } else if manual {
                    report(upToDate: currentVersion)
                }
            }
        }.resume()
    }

    /// Numeric component-wise comparison, so 1.10 beats 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func offer(version: String, page: URL?) {
        let alert = NSAlert()
        alert.messageText = "Eyesaver \(version) is available"
        alert.informativeText = """
        You are running \(currentVersion). Eyesaver is built from source, so updating is:

            git pull && ./build.sh --install
        """
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let page { NSWorkspace.shared.open(page) }
    }

    private static func report(upToDate version: String) {
        let alert = NSAlert()
        alert.messageText = "Eyesaver is up to date"
        alert.informativeText = "You are running version \(version)."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func report(failure: String) {
        let alert = NSAlert()
        alert.messageText = "Could not check for updates"
        alert.informativeText = failure
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Screen border

/// Pulsing orange ring around one display. Purely decorative: the window
/// carrying it lets every click through.
private final class BorderView: NSView {
    private let ring = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        // A filled ring, not a stroke. A stroke is centred on its path, so both
        // edges share one radius — and rounding the outer edge leaves a gap in
        // the square bottom corners of the display.
        ring.fillColor = Settings.borderColor.cgColor
        ring.fillRule = .evenOdd
        ring.strokeColor = nil
        ring.shadowColor = Settings.borderColor.cgColor
        ring.shadowOpacity = 0.7
        ring.shadowRadius = 10
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = Settings.borderWidth
        let path = CGMutablePath()
        path.addRect(bounds)                                     // outer: square
        path.addPath(CGPath(roundedRect: bounds.insetBy(dx: w, dy: w),
                            cornerWidth: Settings.borderInnerRadius,
                            cornerHeight: Settings.borderInnerRadius,
                            transform: nil))                     // inner: rounded
        ring.frame = bounds
        ring.path = path
    }

    func startBlinking() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.12
        pulse.duration = Settings.blinkPeriod
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(pulse, forKey: "pulse")
    }
}

/// The borders, one window per display.
final class Borders {
    private var windows: [NSWindow] = []
    private(set) var visible = false

    func show() {
        guard !visible else { return }
        visible = true
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false, screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: true)
            let view = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.orderFrontRegardless()
            view.startBlinking()
            windows.append(window)
        }
    }

    func hide() {
        guard visible else { return }
        visible = false
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

// MARK: - Pill background

/// Translucent material genuinely clipped to rounded corners.
///
/// `layer.cornerRadius` is not enough: in `.behindWindow` blending the blur is
/// composited by the window server across the view's whole rectangle and
/// ignores the layer mask — which is what leaves a visible box around the pill.
/// `maskImage` is the only clip that compositing respects.
final class PillBackground: NSVisualEffectView {
    private let outline = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        outline.lineWidth = 1
        layer?.addSublayer(outline)
        maskImage = PillBackground.mask(radius: Settings.pillRadius)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: Settings.pillRadius,
                              cornerHeight: Settings.pillRadius,
                              transform: nil)
    }

    /// Stretchable image: the four corners are preserved, the centre stretches.
    private static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Pill button

/// Dark capsule button showing its keyboard shortcut as a subscript.
final class PillButton: NSButton {
    private var label: String
    private var shortcut: String
    private let prominent: Bool
    private var hovered = false

    init(label: String, shortcut: String, prominent: Bool, target: AnyObject, action: Selector) {
        self.label = label
        self.shortcut = shortcut
        self.prominent = prominent
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = true
        attributedTitle = makeTitle()
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(label newLabel: String? = nil, shortcut newShortcut: String) {
        if let newLabel { label = newLabel }
        shortcut = newShortcut
        attributedTitle = makeTitle()
        invalidateIntrinsicContentSize()
    }

    private func makeTitle() -> NSAttributedString {
        let tint: NSColor = prominent ? .black : NSColor.white.withAlphaComponent(0.92)
        let title = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: tint,
        ])
        title.append(NSAttributedString(string: "  \(shortcut)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: tint.withAlphaComponent(prominent ? 0.45 : 0.4),
        ]))
        return title
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width + 26, height: 30)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 9
    }

    private func paint() {
        let fill: NSColor = prominent
            ? (hovered ? .white : NSColor.white.withAlphaComponent(0.88))
            : NSColor.white.withAlphaComponent(hovered ? 0.16 : 0.09)
        layer?.backgroundColor = fill.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; paint() }
    override func mouseExited(with event: NSEvent) { hovered = false; paint() }
}

// MARK: - Floating bar

protocol BarDelegate: AnyObject {
    func barDidSkip()
    func barDidGo()
}

/// Dark translucent pill, centred at the bottom of the main display.
/// A non-activating panel: clicking it never steals focus from your work.
final class Bar {
    weak var delegate: BarDelegate?

    private var panel: NSPanel?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var skipButton: PillButton!
    private var goButton: PillButton!

    private(set) var visible = false

    private func build() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: Settings.pillHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Always dark, whatever the system theme is.
        panel.appearance = NSAppearance(named: .vibrantDark)

        let background = PillBackground()

        icon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.75)

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.95)
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.55)

        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let shortcut = Shortcut.current
        skipButton = PillButton(label: "Skip", shortcut: shortcut.skipLabel, prominent: false,
                                target: self, action: #selector(skip))
        goButton = PillButton(label: "Go", shortcut: shortcut.goLabel, prominent: true,
                              target: self, action: #selector(go))

        let buttons = NSStackView(views: [skipButton, goButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let row = NSStackView(views: [icon, labels, buttons])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setHuggingPriority(.defaultHigh, for: .horizontal)

        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])

        panel.contentView = background
        return panel
    }

    @objc private func skip() { delegate?.barDidSkip() }
    @objc private func go() { delegate?.barDidGo() }

    // MARK: Presentation

    func showPrompt() {
        let panel = self.panel ?? build()
        self.panel = panel
        let shortcut = Shortcut.current
        skipButton.update(label: "Skip", shortcut: shortcut.skipLabel)
        goButton.update(shortcut: shortcut.goLabel)
        goButton.isHidden = false
        title.stringValue = "Time to look away"
        subtitle.stringValue = "Rest your eyes for \(Bar.shortFormat(Settings.breakLength))"
        present(panel)
    }

    func switchToCountdown() {
        guard let panel else { return }
        // Same button, new job: dismissing the countdown is still "skip".
        skipButton.update(label: "Done", shortcut: Shortcut.current.skipLabel)
        goButton.isHidden = true
        title.stringValue = "Looking away"
        updateCountdown(Settings.breakLength)
        resize(panel, animated: true)
    }

    func updateCountdown(_ remaining: TimeInterval) {
        let seconds = max(0, Int(remaining.rounded(.up)))
        subtitle.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func present(_ panel: NSPanel) {
        resize(panel, animated: false)
        guard !visible else { return }
        visible = true
        panel.alphaValue = 0
        let destination = targetFrame(for: panel)
        panel.setFrame(destination.offsetBy(dx: 0, dy: -12), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(destination, display: true)
        }
    }

    func hide() {
        guard visible, let panel else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Recomputes width and position: the pill hugs its content.
    private func resize(_ panel: NSPanel, animated: Bool) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let destination = targetFrame(for: panel)
        if animated && visible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(destination, display: true)
            }
        } else {
            panel.setFrame(destination, display: true)
        }
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        let width = max(320, (panel.contentView?.fittingSize.width ?? 320).rounded(.up))
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        return NSRect(x: (area.midX - width / 2).rounded(),
                      y: area.minY + Settings.pillBottomMargin,
                      width: width,
                      height: Settings.pillHeight)
    }

    static func shortFormat(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        if total >= 3600 && total % 3600 == 0 { return "\(total / 3600) h" }
        if total < 60 { return "\(total) s" }
        if total % 60 == 0 { return "\(total / 60) min" }
        return "\(total / 60) min \(total % 60) s"
    }
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate, BarDelegate {
    private var statusItem: NSStatusItem!
    private let borders = Borders()
    private let bar = Bar()
    private let shortcuts = GlobalShortcuts()

    private var nextBreak: Date?
    private var intervalTimer: Timer?
    private var breakEnd: Date?
    private var breakTimer: Timer?
    private var tick: Timer?
    private var paused = false
    private var testSignal: DispatchSourceSignal?
    private var lastTitle = ""

    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private let autoUpdateItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutoUpdate), keyEquivalent: "")

    private enum Phase { case idle, prompt, resting }
    private var phase: Phase = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("--- launch ---")
        bar.delegate = self
        buildMenu()
        schedule()

        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }

        // `kill -USR1 <pid>` triggers a break — handy for testing.
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.trigger() }
        source.resume()
        testSignal = source

        // Let launch settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { Updater.check(manual: false) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.borders.visible else { return }
            self.borders.hide(); self.borders.show()
        }
    }

    // MARK: Menu bar

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Eyesaver")?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Take a Break Now", #selector(takeBreakNow)))
        menu.addItem(item("Reset Timer", #selector(resetTimer)))
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(choiceMenu("Break Every", choices: durations(Settings.intervalPresets),
                                selected: Int(Settings.interval), action: #selector(pickInterval(_:))))
        menu.addItem(choiceMenu("Break Length", choices: durations(Settings.breakPresets),
                                selected: Int(Settings.breakLength), action: #selector(pickBreakLength(_:))))
        menu.addItem(choiceMenu("Shortcuts",
                                choices: Shortcut.allCases.enumerated().map { ($1.name, $0) },
                                selected: Shortcut.allCases.firstIndex(of: Shortcut.current) ?? 0,
                                action: #selector(pickShortcut(_:))))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(autoUpdateItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Eyesaver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
        refreshMenuState()
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    /// One radio-style submenu builder for every list of choices. The selected
    /// value travels in `tag`: seconds for the durations, an index for the
    /// shortcut presets.
    private func choiceMenu(_ title: String, choices: [(String, Int)], selected: Int, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (label, value) in choices {
            let entry = NSMenuItem(title: label, action: action, keyEquivalent: "")
            entry.tag = value
            entry.target = self
            entry.state = value == selected ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func durations(_ values: [Int]) -> [(String, Int)] {
        values.map { (Bar.shortFormat(TimeInterval($0)), $0) }
    }

    private func refreshMenuState() {
        pauseItem.title = paused ? "Resume" : "Pause"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        autoUpdateItem.state = Updater.automatic ? .on : .off
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        Settings.interval = TimeInterval(sender.tag)
        select(sender)
        schedule()
    }

    @objc private func pickBreakLength(_ sender: NSMenuItem) {
        Settings.breakLength = TimeInterval(sender.tag)
        select(sender)
    }

    @objc private func pickShortcut(_ sender: NSMenuItem) {
        let shortcut = Shortcut.allCases[sender.tag]
        Shortcut.current = shortcut
        select(sender)
        Log.write("shortcuts switched to \(shortcut.name)")
    }

    private func select(_ sender: NSMenuItem) {
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    @objc private func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { NSSound.beep() }
        refreshMenuState()
    }

    @objc private func checkForUpdates() { Updater.check(manual: true) }

    @objc private func toggleAutoUpdate() {
        Updater.automatic.toggle()
        refreshMenuState()
    }

    @objc private func takeBreakNow() { trigger() }
    @objc private func resetTimer() { finish(); schedule() }

    @objc private func togglePause() {
        paused.toggle()
        if paused { intervalTimer?.invalidate(); finish() } else { schedule() }
        refreshMenuState()
    }

    // MARK: Cycle

    private func schedule() {
        intervalTimer?.invalidate()
        guard !paused else { nextBreak = nil; return }
        nextBreak = Date().addingTimeInterval(Settings.interval)
        intervalTimer = Timer.scheduledTimer(withTimeInterval: Settings.interval, repeats: false) { [weak self] _ in
            self?.trigger()
        }
    }

    private func trigger() {
        guard phase == .idle else { return }
        phase = .prompt
        borders.show()
        bar.showPrompt()
        // Shortcuts exist only for the duration of the alert: the rest of the
        // time they belong to other apps.
        shortcuts.enable(Shortcut.current) { [weak self] action in
            guard let self else { return }
            switch action {
            case .skip: self.barDidSkip()
            case .go: self.phase == .prompt ? self.barDidGo() : self.barDidSkip()
            }
        }
    }

    /// Skip — everything goes away and the next delay restarts from now.
    func barDidSkip() { finish(); schedule() }

    /// Go — borders go away, the bar becomes a countdown. The next delay
    /// restarts from now as well.
    func barDidGo() {
        guard phase == .prompt else { finish(); schedule(); return }
        phase = .resting
        borders.hide()
        bar.switchToCountdown()
        breakEnd = Date().addingTimeInterval(Settings.breakLength)
        breakTimer?.invalidate()
        breakTimer = Timer.scheduledTimer(withTimeInterval: Settings.breakLength, repeats: false) { [weak self] _ in
            self?.finish()
        }
        schedule()
    }

    private func finish() {
        phase = .idle
        shortcuts.disable()
        breakTimer?.invalidate(); breakTimer = nil
        breakEnd = nil
        borders.hide()
        bar.hide()
    }

    private func heartbeat() {
        if phase == .resting, let end = breakEnd { bar.updateCountdown(end.timeIntervalSinceNow) }

        let title: String
        if paused {
            title = " —"
        } else if phase != .idle {
            title = " 0"
        } else if let next = nextBreak {
            // Whole minutes, rounded up: "1" while any second remains, never
            // "0" during the wait.
            title = " \(max(1, Int((next.timeIntervalSinceNow / 60).rounded(.up))))"
        } else {
            title = " —"
        }
        if title != lastTitle {
            lastTitle = title
            statusItem.button?.title = title
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshMenuState() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
