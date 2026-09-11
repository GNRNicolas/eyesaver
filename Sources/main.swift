import Cocoa
import ServiceManagement
import Carbon.HIToolbox

// MARK: - Settings

/// Everything the user can change, and where it is stored.
///
/// The keys are part of the app's contract with its own past: renaming one
/// silently resets that preference on every existing install, and `breaksTaken`
/// in particular can never be recovered. Rename the Swift property, never the
/// string.
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

    /// Stop counting down when the keyboard and mouse have been quiet this
    /// long. Zero means never stop.
    static var idleTimeout: TimeInterval {
        get { store.object(forKey: "idleTimeout") as? TimeInterval ?? 5 * 60 }
        set { store.set(newValue, forKey: "idleTimeout") }
    }

    /// Breaks taken all the way through, ever.
    static var breaksTaken: Int {
        get { store.integer(forKey: "completedSessions") }
        set { store.set(newValue, forKey: "completedSessions") }
    }

    /// Played when a break runs to its end. Empty means silence.
    static var breakEndSound: String {
        get { store.object(forKey: "breakEndSound") as? String ?? "Hero" }
        set { store.set(newValue, forKey: "breakEndSound") }
    }

    /// System sounds gentle enough to end a break on. They ship with macOS, so
    /// none of them is bundled here.
    static let soundPresets = ["Hero", "Purr", "Pop", "Glass", "Ping", "Tink", "Submarine", "Bottle"]

    /// Offered in the menu, in seconds.
    static let intervalPresets = [1, 10, 15, 20, 25, 30, 45, 60, 120].map { $0 * 60 }
    static let breakLengthPresets = [20, 30, 60, 90, 120, 180, 300]
    static let idleTimeoutPresets = [0, 60, 300, 600, 900, 1800]
}

// MARK: - Style

/// Colours and geometry. Nothing here is persisted or user-facing.
enum Style {
    /// Orange, #FF8C0E.
    static let borderColor = NSColor(calibratedRed: 1.0, green: 0.47, blue: 0.06, alpha: 1.0)
    /// Off-white, #FBFBF2. Pure white is harsh against the dark material.
    static let ink = NSColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xF2 / 255, alpha: 1)
    /// Near-black, #1E1E1C. The warm counterpart to `ink`; pure black is not
    /// used anywhere the eye can see it.
    static let night = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1C / 255, alpha: 1)

    static let borderWidth: CGFloat = 12
    /// Applies to the INNER edge of the border only. The outer edge follows the
    /// display, whose bottom corners are square.
    static let borderInnerRadius: CGFloat = 22
    static let blinkPeriod: CFTimeInterval = 1.1

    static let pillRadius: CGFloat = 16
    static let pillWidth: CGFloat = 460
    static let pillHeight: CGFloat = 60
    static let pillBottomMargin: CGFloat = 15
}

// MARK: - Formatting

/// The two ways a number is written on screen, shared by the menu, the bar and
/// the share card.
enum Format {
    /// 9999 stays 9999; 10000 becomes 10k. Keeps the menu bar narrow once the
    /// count runs into five digits.
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(value / 1_000_000)M" }
        if value >= 10_000 { return "\(value / 1_000)k" }
        return "\(value)"
    }

    /// Durations as a person would say them: "2 min", "1 h", "1 min 30 s".
    static func duration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        if total >= 3600 && total % 3600 == 0 { return "\(total / 3600) h" }
        if total < 60 { return "\(total) s" }
        if total % 60 == 0 { return "\(total / 60) min" }
        return "\(total / 60) min \(total % 60) s"
    }
}

// MARK: - Sound

/// The chime at the end of a break, drawn from the sounds macOS already ships.
enum Sound {
    /// `NSSound(named:)` hands back a shared instance, which refuses to play
    /// again while it still thinks it is playing. Stopping first makes a second
    /// preview audible.
    static func play(_ name: String) {
        guard !name.isEmpty, let sound = NSSound(named: name) else { return }
        sound.stop()
        sound.play()
    }

    static func playBreakEnd() { play(Settings.breakEndSound) }
}

// MARK: - Log

/// Appends to ~/Library/Logs/eyesaver.log. Without it, a shortcut that fails to
/// register is indistinguishable from one that is simply never pressed.
enum Log {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/eyesaver.log")

    /// The file is append-only and the app runs for months, so it needs a cap.
    private static let sizeLimit = 256 * 1024

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        if end > sizeLimit {
            try? handle.truncate(atOffset: 0)
        }
        try? handle.write(contentsOf: data)
    }
}

// MARK: - Idle

/// How long the keyboard and mouse have been quiet.
///
/// `secondsSinceLastEventType` reports a duration, never the content of an
/// event, so it needs no permission. There is no point counting down towards a
/// break while nobody is at the machine.
enum Activity {
    private static let anyInput = CGEventType(rawValue: ~0)!   // kCGAnyInputEventType

    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static var isIdle: Bool {
        let limit = Settings.idleTimeout
        return limit > 0 && idleSeconds >= limit
    }
}

// MARK: - Shortcuts

/// Virtual key codes, as `RegisterEventHotKey` expects them.
private enum KeyCode {
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    static let `return`: UInt16 = 36
}

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
                                   goKey: KeyCode.return, skipLabel: "⌘esc", goLabel: "⌘↩")
        case .control: return Spec(name: "⌃ esc  /  ⌃ space", carbonModifiers: controlKey,
                                   goKey: KeyCode.space, skipLabel: "⌃esc", goLabel: "⌃space")
        case .option:  return Spec(name: "⌥ esc  /  ⌥ space", carbonModifiers: optionKey,
                                   goKey: KeyCode.space, skipLabel: "⌥esc", goLabel: "⌥space")
        case .bare:    return Spec(name: "esc  /  space  (no modifier)", carbonModifiers: 0,
                                   goKey: KeyCode.space, skipLabel: "esc", goLabel: "space")
        }
    }

    var name: String { spec.name }
    /// Carbon-style modifier mask, as expected by RegisterEventHotKey.
    var carbonModifiers: UInt32 { UInt32(spec.carbonModifiers) }
    var skipKey: UInt16 { KeyCode.escape }
    var goKey: UInt16 { spec.goKey }
    var skipLabel: String { spec.skipLabel }
    var goLabel: String { spec.goLabel }

    /// The preset's two hotkeys, paired with what they do.
    var keys: [(UInt16, Action)] { [(skipKey, .skip), (goKey, .go)] }

    enum Action: UInt32 { case skip = 1, go = 2 }
}

/// System-wide shortcuts through `RegisterEventHotKey` (Carbon).
///
/// This is the API app launchers use, and the only way to catch a global
/// shortcut with **no TCC permission at all**: neither Accessibility nor Input
/// Monitoring. A `CGEventTap` needs both, and the grant dies on every rebuild
/// because an ad-hoc signature changes identity each time.
///
/// Shortcuts are registered only while an alert is on screen and removed right
/// after, so they belong to other apps the rest of the time. That window is
/// also the whole conflict story: macOS hands the same combination to every app
/// that asks for it, including ones the system itself uses, and
/// `RegisterEventHotKey` reports no error when it does. Nothing can ask whether
/// a combination is free, so the answer is to hold it for seconds rather than
/// for the session, and to keep the bar clickable either way.
final class GlobalShortcuts {
    private var refs: [EventHotKeyRef] = []
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
        for (key, action) in shortcut.keys {
            guard let ref = GlobalShortcuts.register(key: key, shortcut: shortcut, action: action) else { continue }
            refs.append(ref)
        }
        Log.write("shortcuts registered: \(shortcut.name) (\(refs.count)/2)")
    }

    func disable() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private static func register(key: UInt16, shortcut: Shortcut, action: Shortcut.Action) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(UInt32(key), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.write("RegisterEventHotKey refused \(shortcut.name) (key \(key), status \(status))")
            return nil
        }
        return ref
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
    static let homepage = URL(string: "https://github.com/GNRNicolas/eyesaver")!
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
            let fallback = URL(string: "https://github.com/\(repository)/releases/latest")
            let safePage = isGitHub(page) ? page : fallback

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

    /// A plain `hasSuffix("github.com")` would also accept `evilgithub.com`,
    /// so the host has to match exactly or sit on a real subdomain.
    static func isGitHub(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
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

// MARK: - Share card

/// The shareable card: `card.jpg` from the bundle, with the break count
/// dropped into its empty top-right corner.
///
/// Every number below is in the design's own 939x536 units and scaled to the
/// template's real pixels, so re-exporting the template at another resolution
/// changes nothing here.
enum BreakCard {
    private static let design = NSSize(width: 939, height: 536)
    private static let fontSize: CGFloat = 150
    private static let opacity: CGFloat = 0.8
    /// Measured off the reference card: the digits end this far from the right
    /// edge, and sit on this baseline.
    private static let rightMargin: CGFloat = 57.5
    private static let baselineFromTop: CGFloat = 169
    private static let cornerRadius: CGFloat = 35.5

    /// Jersey 15 is bundled, not assumed: it ships on no Mac. Registering it
    /// is a one-off, hence the lazily evaluated constant.
    private static let fontIsRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "Jersey15-Regular", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// Writes the card to a temporary file and returns it, or nil if the
    /// template or the destination is unreadable.
    static func render(breaks: Int) -> URL? {
        guard let url = Bundle.main.url(forResource: "card", withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let template = NSBitmapImageRep(data: data) else { return nil }

        // The template is exported at 144 dpi, so NSImage would report half
        // these numbers in points and the card would render at half
        // resolution. Pixels are the only honest unit here.
        let size = NSSize(width: template.pixelsWide, height: template.pixelsHigh)
        let scale = size.width / design.width

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: template.pixelsWide, pixelsHigh: template.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        // A JPEG carries no alpha, so the rounded corners have to be cut back
        // out or the card ships with four opaque ones.
        let frame = NSRect(origin: .zero, size: size)
        let radius = cornerRadius * scale
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
        template.draw(in: frame)

        _ = fontIsRegistered
        let font = NSFont(name: "Jersey 15", size: fontSize * scale)
            ?? .monospacedDigitSystemFont(ofSize: fontSize * scale, weight: .regular)
        let text = NSAttributedString(string: Format.count(breaks), attributes: [
            .font: font,
            .foregroundColor: Style.night.withAlphaComponent(opacity),
        ])
        // The two axes do not share an origin: draw(at:) takes the box corner,
        // so x offsets against the ink (size() would add the font's side
        // bearing), while y has to give back the descender to reach the
        // baseline.
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(text),
                                       NSGraphicsContext.current?.cgContext)
        text.draw(at: NSPoint(x: size.width - rightMargin * scale - ink.maxX,
                              y: size.height - baselineFromTop * scale + font.descender))

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("Eyesaver \(breaks) break\(breaks == 1 ? "" : "s").png")
        do { try png.write(to: out) } catch { return nil }
        return out
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
        // edges share one radius, and rounding the outer edge leaves a gap in
        // the square bottom corners of the display.
        ring.fillColor = Style.borderColor.cgColor
        ring.fillRule = .evenOdd
        ring.strokeColor = nil
        ring.shadowColor = Style.borderColor.cgColor
        ring.shadowOpacity = 0.7
        ring.shadowRadius = 10
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = Style.borderWidth
        let path = CGMutablePath()
        path.addRect(bounds)                                     // outer: square
        path.addPath(CGPath(roundedRect: bounds.insetBy(dx: w, dy: w),
                            cornerWidth: Style.borderInnerRadius,
                            cornerHeight: Style.borderInnerRadius,
                            transform: nil))                     // inner: rounded
        ring.frame = bounds
        ring.path = path
    }

    func startBlinking() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.12
        pulse.duration = Style.blinkPeriod
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
/// ignores the layer mask, which is what leaves a visible box around the pill.
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
        outline.strokeColor = Style.ink.withAlphaComponent(0.14).cgColor
        outline.lineWidth = 1
        layer?.addSublayer(outline)
        maskImage = PillBackground.mask(radius: Style.pillRadius)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: Style.pillRadius,
                              cornerHeight: Style.pillRadius,
                              transform: nil)
    }

    /// Stretchable image: the four corners are preserved, the centre stretches.
    private static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // Black here is opacity, not a colour: this image is a mask.
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
        let tint: NSColor = prominent ? Style.night : Style.ink.withAlphaComponent(0.92)
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
            ? (hovered ? Style.ink : Style.ink.withAlphaComponent(0.88))
            : Style.ink.withAlphaComponent(hovered ? 0.16 : 0.09)
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

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    // Built on first use rather than at startup: an app that spends most of its
    // life waiting has no reason to hold a window it has never shown.
    private lazy var skipButton = PillButton(label: "Skip", shortcut: Shortcut.current.skipLabel,
                                             prominent: false, target: self, action: #selector(skip))
    private lazy var goButton = PillButton(label: "Go", shortcut: Shortcut.current.goLabel,
                                           prominent: true, target: self, action: #selector(go))
    private lazy var panel: NSPanel = build()

    private(set) var visible = false

    private func build() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Style.pillWidth, height: Style.pillHeight),
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
        icon.contentTintColor = Style.ink.withAlphaComponent(0.75)

        title.wantsLayer = true
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Style.ink.withAlphaComponent(0.95)
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = Style.ink.withAlphaComponent(0.55)

        for field in [title, subtitle] {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let buttons = NSStackView(views: [skipButton, goButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        // Explicit constraints rather than one outer stack: with nested stacks
        // the slack of a fixed width settles wherever it likes, and the buttons
        // drift away from the right edge. Pinning both ends leaves no doubt.
        for view in [icon, labels, buttons] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),

            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),

            buttons.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            buttons.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])

        panel.contentView = background
        return panel
    }

    @objc private func skip() { delegate?.barDidSkip() }
    @objc private func go() { delegate?.barDidGo() }

    // MARK: Presentation

    func showPrompt() {
        let shortcut = Shortcut.current
        skipButton.update(label: "Skip", shortcut: shortcut.skipLabel)
        goButton.update(shortcut: shortcut.goLabel)
        goButton.isHidden = false
        title.stringValue = "Time to look away"
        subtitle.stringValue = "Rest your eyes for \(Format.duration(Settings.breakLength))"
        present()
    }

    func switchToCountdown() {
        // Same button, same name: dismissing the countdown is still a skip.
        skipButton.update(label: "Skip", shortcut: Shortcut.current.skipLabel)
        goButton.isHidden = true
        setRestingTitle(nudging: false)
        updateCountdown(Settings.breakLength)
        reposition(animated: true)
    }

    /// Calls out a break spent typing, and goes quiet again once the keyboard
    /// and mouse have been still for a moment. Cross-faded rather than swapped,
    /// so it reads as a nudge and not as an alarm.
    func setRestingTitle(nudging: Bool) {
        let wanted = nudging ? "You\u{2019}re not looking away ^^" : "Looking away"
        guard title.stringValue != wanted else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.35
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        title.layer?.add(fade, forKey: "fade")
        title.stringValue = wanted
    }

    func updateCountdown(_ remaining: TimeInterval) {
        let seconds = max(0, Int(remaining.rounded(.up)))
        subtitle.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func present() {
        reposition(animated: false)
        guard !visible else { return }
        visible = true
        panel.alphaValue = 0
        let destination = targetFrame()
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
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [self] in panel.orderOut(nil) })
    }

    /// Puts the pill back where it belongs, following the main display.
    private func reposition(animated: Bool) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let destination = targetFrame()
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

    private func targetFrame() -> NSRect {
        // Fixed, never derived from the content: the title changes length
        // during a break, and a pill that resized would drag the button with it.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        return NSRect(x: (area.midX - Style.pillWidth / 2).rounded(),
                      y: area.minY + Style.pillBottomMargin,
                      width: Style.pillWidth,
                      height: Style.pillHeight)
    }
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate, BarDelegate {
    private var statusItem: NSStatusItem!
    private let borders = Borders()
    private let bar = Bar()
    private let shortcuts = GlobalShortcuts()

    /// Seconds left before the next break. Decremented by the heartbeat rather
    /// than scheduled on a Timer, so it can simply stop while the user is away
    /// or the Mac is asleep.
    private var remaining = Settings.interval
    private var lastBeat = Date()
    private var heartbeatTimer: Timer?
    private var paused = false

    /// When the current break is due to end, and the timer that credits it.
    private var breakEnd: Date?
    private var breakTimer: Timer?

    /// Nudge state: see `shouldNudge()`.
    private var nudgeArmed = false
    private var activeSince: Date?

    /// Seconds of continuous activity during a break before the bar says so.
    private static let nudgeAfter: TimeInterval = 1
    /// Quiet seconds that clear the message again. Wider than `nudgeAfter` on
    /// purpose: without hysteresis the title would flicker between keystrokes.
    private static let nudgeClear: TimeInterval = 5

    private var lastStatusTitle = ""
    /// The share sheet is torn down as soon as its picker is released.
    private var sharePicker: NSSharingServicePicker?
    private var lastCard: URL?
    /// Test hooks, kept alive for the lifetime of the app. See `installTestHooks()`.
    private var signalSources: [DispatchSourceSignal] = []

    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private let autoUpdateItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutoUpdate), keyEquivalent: "")
    private let shareCardItem = NSMenuItem(title: "", action: #selector(shareBreakCard), keyEquivalent: "")

    private enum Phase { case idle, prompt, resting }
    private var phase: Phase = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("--- launch ---")
        bar.delegate = self
        buildMenu()
        resetInterval()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
        installTestHooks()

        // Let launch settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { Updater.check(manual: false) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.borders.visible else { return }
            self.borders.hide(); self.borders.show()
        }
    }

    /// `kill -USR1 <pid>` triggers a break, `-USR2` renders the share card.
    /// There is no other way to reach either without clicking through the menu,
    /// and waiting twenty minutes for a break makes for a poor test loop.
    private func installTestHooks() {
        let hooks: [(Int32, () -> Void)] = [
            (SIGUSR1, { [weak self] in self?.startPrompt() }),
            (SIGUSR2, {
                let url = BreakCard.render(breaks: max(1, Settings.breaksTaken))
                Log.write("share card: \(url?.path ?? "render failed")")
            }),
        ]
        for (number, handler) in hooks {
            signal(number, SIG_IGN)   // the default action is to terminate
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: handler)
            source.resume()
            signalSources.append(source)
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
        menu.addItem(menuItem("Take a Break Now", #selector(takeBreakNow)))
        menu.addItem(menuItem("Reset Timer", #selector(resetTimer)))
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(choiceMenu("Break Every", choices: durationChoices(Settings.intervalPresets),
                                selected: Int(Settings.interval), action: #selector(pickInterval(_:))))
        menu.addItem(choiceMenu("Break Length", choices: durationChoices(Settings.breakLengthPresets),
                                selected: Int(Settings.breakLength), action: #selector(pickBreakLength(_:))))
        menu.addItem(choiceMenu("Pause When Idle", choices: idleTimeoutChoices(),
                                selected: Int(Settings.idleTimeout), action: #selector(pickIdle(_:))))
        menu.addItem(choiceMenu("Sound", choices: soundChoices(),
                                selected: soundIndex(of: Settings.breakEndSound),
                                action: #selector(pickSound(_:))))
        menu.addItem(choiceMenu("Shortcuts",
                                choices: Shortcut.allCases.enumerated().map { ($1.name, $0) },
                                selected: Shortcut.allCases.firstIndex(of: Shortcut.current) ?? 0,
                                action: #selector(pickShortcut(_:))))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(autoUpdateItem)
        menu.addItem(.separator())
        menu.addItem(shareCardItem)
        menu.addItem(menuItem("Share Eyesaver", #selector(shareApp)))
        menu.addItem(menuItem("Star on GitHub", #selector(openRepository)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Eyesaver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
        refreshMenuState()
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
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

    private func durationChoices(_ values: [Int]) -> [(String, Int)] {
        values.map { (Format.duration(TimeInterval($0)), $0) }
    }

    private func idleTimeoutChoices() -> [(String, Int)] {
        Settings.idleTimeoutPresets.map { ($0 == 0 ? "Never" : "After \(Format.duration(TimeInterval($0)))", $0) }
    }

    /// Ticks the entry matching `sender` and clears its siblings.
    private func select(_ sender: NSMenuItem) {
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    private func refreshMenuState() {
        pauseItem.title = paused ? "Resume" : "Pause"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        autoUpdateItem.state = Updater.automatic ? .on : .off
        let breaks = Settings.breaksTaken
        shareCardItem.title = breaks == 0
            ? "No Breaks Taken Yet"
            : "Share my \(breaks) Break\(breaks == 1 ? "" : "s")"
        shareCardItem.isEnabled = breaks > 0
    }

    // MARK: Menu actions

    @objc private func pickInterval(_ sender: NSMenuItem) {
        Settings.interval = TimeInterval(sender.tag)
        select(sender)
        resetInterval()
    }

    @objc private func pickBreakLength(_ sender: NSMenuItem) {
        Settings.breakLength = TimeInterval(sender.tag)
        select(sender)
    }

    /// Index 0 is silence; the rest follow `Settings.soundPresets`.
    private func soundChoices() -> [(String, Int)] {
        [("Off", 0)] + Settings.soundPresets.enumerated().map { ($1, $0 + 1) }
    }

    private func soundIndex(of name: String) -> Int {
        Settings.soundPresets.firstIndex(of: name).map { $0 + 1 } ?? 0
    }

    @objc private func pickSound(_ sender: NSMenuItem) {
        let name = sender.tag == 0 ? "" : Settings.soundPresets[sender.tag - 1]
        Settings.breakEndSound = name
        select(sender)
        // Picking a sound plays it: choosing one you have never heard, and
        // waiting a full break to find out, would be a strange way to decide.
        Sound.play(name)
    }

    @objc private func pickIdle(_ sender: NSMenuItem) {
        Settings.idleTimeout = TimeInterval(sender.tag)
        select(sender)
    }

    @objc private func pickShortcut(_ sender: NSMenuItem) {
        let shortcut = Shortcut.allCases[sender.tag]
        Shortcut.current = shortcut
        select(sender)
        Log.write("shortcuts switched to \(shortcut.name)")
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

    @objc private func openRepository() { NSWorkspace.shared.open(Updater.homepage) }

    /// Renders the break count onto a card and offers it to the share sheet.
    @objc private func shareBreakCard() {
        guard Settings.breaksTaken > 0,
              let anchor = statusItem.button,
              let card = BreakCard.render(breaks: Settings.breaksTaken) else { return }
        lastCard = card
        // Messages and Mail drop a file URL that points into the temporary
        // directory: nothing is attached, and nothing is reported. An NSImage
        // goes onto the pasteboard as image data, which every service handles.
        // The URL is kept for the Download entry, which does want a file.
        guard let image = NSImage(contentsOf: card) else { return }
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: [image])
            picker.delegate = self
            self.sharePicker = picker
            picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
        }
    }

    /// Copies the card to ~/Downloads and reveals it. The share sheet has no
    /// save-to-disk entry of its own, so one is added to it.
    private func downloadCard() {
        guard let card = lastCard else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var destination = downloads.appendingPathComponent(card.lastPathComponent)
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = card.deletingPathExtension().lastPathComponent
            destination = downloads.appendingPathComponent("\(stem) \(attempt).png")
            attempt += 1
        }
        do {
            try FileManager.default.copyItem(at: card, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            Log.write("saving the card failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    /// The macOS share sheet, anchored on the menu bar item. Deferred: the
    /// picker cannot be presented while the menu it was invoked from is still
    /// tearing down.
    @objc private func shareApp() {
        guard let anchor = statusItem.button else { return }
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: [Updater.homepage])
            picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
        }
    }

    @objc private func toggleAutoUpdate() {
        Updater.automatic.toggle()
        refreshMenuState()
    }

    @objc private func takeBreakNow() { startPrompt() }
    @objc private func resetTimer() { dismiss(); resetInterval() }

    @objc private func togglePause() {
        paused.toggle()
        if paused { dismiss() } else { resetInterval() }
        refreshMenuState()
    }

    // MARK: Cycle

    private func resetInterval() {
        remaining = Settings.interval
        lastBeat = Date()
    }

    /// Raises the border and the bar, and claims the shortcuts for as long as
    /// they are on screen.
    private func startPrompt() {
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
            // Go belongs to the prompt only. During the countdown it does
            // nothing: ending a break is Skip's job, whatever the preset.
            case .go: if self.phase == .prompt { self.barDidGo() }
            }
        }
    }

    /// Skip: everything goes away and the next delay restarts from now.
    func barDidSkip() { dismiss(); resetInterval() }

    /// Go: borders go away, the bar becomes a countdown. The next delay
    /// restarts from now as well.
    func barDidGo() {
        guard phase == .prompt else { dismiss(); resetInterval(); return }
        phase = .resting
        borders.hide()
        bar.switchToCountdown()
        nudgeArmed = false
        activeSince = nil
        breakEnd = Date().addingTimeInterval(Settings.breakLength)
        breakTimer?.invalidate()
        breakTimer = Timer.scheduledTimer(withTimeInterval: Settings.breakLength, repeats: false) { [weak self] _ in
            // Only a break taken all the way through counts. Skipping out of
            // the countdown early does not.
            Settings.breaksTaken += 1
            Log.write("break completed (\(Settings.breaksTaken) total)")
            Sound.playBreakEnd()
            self?.dismiss()
        }
        resetInterval()
    }

    /// Back to waiting: no border, no bar, no shortcuts held.
    private func dismiss() {
        phase = .idle
        shortcuts.disable()
        breakTimer?.invalidate(); breakTimer = nil
        breakEnd = nil
        borders.hide()
        bar.hide()
    }

    /// True once the user has been back at the keyboard for a moment.
    private func shouldNudge() -> Bool {
        let quietFor = Activity.idleSeconds

        // Arm on the first quiet second rather than after a fixed delay: Go is
        // itself a keypress, and any grace period wide enough to cover it would
        // be arbitrary.
        guard nudgeArmed else {
            nudgeArmed = quietFor >= Self.nudgeAfter
            return false
        }
        // Still for long enough: the message can go.
        if quietFor >= Self.nudgeClear {
            activeSince = nil
            return false
        }
        // Activity just resumed: start counting how long it lasts.
        if quietFor < Self.nudgeAfter, activeSince == nil {
            activeSince = Date()
        }
        guard let since = activeSince else { return false }
        return Date().timeIntervalSince(since) >= Self.nudgeAfter
    }

    private func heartbeat() {
        if phase == .resting, let end = breakEnd {
            bar.updateCountdown(end.timeIntervalSinceNow)
            bar.setRestingTitle(nudging: shouldNudge())
        }

        // Real elapsed time, not a tick count: after the Mac sleeps the clock
        // has moved even though the heartbeat has not fired.
        let now = Date()
        let elapsed = now.timeIntervalSince(lastBeat)
        lastBeat = now
        let away = Activity.isIdle
        if phase == .idle && !paused && !away {
            remaining -= elapsed
            if remaining <= 0 { startPrompt() }
        }

        let countdown: String
        if paused {
            countdown = "paused"
        } else if phase != .idle {
            countdown = "0"
        } else if away {
            countdown = "idle"
        } else {
            // Whole minutes, rounded up: "1" while any second remains, never
            // "0" during the wait.
            countdown = "\(max(1, Int((remaining / 60).rounded(.up))))"
        }
        let title = " \(countdown)"
        if title != lastStatusTitle {
            lastStatusTitle = title
            statusItem.button?.title = title
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshMenuState() }
}

extension AppDelegate: NSSharingServicePickerDelegate {
    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        let icon = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) ?? NSImage()
        let save = NSSharingService(title: "Download", image: icon, alternateImage: nil) { [weak self] in
            self?.downloadCard()
        }
        return [save] + proposed
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
