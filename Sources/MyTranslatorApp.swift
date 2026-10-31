import Cocoa
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import FoundationModels
import NaturalLanguage
import AVFoundation

private let myTranslatorHotKeySignature: OSType = 0x4D_54_52_4E // MTRN
private let polishHotKeyIdentifier: UInt32 = 1
private let translationHotKeyIdentifier: UInt32 = 2

private enum PolishOutcome {
    case success(String)
    case failure(String)
}

private final class PolishResult {
    private let lock = NSLock()
    private var storedValue: PolishOutcome?

    func set(_ value: PolishOutcome) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func get() -> PolishOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

private func myTranslatorHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == myTranslatorHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleRegisteredHotKey(hotKeyID.id)
    return noErr
}

final class HotkeyCaptureField: NSTextField {
    private let keyNames: [UInt16: String] = [
        36: "return",
        48: "tab",
        49: "space",
        51: "delete",
        53: "escape",
        71: "clear",
        76: "enter",
        96: "f5",
        97: "f6",
        98: "f7",
        99: "f3",
        100: "f8",
        101: "f9",
        103: "f11",
        105: "f13",
        107: "f14",
        109: "f10",
        111: "f12",
        113: "f15",
        114: "help",
        115: "home",
        116: "pageup",
        117: "forwarddelete",
        118: "f4",
        119: "end",
        120: "f2",
        121: "pagedown",
        122: "f1",
        123: "left",
        124: "right",
        125: "down",
        126: "up",
        131: "f16",
        160: "f17",
        79: "f18",
        80: "f19"
    ]
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCaptureField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCaptureField()
    }

    private func configureCaptureField() {
        isEditable = false
        isSelectable = true
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        alignment = .right
        font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        textColor = WidgetStyle.text
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = WidgetStyle.elevated.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isActive = window?.firstResponder === self
        layer?.borderWidth = isActive ? 2 : 1
        layer?.borderColor = isActive
            ? WidgetStyle.accent.cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.10).cgColor

        let value = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            drawPlaceholder()
            return
        }
        drawKeyCaps(for: value)
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            startMonitoring()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        stopMonitoring()
        return super.resignFirstResponder()
    }

    private func startMonitoring() {
        stopMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.firstResponder === self else {
                return event
            }
            self.capture(event)
            return nil
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }

    func capture(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = keyName(for: event)
        if key == "escape" {
            window?.makeFirstResponder(nil)
            return
        }

        guard !key.isEmpty else {
            return
        }

        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        parts.append(key)

        stringValue = parts.joined(separator: "+")
        needsDisplay = true
    }

    private func keyName(for event: NSEvent) -> String {
        if let named = keyNames[event.keyCode] {
            return named
        }

        let chars = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard let first = chars.first else { return "" }
        return String(first)
    }

    private func drawPlaceholder() {
        let text = UILocalization.text("Type a shortcut")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WidgetStyle.font(12),
            .foregroundColor: WidgetStyle.secondary
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.maxX - size.width - 10, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func displayToken(_ token: String) -> String {
        switch token {
        case "ctrl": return "^"
        case "alt": return "⌥"
        case "shift": return "⇧"
        case "cmd": return "⌘"
        case "space": return UILocalization.text("Space")
        case "return": return "↩"
        case "tab": return "⇥"
        case "delete": return "⌫"
        case "escape": return "Esc"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return token.uppercased()
        }
    }

    private func drawKeyCaps(for value: String) {
        let tokens = value.split(separator: "+").map { displayToken(String($0)) }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let textColor = WidgetStyle.text
        let capFill = WidgetStyle.surface
        let capBorder = NSColor(calibratedWhite: 1, alpha: 0.14)

        var x = bounds.maxX - 8
        let y = bounds.midY - 9
        for token in tokens.reversed() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let textSize = token.size(withAttributes: attributes)
            let width = max(24, textSize.width + 12)
            x -= width
            let rect = NSRect(x: x, y: y, width: width, height: 18)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            capFill.setFill()
            path.fill()
            capBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
            token.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                withAttributes: attributes
            )
            x -= 4
        }
    }
}

final class OverlayResizeHandle: NSView {
    private weak var targetWindow: NSWindow?
    private var initialFrame: NSRect = .zero
    private var initialMouse: NSPoint = .zero

    init(frame: NSRect, targetWindow: NSWindow) {
        self.targetWindow = targetWindow
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        for offset in [4.0, 8.0, 12.0] {
            path.move(to: NSPoint(x: bounds.maxX - CGFloat(offset), y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + CGFloat(offset)))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let targetWindow else { return }
        initialFrame = targetWindow.frame
        initialMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let targetWindow else { return }
        let currentMouse = NSEvent.mouseLocation
        let minWidth: CGFloat = 360
        let minHeight: CGFloat = 180
        let newWidth = max(minWidth, initialFrame.width + currentMouse.x - initialMouse.x)
        let newHeight = max(minHeight, initialFrame.height - (currentMouse.y - initialMouse.y))
        let newFrame = NSRect(
            x: initialFrame.minX,
            y: initialFrame.maxY - newHeight,
            width: newWidth,
            height: newHeight
        )
        targetWindow.setFrame(newFrame, display: true)
    }
}

private enum WidgetStyle {
    static let background = NSColor(calibratedRed: 0.105, green: 0.108, blue: 0.115, alpha: 1)
    static let surface = NSColor(calibratedRed: 0.165, green: 0.170, blue: 0.180, alpha: 1)
    static let elevated = NSColor(calibratedRed: 0.215, green: 0.220, blue: 0.235, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.97, alpha: 1)
    static let secondary = NSColor(calibratedWhite: 0.68, alpha: 1)
    static let subtle = NSColor(calibratedWhite: 0.40, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1)
    static let warning = NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.42, alpha: 1)
    static let success = NSColor(calibratedRed: 0.55, green: 0.87, blue: 0.67, alpha: 1)

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func box(_ frame: NSRect, fill: NSColor = surface, radius: CGFloat = 16) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.fillColor = fill
        box.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08)
        box.borderWidth = 1
        box.cornerRadius = radius
        return box
    }

    static func stylePrimaryButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = NSColor.systemBlue.cgColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: fittingButtonFont(for: button, preferredSize: 13),
                .foregroundColor: NSColor.white
            ]
        )
    }

    static func styleSecondaryButton(_ button: NSButton, fontSize: CGFloat = 13) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = elevated.cgColor
        button.contentTintColor = text
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: fittingButtonFont(for: button, preferredSize: fontSize),
                .foregroundColor: text
            ]
        )
    }

    private static func fittingButtonFont(for button: NSButton, preferredSize: CGFloat) -> NSFont {
        var size = preferredSize
        while size > 9 && (button.title as NSString).size(withAttributes: [.font: font(size)]).width > button.frame.width - 10 {
            size -= 0.5
        }
        return font(size)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, AVSpeechSynthesizerDelegate {
    enum Config {
        static let keys = [
            "MYTRANSLATOR_HOTKEY",
            "MYTRANSLATOR_POLISH_HOTKEY",
            "MYTRANSLATOR_SOURCE_LANGUAGE",
            "MYTRANSLATOR_TARGET_LANGUAGE",
            "MYTRANSLATOR_TIMEOUT_SECONDS"
        ]

        static let defaults: [String: String] = [
            "MYTRANSLATOR_HOTKEY": "ctrl+shift+t",
            "MYTRANSLATOR_POLISH_HOTKEY": "ctrl+shift+p",
            "MYTRANSLATOR_SOURCE_LANGUAGE": "fr",
            "MYTRANSLATOR_TARGET_LANGUAGE": "en",
            "MYTRANSLATOR_TIMEOUT_SECONDS": "20"
        ]

    }

    struct LanguageOption {
        let code: String
        let label: String
    }

    struct Hotkey {
        var keyCode: CGKeyCode
        var requiresCtrl: Bool
        var requiresShift: Bool
        var requiresAlt: Bool
        var requiresCmd: Bool
    }

    var window: NSWindow!
    private var setupWindow: NSWindow?
    private var languageInfoWindow: NSWindow?
    private var translationOverlayWindow: NSWindow?
    private var translationOverlayText = ""
    private var speechSynthesizer: AVSpeechSynthesizer?
    private weak var speechButton: NSButton?
    private var hotkeyField: HotkeyCaptureField?
    private var polishHotkeyField: HotkeyCaptureField?
    private var sourceLanguagePopup: NSPopUpButton?
    private var targetLanguagePopup: NSPopUpButton?
    private var timeoutField: NSTextField?
    private weak var translationProgressIndicator: NSProgressIndicator?
    private weak var translationProgressLabel: NSTextField?
    private var normalDockIcon: NSImage?
    private var busyDockIcon: NSImage?
    private var busyDockFrames: [NSImage] = []
    private var busyDockTimer: Timer?
    private var busyDockFrameIndex = 0
    private var hotKeyEventHandler: EventHandlerRef?
    private var polishHotKeyRef: EventHotKeyRef?
    private var translationHotKeyRef: EventHotKeyRef?

    private let translationQueue = DispatchQueue(label: "com.user.mytranslator.translation")
    private var didShowTranslatorError = false

    private var hotkey: Hotkey {
        parseHotkey(configValue("MYTRANSLATOR_HOTKEY"))
    }

    private var polishHotkey: Hotkey {
        parseHotkey(configValue("MYTRANSLATOR_POLISH_HOTKEY"))
    }

    private func configValue(_ key: String) -> String {
        if let value = UserDefaults.standard.string(forKey: key),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return Config.defaults[key] ?? ""
    }

    private func configLanguageCode(_ key: String) -> String {
        let fallback = Config.defaults[key] ?? ""
        return Self.languageCode(configValue(key), fallback: fallback)
    }

    private func l(_ english: String) -> String {
        UILocalization.text(english, language: configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE"))
    }

    private func configTimeoutSeconds() -> Int {
        let raw = configValue("MYTRANSLATOR_TIMEOUT_SECONDS")
        let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 20
        return min(300, max(3, parsed))
    }

    private func hotkeyMatches(_ hotkey: Hotkey, keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == hotkey.keyCode
            && flags.contains(.maskControl) == hotkey.requiresCtrl
            && flags.contains(.maskShift) == hotkey.requiresShift
            && flags.contains(.maskAlternate) == hotkey.requiresAlt
            && flags.contains(.maskCommand) == hotkey.requiresCmd
    }

    private static func languageCode(_ raw: String, fallback: String = "") -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: String] = [
            "en": "en", "en-au": "en", "en-ca": "en", "en-gb": "en", "en-ie": "en", "en-in": "en", "en-nz": "en", "en-sg": "en", "en-za": "en", "english": "en", "anglais": "en",
            "fr": "fr", "fr-ca": "fr", "french": "fr", "français": "fr", "francais": "fr",
            "es": "es", "es-mx": "es", "es-us": "es", "spanish": "es", "espagnol": "es",
            "de": "de", "de-ch": "de", "german": "de", "allemand": "de",
            "it": "it", "it-ch": "it", "italian": "it", "italien": "it",
            "pt": "pt", "pt-pt": "pt", "portuguese": "pt", "portugais": "pt",
            "nl": "nl", "dutch": "nl", "néerlandais": "nl", "neerlandais": "nl",
            "ru": "ru", "russian": "ru", "russe": "ru",
            "zh": "zh-Hans", "zh-hans": "zh-Hans", "simplified chinese": "zh-Hans", "chinois": "zh-Hans",
            "zh-hant": "zh-Hant", "zh-hk": "zh-Hant", "zh-tw": "zh-Hant", "traditional chinese": "zh-Hant",
            "ja": "ja", "japanese": "ja", "japonais": "ja",
            "ko": "ko", "korean": "ko", "coréen": "ko", "coreen": "ko",
            "ar": "ar", "arabic": "ar", "arabe": "ar",
            "hi": "hi", "hindi": "hi",
            "bn": "bn", "bengali": "bn",
            "ur": "ur", "urdu": "ur",
            "tr": "tr", "turkish": "tr", "turc": "tr",
            "pl": "pl", "polish": "pl", "polonais": "pl",
            "sv": "sv", "swedish": "sv", "suédois": "sv", "suedois": "sv",
            "no": "no", "norwegian": "no",
            "nb": "nb", "norvégien bokmål": "nb", "norvegien bokmal": "nb",
            "da": "da", "danish": "da", "danois": "da",
            "fi": "fi", "finnish": "fi", "finnois": "fi",
            "el": "el", "greek": "el", "grec": "el",
            "he": "he", "hebrew": "he", "hébreu": "he", "hebreu": "he",
            "th": "th", "thai": "th", "thaï": "th",
            "vi": "vi", "vietnamese": "vi", "vietnamien": "vi",
            "id": "id", "indonesian": "id", "indonésien": "id", "indonesien": "id",
            "ms": "ms", "malay": "ms",
            "cs": "cs", "czech": "cs",
            "ro": "ro", "romanian": "ro", "roumain": "ro"
        ]
        return map[key] ?? (key.isEmpty ? fallback : raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func languageLabel(_ code: String) -> String {
        let normalized = languageCode(code)
        let labels: [String: String] = [
            "en": "English",
            "fr": "French",
            "es": "Spanish",
            "de": "German",
            "it": "Italian",
            "pt": "Portuguese",
            "nl": "Dutch",
            "ru": "Russian",
            "zh-Hans": "Simplified Chinese",
            "zh-Hant": "Traditional Chinese",
            "ja": "Japanese",
            "ko": "Korean",
            "ar": "Arabic",
            "hi": "Hindi",
            "bn": "Bengali",
            "ur": "Urdu",
            "tr": "Turkish",
            "pl": "Polish",
            "sv": "Swedish",
            "no": "Norwegian",
            "nb": "Norwegian Bokmal",
            "da": "Danish",
            "fi": "Finnish",
            "el": "Greek",
            "he": "Hebrew",
            "th": "Thai",
            "vi": "Vietnamese",
            "id": "Indonesian",
            "ms": "Malay",
            "cs": "Czech",
            "ro": "Romanian"
        ]
        return labels[normalized] ?? Locale.current.localizedString(forLanguageCode: normalized) ?? normalized
    }

    private static func displayLanguageLabel(_ code: String) -> String {
        let locale = Locale(identifier: UILocalization.currentLanguage.replacingOccurrences(of: "-", with: "_"))
        if languageCode(code).hasPrefix("zh") {
            return locale.localizedString(forLanguageCode: "zh")?.capitalized(with: locale) ?? "Chinese"
        }
        return locale.localizedString(forIdentifier: languageCode(code))?.capitalized(with: locale)
            ?? languageLabel(code)
    }

    private func saveConfig(_ values: [String: String]) throws {
        let defaults = UserDefaults.standard
        for key in Config.keys {
            var value = (values[key] ?? Config.defaults[key] ?? "")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "MYTRANSLATOR_SOURCE_LANGUAGE" || key == "MYTRANSLATOR_TARGET_LANGUAGE" {
                value = Self.languageCode(value, fallback: Config.defaults[key] ?? "")
            } else if key == "MYTRANSLATOR_TIMEOUT_SECONDS" {
                let parsed = Int(value) ?? Int(Config.defaults[key] ?? "20") ?? 20
                value = String(min(300, max(3, parsed)))
            }
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
    }

    func keyCodeForHotkeyKey(_ key: String) -> CGKeyCode {
        if key.count == 1, let scalar = key.unicodeScalars.first {
            let map: [UnicodeScalar: CGKeyCode] = [
                "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
                "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
                "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
                "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
                "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47
            ]
            if let code = map[scalar] {
                return code
            }
        }

        let named: [String: CGKeyCode] = [
            "return": 36,
            "tab": 48,
            "space": 49,
            "delete": 51,
            "escape": 53,
            "enter": 76,
            "left": 123,
            "right": 124,
            "down": 125,
            "up": 126,
            "f1": 122,
            "f2": 120,
            "f3": 99,
            "f4": 118,
            "f5": 96,
            "f6": 97,
            "f7": 98,
            "f8": 100,
            "f9": 101,
            "f10": 109,
            "f11": 103,
            "f12": 111,
            "f13": 105,
            "f14": 107,
            "f15": 113,
            "f16": 131,
            "f17": 160,
            "f18": 79,
            "f19": 80
        ]
        return named[key] ?? 79
    }

    func parseHotkey(_ raw: String) -> Hotkey {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "f18" {
            return Hotkey(keyCode: 79, requiresCtrl: false, requiresShift: false, requiresAlt: false, requiresCmd: false)
        }

        let parts = value.split(separator: "+")
        var ctrl = false
        var shift = false
        var alt = false
        var cmd = false
        var key: CGKeyCode = 79

        for part in parts {
            switch part {
            case "ctrl", "control": ctrl = true
            case "shift": shift = true
            case "alt", "option": alt = true
            case "cmd", "command": cmd = true
            default: key = keyCodeForHotkeyKey(String(part))
            }
        }

        return Hotkey(keyCode: key, requiresCtrl: ctrl, requiresShift: shift, requiresAlt: alt, requiresCmd: cmd)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureDockIcons()
        buildMenu()
        buildWindow()
        setupEventTap()
    }

    func configureDockIcons() {
        let baseIcon: NSImage
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            baseIcon = icon
        } else {
            baseIcon = NSApp.applicationIconImage
        }

        normalDockIcon = baseIcon
        if let iconPath = Bundle.main.path(forResource: "BusyIcon", ofType: "png"),
           let icon = NSImage(contentsOfFile: iconPath) {
            busyDockIcon = icon
            busyDockFrames = animatedBusyDockFrames(icon)
        }
        NSApp.applicationIconImage = baseIcon
    }

    func animatedBusyDockFrames(_ icon: NSImage) -> [NSImage] {
        let size = NSSize(width: 512, height: 512)
        let dotCenters: [CGFloat] = [0.543, 0.628, 0.713]
        let brightness: [CGFloat] = [0.85, 0.55, 0.12, 0.12, 0.12, 0.55]

        return (0..<6).map { frameIndex in
            let frame = NSImage(size: size)
            frame.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero, operation: .sourceOver, fraction: 1)

            for (dotIndex, centerX) in dotCenters.enumerated() {
                let phase = (frameIndex - dotIndex * 2 + 6) % 6
                NSColor.white.withAlphaComponent(brightness[phase]).setFill()
                let diameter = size.width * 0.052
                let rect = NSRect(x: size.width * centerX - diameter / 2,
                                  y: size.height * 0.437 - diameter / 2,
                                  width: diameter, height: diameter)
                NSBezierPath(ovalIn: rect).fill()
            }

            frame.unlockFocus()
            frame.isTemplate = false
            return frame
        }
    }

    func setDockIconBusy(_ busy: Bool) {
        DispatchQueue.main.async { [self] in
            if busy {
                guard let busyDockIcon = self.busyDockIcon else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || self.busyDockFrames.isEmpty {
                    NSApp.applicationIconImage = busyDockIcon
                    return
                }
                guard self.busyDockTimer == nil else { return }
                self.busyDockFrameIndex = 0
                NSApp.applicationIconImage = self.busyDockFrames[0]
                self.busyDockTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] timer in
                    guard let self else {
                        timer.invalidate()
                        return
                    }
                    self.busyDockFrameIndex = (self.busyDockFrameIndex + 1) % self.busyDockFrames.count
                    NSApp.applicationIconImage = self.busyDockFrames[self.busyDockFrameIndex]
                }
                self.busyDockTimer?.tolerance = 0.03
            } else {
                self.busyDockTimer?.invalidate()
                self.busyDockTimer = nil
                self.busyDockFrameIndex = 0
                if let normalDockIcon = self.normalDockIcon {
                    NSApp.applicationIconImage = normalDockIcon
                }
            }
        }
    }

    func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "MyTranslator")
        appMenu.addItem(withTitle: l("About MyTranslator"), action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: l("Settings"), action: #selector(showSetup), keyEquivalent: ",")
        appMenu.addItem(withTitle: l("Close Windows"), action: #selector(closeWindows), keyEquivalent: "w")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: l("Quit MyTranslator"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: l("Edit"))
        editMenu.addItem(withTitle: l("Undo"), action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: l("Redo"), action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: l("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: l("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: l("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: l("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowsMenuItem = NSMenuItem()
        mainMenu.addItem(windowsMenuItem)
        let windowsMenu = NSMenu(title: l("Windows"))
        windowsMenu.addItem(withTitle: l("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowsMenu.addItem(withTitle: l("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowsMenu.addItem(NSMenuItem.separator())
        windowsMenu.addItem(withTitle: l("Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowsMenuItem.submenu = windowsMenu
        NSApp.windowsMenu = windowsMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: l("Help"))
        helpMenu.addItem(withTitle: l("MyTranslator User Guide (English)"), action: #selector(openUserGuide), keyEquivalent: "?")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    func buildWindow(preserving frame: NSRect? = nil) {
        let primaryLanguage = Self.displayLanguageLabel(configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE"))
        let translationLanguage = Self.displayLanguageLabel(configLanguageCode("MYTRANSLATOR_TARGET_LANGUAGE"))
        let translationShortcutLabel = formatShortcut(configValue("MYTRANSLATOR_HOTKEY"))
        let polishShortcutLabel = formatShortcut(configValue("MYTRANSLATOR_POLISH_HOTKEY"))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 304),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MyTranslator"
        window.minSize = NSSize(width: 340, height: 304)
        window.isReleasedWhenClosed = false
        if let frame {
            window.setContentSize(NSSize(width: 340, height: 304))
            window.setFrameOrigin(frame.origin)
        } else {
            window.center()
        }
        window.delegate = self
        window.backgroundColor = WidgetStyle.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        let cv = window.contentView!
        cv.wantsLayer = true
        cv.layer?.backgroundColor = WidgetStyle.background.cgColor
        func label(_ value: String, frame: NSRect, size: CGFloat,
                   weight: NSFont.Weight = .regular, color: NSColor = WidgetStyle.text) -> NSTextField {
            let field = NSTextField(labelWithString: value)
            field.frame = frame
            field.font = WidgetStyle.font(size, weight: weight)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            cv.addSubview(field)
            return field
        }

        _ = label("MyTranslator", frame: NSRect(x: 22, y: 245, width: 205, height: 25),
                  size: 19, weight: .bold)
        _ = label("\(primaryLanguage)  ↔  \(translationLanguage)",
                  frame: NSRect(x: 22, y: 221, width: 250, height: 19),
                  size: 12, weight: .medium, color: WidgetStyle.secondary)

        let appIcon = NSImageView(frame: NSRect(x: 280, y: 226, width: 40, height: 40))
        appIcon.image = normalDockIcon
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.setAccessibilityLabel("MyTranslator")
        cv.addSubview(appIcon)

        let settings = NSButton(title: l("Settings"), target: self, action: #selector(showSetup))
        settings.frame = NSRect(x: 66, y: 21, width: 80, height: 24)
        settings.bezelStyle = .rounded
        settings.font = WidgetStyle.font(13)
        WidgetStyle.styleSecondaryButton(settings)
        settings.toolTip = l("Settings")
        cv.addSubview(settings)

        let hideButton = NSButton(title: l("Hide"), target: self, action: #selector(minimizeMainWindow))
        hideButton.frame = NSRect(x: 242, y: 21, width: 80, height: 24)
        hideButton.bezelStyle = .rounded
        hideButton.keyEquivalent = "\r"
        hideButton.font = WidgetStyle.font(13)
        WidgetStyle.stylePrimaryButton(hideButton)
        hideButton.toolTip = l("Minimize the window without quitting the app")
        cv.addSubview(hideButton)

        let quitButton = NSButton(title: l("Quit"), target: self, action: #selector(quitApp))
        quitButton.frame = NSRect(x: 154, y: 21, width: 80, height: 24)
        quitButton.bezelStyle = .rounded
        quitButton.font = WidgetStyle.font(13)
        WidgetStyle.styleSecondaryButton(quitButton)
        quitButton.toolTip = l("Quit MyTranslator")
        cv.addSubview(quitButton)

        let timeline = NSView(frame: NSRect(x: 29, y: 110, width: 1, height: 72))
        timeline.wantsLayer = true
        timeline.layer?.backgroundColor = WidgetStyle.subtle.cgColor
        cv.addSubview(timeline)
        for y in [176.0, 104.0] {
            let node = NSView(frame: NSRect(x: 24, y: y, width: 11, height: 11))
            node.wantsLayer = true
            node.layer?.cornerRadius = 5.5
            node.layer?.backgroundColor = WidgetStyle.text.cgColor
            node.layer?.borderWidth = 3
            node.layer?.borderColor = WidgetStyle.elevated.cgColor
            cv.addSubview(node)
        }

        _ = label(l("Translate"), frame: NSRect(x: 48, y: 172, width: 170, height: 21),
                  size: 15, weight: .semibold)
        _ = label(l("Replace or show the result"),
                  frame: NSRect(x: 48, y: 150, width: 257, height: 17),
                  size: 11, color: WidgetStyle.secondary)
        let translateKey = label(translationShortcutLabel, frame: NSRect(x: 232, y: 173, width: 86, height: 18),
                                 size: 11, weight: .semibold, color: WidgetStyle.accent)
        translateKey.alignment = .right
        _ = label(l("Improve"), frame: NSRect(x: 48, y: 100, width: 170, height: 21),
                  size: 15, weight: .semibold)
        _ = label(l("In the original language"), frame: NSRect(x: 48, y: 78, width: 250, height: 17),
                  size: 11, color: WidgetStyle.secondary)
        let polishKey = label(polishShortcutLabel, frame: NSRect(x: 232, y: 101, width: 86, height: 18),
                              size: 11, weight: .semibold, color: WidgetStyle.accent)
        polishKey.alignment = .right

        let divider = NSView(frame: NSRect(x: 22, y: 59, width: 296, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = WidgetStyle.elevated.cgColor
        cv.addSubview(divider)
        let spinner = NSProgressIndicator(frame: NSRect(x: 22, y: 24, width: 17, height: 17))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        cv.addSubview(spinner)
        translationProgressIndicator = spinner

        let progressLabel = label(l("Working…"), frame: NSRect(x: 47, y: 25, width: 145, height: 17),
                                  size: 10, weight: .medium, color: WidgetStyle.secondary)
        progressLabel.isHidden = true
        translationProgressLabel = progressLabel

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setTranslationInProgress(_ inProgress: Bool) {
        setDockIconBusy(inProgress)

        let update = {
            let indicator = self.translationProgressIndicator
            indicator?.isHidden = !inProgress
            self.translationProgressLabel?.isHidden = !inProgress
            if inProgress {
                indicator?.startAnimation(nil)
            } else {
                indicator?.stopAnimation(nil)
            }
        }

        if Thread.isMainThread {
            update()
        } else if inProgress {
            DispatchQueue.main.sync(execute: update)
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func minimizeMainWindow() {
        window?.performMiniaturize(nil)
    }

    @objc func closeWindows() {
        setupWindow?.orderOut(nil)
        window?.orderOut(nil)
    }

    @objc func showAbout() {
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        var versionText = "\(l("Build")) \(buildNumber)"
        if let buildDate = Bundle.main.object(forInfoDictionaryKey: "MyTranslatorBuildDate") as? String {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            if let date = parser.date(from: buildDate) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE"))
                formatter.dateStyle = .medium
                versionText += " (\(formatter.string(from: date)))"
            }
        }
        let alert = NSAlert()
        alert.messageText = "MyTranslator"
        alert.informativeText = versionText
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            alert.icon = icon
        }
        alert.addButton(withTitle: l("OK"))
        alert.runModal()
    }

    @objc func openUserGuide() {
        guard let path = Bundle.main.path(forResource: "UserGuide", ofType: "html") else {
            showTranslatorError(l("The user guide is missing from the app."))
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func refreshMainWindow() {
        let oldWindow = window
        let frame = oldWindow?.frame
        oldWindow?.delegate = nil
        oldWindow?.close()
        buildWindow(preserving: frame)
    }

    func supportedLanguageOptions() -> [LanguageOption] {
        let codes = ["ar", "da", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nb", "nl", "pl", "pt", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans"]
        return codes
            .map { LanguageOption(code: $0, label: Self.languageLabel($0)) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    @objc func showLanguageInstallInfo() {
        if let languageInfoWindow {
            languageInfoWindow.makeKeyAndOrderFront(nil)
            return
        }

        let info = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        info.title = l("Offline languages")
        info.titleVisibility = .hidden
        info.titlebarAppearsTransparent = true
        info.backgroundColor = WidgetStyle.background
        info.appearance = NSAppearance(named: .darkAqua)
        info.isMovableByWindowBackground = true
        info.isReleasedWhenClosed = false
        info.delegate = self
        info.standardWindowButton(.miniaturizeButton)?.isHidden = true
        info.standardWindowButton(.zoomButton)?.isHidden = true

        let cv = NSView(frame: info.contentView!.bounds)
        cv.wantsLayer = true
        cv.layer?.backgroundColor = WidgetStyle.background.cgColor
        info.contentView = cv

        func label(_ value: String, frame: NSRect, size: CGFloat,
                   weight: NSFont.Weight = .regular, color: NSColor = WidgetStyle.text) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value)
            field.frame = frame
            field.font = WidgetStyle.font(size, weight: weight)
            field.textColor = color
            cv.addSubview(field)
            return field
        }

        let icon = NSImageView(frame: NSRect(x: 22, y: 286, width: 22, height: 22))
        icon.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: l("Information"))
        icon.contentTintColor = WidgetStyle.accent
        cv.addSubview(icon)
        _ = label(l("Offline languages"), frame: NSRect(x: 52, y: 282, width: 340, height: 28),
                  size: 19, weight: .semibold)
        _ = label(l("Apple Translation uses languages downloaded on this Mac."),
                  frame: NSRect(x: 22, y: 237, width: 376, height: 38),
                  size: 12, color: WidgetStyle.secondary)

        cv.addSubview(WidgetStyle.box(NSRect(x: 18, y: 82, width: 384, height: 146)))
        _ = label(l("The lists show the 22 languages supported by Apple Translation. Some require a download before offline use."),
                  frame: NSRect(x: 34, y: 166, width: 350, height: 56), size: 12)
        _ = label(l("To use a language that is not installed, download it in Apple Translate for offline use. You can manage downloaded languages in its settings."),
                  frame: NSRect(x: 34, y: 95, width: 350, height: 68), size: 12)
        _ = label(l("Reopen this window after installation."),
                  frame: NSRect(x: 22, y: 56, width: 376, height: 18),
                  size: 11, color: WidgetStyle.secondary)

        let okButton = NSButton(title: l("OK"), target: self, action: #selector(closeLanguageInstallInfo))
        okButton.bezelStyle = .rounded
        okButton.font = WidgetStyle.font(12)
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: 310, y: 17, width: 92, height: 32)
        cv.addSubview(okButton)

        if let setupWindow {
            info.setFrameOrigin(NSPoint(x: setupWindow.frame.midX - 210, y: setupWindow.frame.midY - 175))
            setupWindow.addChildWindow(info, ordered: .above)
        } else {
            info.center()
        }
        languageInfoWindow = info
        info.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeLanguageInstallInfo() {
        languageInfoWindow?.close()
    }

    @objc func showSetup() {
        unregisterGlobalHotkeys()

        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 516),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "\(l("Settings")) MyTranslator"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = WidgetStyle.background
        win.appearance = NSAppearance(named: .darkAqua)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true

        let cv = NSView(frame: win.contentView!.bounds)
        cv.autoresizingMask = [.width, .height]
        cv.wantsLayer = true
        cv.layer?.backgroundColor = WidgetStyle.background.cgColor
        win.contentView = cv

        func label(_ text: String, frame: NSRect, size: CGFloat = 13,
                   weight: NSFont.Weight = .regular, color: NSColor = WidgetStyle.text) -> NSTextField {
            let tf = NSTextField(labelWithString: text)
            tf.font = WidgetStyle.font(size, weight: weight)
            tf.textColor = color
            tf.frame = frame
            tf.lineBreakMode = .byTruncatingTail
            cv.addSubview(tf)
            return tf
        }

        func card(_ frame: NSRect) {
            cv.addSubview(WidgetStyle.box(frame))
        }

        _ = label(l("Settings"), frame: NSRect(x: 22, y: 452, width: 300, height: 28),
                  size: 21, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: l("The primary language is the default destination. Text already in that language is translated into the other language."))
        subtitle.font = WidgetStyle.font(11)
        subtitle.textColor = WidgetStyle.secondary
        subtitle.frame = NSRect(x: 22, y: 414, width: 416, height: 33)
        cv.addSubview(subtitle)

        _ = label(l("Languages"), frame: NSRect(x: 22, y: 391, width: 180, height: 18),
                  size: 12, weight: .semibold, color: WidgetStyle.secondary)
        card(NSRect(x: 18, y: 286, width: 424, height: 99))
        _ = label(l("Primary"), frame: NSRect(x: 36, y: 346, width: 135, height: 20), weight: .medium)
        _ = label(l("Other language"), frame: NSRect(x: 36, y: 303, width: 135, height: 20), weight: .medium)

        let supportedLanguages = supportedLanguageOptions()

        func populateLanguagePopup(_ popup: NSPopUpButton, selectedCode: String, options: [LanguageOption]) {
            popup.removeAllItems()
            var seen = Set<String>()
            let normalizedSelection = selectedCode == "zh-Hant" ? "zh-Hans" : selectedCode
            let sortedOptions = options.sorted {
                Self.displayLanguageLabel($0.code).localizedCaseInsensitiveCompare(Self.displayLanguageLabel($1.code)) == .orderedAscending
            }
            for option in sortedOptions where !seen.contains(option.code) {
                seen.insert(option.code)
                popup.addItem(withTitle: Self.displayLanguageLabel(option.code))
                popup.lastItem?.representedObject = option.code
            }
            if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == normalizedSelection }) {
                popup.selectItem(at: index)
            } else {
                popup.selectItem(at: 0)
            }
        }

        func languagePopup(_ value: String, y: CGFloat) -> NSPopUpButton {
            let popup = NSPopUpButton(frame: NSRect(x: 185, y: y - 4, width: 236, height: 29), pullsDown: false)
            populateLanguagePopup(popup, selectedCode: value, options: supportedLanguages)
            cv.addSubview(popup)
            return popup
        }

        sourceLanguagePopup = languagePopup(configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE"), y: 346)
        targetLanguagePopup = languagePopup(configLanguageCode("MYTRANSLATOR_TARGET_LANGUAGE"), y: 303)

        let infoButton = NSButton(title: "", target: self, action: #selector(showLanguageInstallInfo))
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: l("Languages"))
        infoButton.isBordered = false
        infoButton.toolTip = l("Manage installed Apple Translation languages")
        infoButton.frame = NSRect(x: 407, y: 387, width: 26, height: 24)
        infoButton.contentTintColor = WidgetStyle.secondary
        cv.addSubview(infoButton)

        _ = label(l("Shortcuts"), frame: NSRect(x: 22, y: 262, width: 180, height: 18),
                  size: 12, weight: .semibold, color: WidgetStyle.secondary)
        card(NSRect(x: 18, y: 151, width: 424, height: 105))
        _ = label(l("Improve"), frame: NSRect(x: 36, y: 213, width: 135, height: 20), weight: .medium)
        _ = label(l("Translate"), frame: NSRect(x: 36, y: 166, width: 135, height: 20), weight: .medium)

        let polishHotkeyCapture = HotkeyCaptureField(string: configValue("MYTRANSLATOR_POLISH_HOTKEY"))
        polishHotkeyCapture.frame = NSRect(x: 185, y: 209, width: 236, height: 28)
        polishHotkeyCapture.toolTip = l("Click and type the new Improve shortcut.")
        cv.addSubview(polishHotkeyCapture)
        polishHotkeyField = polishHotkeyCapture

        let hotkeyCapture = HotkeyCaptureField(string: configValue("MYTRANSLATOR_HOTKEY"))
        hotkeyCapture.frame = NSRect(x: 185, y: 162, width: 236, height: 28)
        hotkeyCapture.toolTip = l("Click and type the new Translate shortcut.")
        cv.addSubview(hotkeyCapture)
        hotkeyField = hotkeyCapture

        _ = label(l("Advanced"), frame: NSRect(x: 22, y: 126, width: 180, height: 18),
                  size: 12, weight: .semibold, color: WidgetStyle.secondary)
        card(NSRect(x: 18, y: 69, width: 424, height: 51))
        _ = label(l("Timeout"), frame: NSRect(x: 36, y: 85, width: 135, height: 20), weight: .medium)
        let timeoutInput = NSTextField(frame: NSRect(x: 185, y: 80, width: 70, height: 28))
        timeoutInput.integerValue = configTimeoutSeconds()
        timeoutInput.alignment = .right
        timeoutInput.formatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.minimum = 3
            formatter.maximum = 300
            formatter.allowsFloats = false
            return formatter
        }()
        timeoutInput.toolTip = l("Maximum wait: 3 to 300 seconds.")
        timeoutInput.font = WidgetStyle.font(13)
        timeoutInput.backgroundColor = WidgetStyle.elevated
        timeoutInput.textColor = WidgetStyle.text
        cv.addSubview(timeoutInput)
        timeoutField = timeoutInput

        _ = label(l("seconds"), frame: NSRect(x: 266, y: 85, width: 100, height: 18),
                  size: 11, color: WidgetStyle.secondary)

        let saveButton = NSButton(title: l("Save"), target: self, action: #selector(saveSetup))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.font = WidgetStyle.font(13)
        saveButton.frame = NSRect(x: 362, y: 25, width: 80, height: 24)
        WidgetStyle.stylePrimaryButton(saveButton)
        cv.addSubview(saveButton)

        let cancelButton = NSButton(title: l("Cancel"), target: self, action: #selector(closeSetup))
        cancelButton.bezelStyle = .rounded
        cancelButton.font = WidgetStyle.font(13)
        cancelButton.frame = NSRect(x: 274, y: 25, width: 80, height: 24)
        WidgetStyle.styleSecondaryButton(cancelButton)
        cv.addSubview(cancelButton)

        setupWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

    }

    @objc func closeSetup() {
        languageInfoWindow?.close()
        if let setupWindow {
            setupWindow.close()
        } else {
            setupEventTap()
        }
    }

    @objc func saveSetup() {
        let values: [String: String] = [
            "MYTRANSLATOR_HOTKEY": hotkeyField?.stringValue ?? Config.defaults["MYTRANSLATOR_HOTKEY"]!,
            "MYTRANSLATOR_POLISH_HOTKEY": polishHotkeyField?.stringValue ?? Config.defaults["MYTRANSLATOR_POLISH_HOTKEY"]!,
            "MYTRANSLATOR_SOURCE_LANGUAGE": (sourceLanguagePopup?.selectedItem?.representedObject as? String) ?? Config.defaults["MYTRANSLATOR_SOURCE_LANGUAGE"]!,
            "MYTRANSLATOR_TARGET_LANGUAGE": (targetLanguagePopup?.selectedItem?.representedObject as? String) ?? Config.defaults["MYTRANSLATOR_TARGET_LANGUAGE"]!,
            "MYTRANSLATOR_TIMEOUT_SECONDS": String(min(300, max(3, timeoutField?.integerValue ?? configTimeoutSeconds())))
        ]

        do {
            try saveConfig(values)
            closeSetup()
            buildMenu()
            refreshMainWindow()
        } catch {
            fputs("MyTranslator settings error: \(error)\n", stderr)
            let a = NSAlert()
            a.messageText = l("Unable to save settings")
            a.alertStyle = .warning
            a.addButton(withTitle: l("OK"))
            a.runModal()
        }
    }

    func formatShortcut(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "F18" }

        let parts = value.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count <= 1 { return value.uppercased() }

        let mapped = parts.map { part -> String in
            switch part.lowercased() {
            case "ctrl", "control": return "⌃"
            case "shift": return "⇧"
            case "alt", "option": return "⌥"
            case "cmd", "command": return "⌘"
            default: return part.uppercased()
            }
        }
        return mapped.joined(separator: " ")
    }

    func setupEventTap() {
        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(accessibilityOptions) else {
            showAccessibilityAlert()
            return
        }

        unregisterGlobalHotkeys()

        if hotKeyEventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                myTranslatorHotKeyHandler,
                1,
                &eventType,
                selfPtr,
                &hotKeyEventHandler
            )
            guard handlerStatus == noErr else {
                showHotkeyRegistrationAlert("\(l("Unable to initialize global shortcuts.")) (\(handlerStatus))")
                return
            }
        }

        let polishStatus = registerGlobalHotkey(
            polishHotkey,
            identifier: polishHotKeyIdentifier,
            reference: &polishHotKeyRef
        )
        let translationStatus = registerGlobalHotkey(
            hotkey,
            identifier: translationHotKeyIdentifier,
            reference: &translationHotKeyRef
        )
        if polishStatus != noErr || translationStatus != noErr {
            showHotkeyRegistrationAlert(
                l("One of the shortcuts is already used by macOS or another app. Choose another shortcut in Settings.")
            )
        }
    }

    func carbonModifiers(for hotkey: Hotkey) -> UInt32 {
        var modifiers: UInt32 = 0
        if hotkey.requiresCtrl { modifiers |= UInt32(controlKey) }
        if hotkey.requiresShift { modifiers |= UInt32(shiftKey) }
        if hotkey.requiresAlt { modifiers |= UInt32(optionKey) }
        if hotkey.requiresCmd { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    func registerGlobalHotkey(
        _ hotkey: Hotkey,
        identifier: UInt32,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: myTranslatorHotKeySignature, id: identifier)
        return RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers(for: hotkey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
    }

    func unregisterGlobalHotkeys() {
        if let polishHotKeyRef {
            UnregisterEventHotKey(polishHotKeyRef)
            self.polishHotKeyRef = nil
        }
        if let translationHotKeyRef {
            UnregisterEventHotKey(translationHotKeyRef)
            self.translationHotKeyRef = nil
        }
    }

    func handleRegisteredHotKey(_ identifier: UInt32) {
        let action: TextAction
        switch identifier {
        case polishHotKeyIdentifier:
            action = .polish
        case translationHotKeyIdentifier:
            action = .translate
        default:
            return
        }
        translationQueue.async { self.handleTextAction(action) }
    }

    func showHotkeyRegistrationAlert(_ details: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = self.l("Shortcut unavailable")
            alert.informativeText = details
            alert.alertStyle = .warning
            alert.addButton(withTitle: self.l("Open Settings"))
            alert.addButton(withTitle: self.l("Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                self.showSetup()
            }
        }
    }

    func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = self.l("Accessibility permission required")
            a.informativeText = self.l("Enable MyTranslator in System Settings → Privacy & Security → Accessibility. If it is already listed, remove the old entry, add this app again, and restart it.")
            a.alertStyle = .warning
            a.addButton(withTitle: self.l("Open Settings"))
            a.addButton(withTitle: self.l("Later"))
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    @objc func closeTranslationOverlay() {
        stopSpeakingTranslation()
        translationOverlayWindow?.orderOut(nil)
        translationOverlayWindow = nil
        translationOverlayText = ""
        speechButton = nil
    }

    @objc func copyTranslationOverlayText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translationOverlayText, forType: .string)
    }

    @objc func toggleSpeakTranslation() {
        if speechSynthesizer?.isSpeaking == true {
            stopSpeakingTranslation()
            return
        }

        let text = translationOverlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: text)
        speechSynthesizer = synthesizer
        configureSpeechButton(isSpeaking: true)
        synthesizer.speak(utterance)
    }

    func stopSpeakingTranslation() {
        speechSynthesizer?.stopSpeaking(at: .immediate)
        speechSynthesizer?.delegate = nil
        speechSynthesizer = nil
        configureSpeechButton(isSpeaking: false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.speechSynthesizer === synthesizer else { return }
            self.speechSynthesizer = nil
            self.configureSpeechButton(isSpeaking: false)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.speechSynthesizer === synthesizer else { return }
            self.speechSynthesizer = nil
            self.configureSpeechButton(isSpeaking: false)
        }
    }

    func configureSpeechButton(isSpeaking: Bool) {
        speechButton?.title = isSpeaking ? l("Stop") : l("Listen")
        speechButton?.image = NSImage(
            systemSymbolName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
            accessibilityDescription: isSpeaking ? l("Stop") : l("Listen")
        )
        speechButton?.imagePosition = .imageLeft
        speechButton?.imageHugsTitle = true
        speechButton?.toolTip = isSpeaking ? l("Stop playback") : l("Listen to the text")
        if let speechButton {
            WidgetStyle.styleSecondaryButton(speechButton, fontSize: 11)
        }
    }

    func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage?.rawValue else {
            return nil
        }

        let normalized = Self.languageCode(language)
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        let matchingVoice = availableVoices.first { voice in
            let locale = voice.language
            let voiceLanguage = Self.languageCode(locale)
            return voiceLanguage == normalized || locale.lowercased().hasPrefix(normalized.lowercased() + "-")
        }
        return matchingVoice
    }

    func detectedTextLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let rawLanguage = recognizer.dominantLanguage?.rawValue else {
            return nil
        }
        let normalized = Self.languageCode(rawLanguage)
        return normalized.isEmpty ? nil : normalized
    }

    func polishPrompt(for text: String, languageCode: String?, retry: Bool) -> String {
        let languageDescription: String
        if let languageCode {
            languageDescription = "\(Self.languageLabel(languageCode)) (\(languageCode))"
        } else {
            languageDescription = "the exact same language as the input"
        }

        let strictPrefix = retry
            ? "Previous output used the wrong language. "
            : ""

        return """
        \(strictPrefix)Correct and polish the text below.
        Output language: \(languageDescription).
        Do not translate to another language.
        Keep the original meaning, tone, paragraph breaks, names, numbers, URLs, code, and markdown.
        Return only the polished text.

        \(text)
        """
    }

    func polishOutputKeepsOriginalLanguage(_ output: String, originalLanguage: String?) -> Bool {
        guard let originalLanguage else {
            return true
        }
        guard textHasEnoughLanguageSignal(output),
              let outputLanguage = detectedTextLanguage(output) else {
            return true
        }
        return outputLanguage == originalLanguage
    }

    func textHasEnoughLanguageSignal(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letters.count >= 20
    }

    func showTranslationOverlay(_ translated: String, sourceText: String, action: TextAction) {
        DispatchQueue.main.async {
            self.stopSpeakingTranslation()
            self.translationOverlayWindow?.orderOut(nil)
            self.translationOverlayText = translated

            let sourceCode = self.detectedTextLanguage(sourceText)
                ?? self.configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE")
            let headerTitle: String
            let languageDirection: String
            switch action {
            case .translate:
                let primaryCode = self.configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE")
                let targetCode = sourceCode == primaryCode
                    ? self.configLanguageCode("MYTRANSLATOR_TARGET_LANGUAGE")
                    : primaryCode
                headerTitle = self.l("Translation")
                languageDirection = "\(Self.displayLanguageLabel(sourceCode))  →  \(Self.displayLanguageLabel(targetCode))"
            case .polish:
                headerTitle = self.l("Improvement")
                languageDirection = "\(Self.displayLanguageLabel(sourceCode)) · \(self.l("original language"))"
            }

            let width: CGFloat = 420
            let height: CGFloat = 260
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            var x = mouse.x - width / 2
            var y = mouse.y + 26
            x = min(max(x, screenFrame.minX + 16), screenFrame.maxX - width - 16)
            if y + height > screenFrame.maxY {
                y = mouse.y - height - 26
            }
            y = min(max(y, screenFrame.minY + 16), screenFrame.maxY - height - 16)

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 350, height: 190)

            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            container.autoresizingMask = [.width, .height]
            container.wantsLayer = true
            container.layer?.cornerRadius = 20
            container.layer?.backgroundColor = WidgetStyle.background.cgColor
            container.layer?.borderWidth = 1
            container.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
            container.layer?.shadowColor = NSColor.black.cgColor
            container.layer?.shadowOpacity = 0.30
            container.layer?.shadowRadius = 16
            container.layer?.shadowOffset = CGSize(width: 0, height: -6)

            let resultCard = WidgetStyle.box(NSRect(x: 18, y: 66, width: width - 36, height: height - 130))
            resultCard.autoresizingMask = [.width, .height]
            container.addSubview(resultCard)

            let title = NSTextField(labelWithString: headerTitle)
            title.font = WidgetStyle.font(16, weight: .semibold)
            title.textColor = WidgetStyle.text
            title.frame = NSRect(x: 20, y: height - 39, width: width - 40, height: 23)
            title.autoresizingMask = [.width, .minYMargin]
            container.addSubview(title)

            let direction = NSTextField(labelWithString: languageDirection)
            direction.font = WidgetStyle.font(11, weight: .medium)
            direction.textColor = WidgetStyle.secondary
            direction.frame = NSRect(x: 20, y: height - 59, width: width - 40, height: 17)
            direction.autoresizingMask = [.width, .minYMargin]
            container.addSubview(direction)

            let resultLabel = NSTextField(labelWithString: self.l("RESULT"))
            resultLabel.font = WidgetStyle.font(10, weight: .semibold)
            resultLabel.textColor = WidgetStyle.secondary
            resultLabel.frame = NSRect(x: 32, y: height - 91, width: width - 64, height: 16)
            resultLabel.autoresizingMask = [.width, .minYMargin]
            container.addSubview(resultLabel)

            let scroll = NSScrollView(frame: NSRect(x: 28, y: 78, width: width - 56, height: height - 176))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.drawsBackground = false
            let textView = NSTextView(frame: scroll.bounds)
            textView.autoresizingMask = [.width, .height]
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = WidgetStyle.font(14)
            textView.textColor = WidgetStyle.text
            textView.string = translated
            textView.textContainerInset = NSSize(width: 4, height: 4)
            scroll.documentView = textView
            container.addSubview(scroll)

            let readButton = NSButton(title: self.l("Listen"), target: self, action: #selector(self.toggleSpeakTranslation))
            readButton.bezelStyle = .rounded
            readButton.font = WidgetStyle.font(11)
            readButton.frame = NSRect(x: width - 290, y: 18, width: 86, height: 32)
            readButton.autoresizingMask = [.minXMargin, .maxYMargin]
            container.addSubview(readButton)
            self.speechButton = readButton
            self.configureSpeechButton(isSpeaking: false)

            let copyButton = NSButton(title: self.l("Copy"), target: self, action: #selector(self.copyTranslationOverlayText))
            copyButton.bezelStyle = .rounded
            copyButton.font = WidgetStyle.font(11)
            WidgetStyle.styleSecondaryButton(copyButton, fontSize: 11)
            copyButton.toolTip = self.l("Copy all text")
            copyButton.frame = NSRect(x: width - 196, y: 18, width: 80, height: 32)
            copyButton.autoresizingMask = [.minXMargin, .maxYMargin]
            container.addSubview(copyButton)

            let closeButton = NSButton(title: self.l("Close"), target: self, action: #selector(self.closeTranslationOverlay))
            closeButton.bezelStyle = .rounded
            closeButton.font = WidgetStyle.font(11)
            WidgetStyle.styleSecondaryButton(closeButton, fontSize: 11)
            closeButton.toolTip = self.l("Close")
            closeButton.frame = NSRect(x: width - 108, y: 18, width: 84, height: 32)
            closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
            container.addSubview(closeButton)

            let resizeHandle = OverlayResizeHandle(
                frame: NSRect(x: width - 25, y: 7, width: 18, height: 18),
                targetWindow: panel
            )
            resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
            container.addSubview(resizeHandle)

            panel.contentView = container
            panel.orderFrontRegardless()
            self.translationOverlayWindow = panel
        }
    }

    enum TextAction {
        case translate
        case polish

        var progressTitle: String {
            switch self {
            case .translate: return "Translating…"
            case .polish: return "Improving…"
            }
        }
    }

    func handleTextAction(_ action: TextAction) {
        func normalizedClipboardText(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }

        setTranslationInProgress(true)
        DispatchQueue.main.async {
            self.translationProgressLabel?.stringValue = self.l(action.progressTitle)
        }
        defer {
            setTranslationInProgress(false)
        }

        var saved = ""
        var sourcePID: pid_t?
        var sourceElement: AXUIElement?
        var sourceRange: NSRange?
        DispatchQueue.main.sync {
            saved = NSPasteboard.general.string(forType: .string) ?? ""
            sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            sourceElement = focusedAXElement()
            sourceRange = sourceElement.flatMap { selectedRange(from: $0) }
        }

        DispatchQueue.main.sync {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("__MYTRANSLATOR_SENTINEL__", forType: .string)
        }
        Thread.sleep(forTimeInterval: 0.05)

        postKey(8, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.35)

        var selected = ""
        DispatchQueue.main.sync {
            selected = NSPasteboard.general.string(forType: .string) ?? ""
        }

        guard !selected.isEmpty, selected != "__MYTRANSLATOR_SENTINEL__" else {
            restore(saved)
            return
        }

        guard let transformed = transformSelectedText(selected, action: action) else {
            restore(saved)
            return
        }

        var pasted = false
        DispatchQueue.main.sync {
            let currentElement = focusedAXElement()
            let sameElement: Bool
            if let sourceElement, let currentElement {
                sameElement = CFEqual(sourceElement, currentElement)
            } else { sameElement = false }
            let currentSelection = currentElement.flatMap { stringAttribute(kAXSelectedTextAttribute, from: $0) }
            guard TextReplacementSafety.canReplace(
                sourcePID: sourcePID, currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                sameElement: sameElement, original: selected, selected: currentSelection,
                originalRange: sourceRange, currentRange: currentElement.flatMap { selectedRange(from: $0) }) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transformed, forType: .string)
            postKey(9, flags: .maskCommand)
            pasted = true
        }
        guard pasted else {
            restore(saved)
            showTranslationOverlay(transformed, sourceText: selected, action: action)
            return
        }
        Thread.sleep(forTimeInterval: 0.55)

        let focusedElementContainsTranslatedText = focusedElementContainsText(transformed)
        if focusedElementContainsTranslatedText {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.restore(saved)
            }
            return
        }

        let accessibilitySelectionStillOriginal = focusedSelectedTextMatches(selected)

        let verificationSentinel = "__MYTRANSLATOR_VERIFY_\(UUID().uuidString)__"
        DispatchQueue.main.sync {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(verificationSentinel, forType: .string)
        }
        Thread.sleep(forTimeInterval: 0.05)
        postKey(8, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.30)

        var afterPasteSelection = ""
        DispatchQueue.main.sync {
            afterPasteSelection = NSPasteboard.general.string(forType: .string) ?? ""
        }

        let originalStillSelected =
            normalizedClipboardText(afterPasteSelection) == normalizedClipboardText(selected)
            && normalizedClipboardText(transformed) != normalizedClipboardText(selected)
        let verificationCopyDidNotRun = afterPasteSelection == verificationSentinel
        let pasteFailedWithOriginalStillSelected =
            originalStillSelected || (verificationCopyDidNotRun && accessibilitySelectionStillOriginal)

        if pasteFailedWithOriginalStillSelected {
            restore(saved)
            showTranslationOverlay(transformed, sourceText: selected, action: action)
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            self.restore(saved)
        }
    }

    func focusedElementAllowsTextInsertion() -> Bool {
        guard let focusedElement = focusedAXElement() else {
            return false
        }
        return elementAllowsTextInsertion(focusedElement)
    }

    func focusedElementContainsText(_ text: String) -> Bool {
        guard !text.isEmpty, let focusedElement = focusedAXElement() else {
            return false
        }

        let normalizedNeedle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNeedle.isEmpty else {
            return false
        }

        return elementOrAncestor(focusedElement) { element in
            guard let value = stringAttribute(kAXValueAttribute, from: element) else {
                return false
            }
            return value.contains(normalizedNeedle)
        }
    }

    func focusedSelectedTextMatches(_ text: String) -> Bool {
        guard !text.isEmpty, let focusedElement = focusedAXElement() else {
            return false
        }

        let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else {
            return false
        }

        return elementOrAncestor(focusedElement) { element in
            guard let selectedText = stringAttribute(kAXSelectedTextAttribute, from: element) else {
                return false
            }
            return selectedText.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        }
    }

    func selectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let rangeValue = value as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func focusedAXElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            return nil
        }

        return (focusedValue as! AXUIElement)
    }

    func elementAllowsTextInsertion(_ focusedElement: AXUIElement) -> Bool {
        var current: AXUIElement? = focusedElement
        for _ in 0..<8 {
            guard let element = current else { return false }

            if let editable = boolAttribute("AXEditable", from: element) {
                return editable
            }

            var valueSettable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &valueSettable
            ) == .success, valueSettable.boolValue {
                return true
            }

            if let role = stringAttribute(kAXRoleAttribute, from: element),
               role == "AXTextField" || role == "AXComboBox" {
                return true
            }

            if stringAttribute(kAXSubroleAttribute, from: element) == "AXSecureTextField" {
                return true
            }

            var parentValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success, let parentValue {
                current = (parentValue as! AXUIElement)
            } else {
                current = nil
            }
        }

        return false
    }

    func elementOrAncestor(_ element: AXUIElement, matches: (AXUIElement) -> Bool) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else {
                return false
            }
            if matches(candidate) {
                return true
            }

            var parentValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success, let parentValue {
                current = (parentValue as! AXUIElement)
            } else {
                current = nil
            }
        }

        return false
    }

    func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success, let value else {
            return nil
        }

        return value as? String
    }

    func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success, let value else {
            return nil
        }

        return value as? Bool
    }

    func legacyFocusedElementAllowsTextInsertion(_ focusedElement: AXUIElement) -> Bool {
        var valueSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success, valueSettable.boolValue {
            return true
        }

        var selectedTextSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        ) == .success, selectedTextSettable.boolValue {
            return true
        }

        return false
    }

    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func restore(_ text: String) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            if !text.isEmpty {
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    func showTranslatorError(_ details: String) {
        guard !didShowTranslatorError else { return }
        didShowTranslatorError = true
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = self.l("Operation failed")
            a.informativeText = details
            a.alertStyle = .warning
            a.addButton(withTitle: self.l("OK"))
            a.runModal()
        }
    }

    func transformSelectedText(_ text: String, action: TextAction) -> String? {
        switch action {
        case .translate:
            return callTranslator(text)
        case .polish:
            return callPolisher(text)
        }
    }

    func callTranslator(_ text: String) -> String? {
        guard let runner = Bundle.main.path(forResource: "translator_runner", ofType: "sh") else {
            showTranslatorError(l("The local translator is missing."))
            return nil
        }

        var environment = ProcessInfo.processInfo.environment
        environment["MYTRANSLATOR_SOURCE_LANGUAGE"] = configLanguageCode("MYTRANSLATOR_SOURCE_LANGUAGE")
        environment["MYTRANSLATOR_TARGET_LANGUAGE"] = configLanguageCode("MYTRANSLATOR_TARGET_LANGUAGE")
        let timeoutSeconds = configTimeoutSeconds()
        environment["MYTRANSLATOR_TIMEOUT_SECONDS"] = String(timeoutSeconds)

        do {
            let captured = try TranslationProcess.run(
                executable: URL(fileURLWithPath: "/bin/bash"), arguments: [runner],
                environment: environment, input: Data(text.utf8), timeout: TimeInterval(timeoutSeconds))
            let result = String(data: captured.output, encoding: .utf8) ?? ""
            let errText = String(data: captured.errors, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard captured.status == 0 else {
                let rawDetails = errText.isEmpty ? "exit code \(captured.status)" : errText
                let details = friendlyTranslationError(rawDetails)
                showTranslatorError(details)
                return nil
            }

            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !errText.isEmpty {
                    showTranslatorError(friendlyTranslationError(errText))
                }
                return nil
            }
            didShowTranslatorError = false
            return result
        } catch TranslationProcess.Failure.timedOut {
            showTranslatorError("\(l("Apple Translation timed out after")) \(timeoutSeconds) \(l("seconds"))")
            return nil
        } catch {
            showTranslatorError(l("Unable to launch the local translator."))
            return nil
        }
    }

    func friendlyTranslationError(_ details: String) -> String {
        if details.contains("notInstalled") || details.localizedCaseInsensitiveContains("not installed") {
            return l("Apple Translation cannot translate this selection with the languages installed on this Mac. Check both languages in Settings and download them in Apple Translate if needed.")
        }
        if details.localizedCaseInsensitiveContains("timed out") {
            return l("Apple Translation timed out. Try again or increase the timeout in Settings.")
        }
        return l("Apple Translation failed. Check the offline languages and try again.")
    }

    func callPolisher(_ text: String) -> String? {
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard model.isAvailable else {
            showTranslatorError(l("Apple Foundation Models is not available on this Mac."))
            return nil
        }

        let inputLanguage = detectedTextLanguage(text)
        let session = LanguageModelSession(
            model: model,
            instructions: """
            Return only corrected and polished text.
            Keep exactly the same language and meaning as the input.
            Never translate the text to another language.
            Preserve paragraph breaks, names, numbers, URLs, code, and markdown.
            """
        )
        let timeoutSeconds = configTimeoutSeconds()
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = PolishResult()

        let task = Task {
            var outcome: PolishOutcome = .failure(l("No improvement result was generated."))
            do {
                let maxTokens = min(4096, max(256, text.count / 2 + 128))
                let options = GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.1,
                    maximumResponseTokens: maxTokens
                )

                for attempt in 0..<2 {
                    let response = try await session.respond(
                        to: polishPrompt(for: text, languageCode: inputLanguage, retry: attempt > 0),
                        options: options
                    )
                    let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if polishOutputKeepsOriginalLanguage(candidate, originalLanguage: inputLanguage) {
                        outcome = .success(candidate)
                        break
                    }

                    outcome = .failure(l("The improved text changed language. The selection was not replaced."))
                }
            } catch let error as LanguageModelSession.GenerationError {
                fputs("MyTranslator improvement error: \(generationErrorDetails(error))\n", stderr)
                outcome = .failure(l("The language model could not improve this text."))
            } catch {
                fputs("MyTranslator improvement error: \(error)\n", stderr)
                outcome = .failure(l("The language model could not improve this text."))
            }
            resultBox.set(outcome)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + TimeInterval(timeoutSeconds)) == .timedOut {
            task.cancel()
            showTranslatorError("\(l("Text improvement timed out after")) \(timeoutSeconds) \(l("seconds"))")
            return nil
        }

        guard let outcome = resultBox.get() else {
            showTranslatorError(l("Text improvement finished without a result."))
            return nil
        }
        let polished: String
        switch outcome {
        case .success(let value):
            polished = value
        case .failure(let failure):
            showTranslatorError("\(l("Text improvement failed")): \(failure)")
            return nil
        }

        guard !polished.isEmpty else {
            showTranslatorError(l("Text improvement returned an empty result."))
            return nil
        }

        didShowTranslatorError = false
        return polished
    }

    func generationErrorDetails(_ error: LanguageModelSession.GenerationError) -> String {
        let pieces = [
            error.errorDescription,
            error.failureReason,
            error.recoverySuggestion,
            String(describing: error)
        ]
        return pieces
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow === languageInfoWindow {
            setupWindow?.removeChildWindow(closingWindow)
            languageInfoWindow = nil
            return
        }
        if let closingWindow = notification.object as? NSWindow, closingWindow === setupWindow {
            languageInfoWindow?.close()
            setupWindow = nil
            setupEventTap()
            return
        }
        if let closingWindow = notification.object as? NSWindow, closingWindow === window {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MyTranslatorMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
