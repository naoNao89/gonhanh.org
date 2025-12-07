import Foundation
import Carbon
import AppKit

// MARK: - Debug Logging

func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    print(message)

    // Also write to file
    let logPath = "/tmp/gonhanh_debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(logMessage.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: logMessage.data(using: .utf8))
    }
}

// MARK: - FFI Result Struct (must match Rust #[repr(C)])

struct ImeResult {
    var chars: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    var action: UInt8      // 0=None, 1=Send, 2=Restore
    var backspace: UInt8
    var count: UInt8
    var _pad: UInt8
}

// MARK: - C Function Declarations

@_silgen_name("ime_init")
func ime_init()

@_silgen_name("ime_key")
func ime_key(_ key: UInt16, _ caps: Bool, _ ctrl: Bool) -> UnsafeMutablePointer<ImeResult>?

@_silgen_name("ime_method")
func ime_method(_ method: UInt8)

@_silgen_name("ime_enabled")
func ime_enabled(_ enabled: Bool)

@_silgen_name("ime_modern")
func ime_modern(_ modern: Bool)

@_silgen_name("ime_clear")
func ime_clear()

@_silgen_name("ime_free")
func ime_free(_ result: UnsafeMutablePointer<ImeResult>?)

// MARK: - RustBridge

class RustBridge {
    static var isInitialized = false

    /// Initialize engine (call once at app start)
    static func initialize() {
        guard !isInitialized else { return }
        ime_init()
        isInitialized = true
        debugLog("[RustBridge] Engine initialized")
    }

    /// Process key event
    /// Returns: (backspaceCount, newChars) or nil if no action needed
    static func processKey(keyCode: UInt16, caps: Bool, ctrl: Bool) -> (Int, [Character])? {
        guard isInitialized else {
            debugLog("[RustBridge] Engine not initialized!")
            return nil
        }

        guard let resultPtr = ime_key(keyCode, caps, ctrl) else {
            return nil
        }

        let result = resultPtr.pointee
        ime_free(resultPtr)

        // Action: 0=None, 1=Send, 2=Restore
        guard result.action == 1 else {
            return nil
        }

        let backspace = Int(result.backspace)
        var chars: [Character] = []

        // Extract chars from tuple
        let charArray = withUnsafePointer(to: result.chars) { ptr in
            ptr.withMemoryRebound(to: UInt32.self, capacity: 32) { bound in
                Array(UnsafeBufferPointer(start: bound, count: Int(result.count)))
            }
        }

        for code in charArray {
            if let scalar = Unicode.Scalar(code) {
                chars.append(Character(scalar))
            }
        }

        return (backspace, chars)
    }

    /// Set input method (0=Telex, 1=VNI)
    static func setMethod(_ method: Int) {
        ime_method(UInt8(method))
        debugLog("[RustBridge] Method set to: \(method == 0 ? "Telex" : "VNI")")
    }

    /// Enable/disable engine
    static func setEnabled(_ enabled: Bool) {
        ime_enabled(enabled)
        debugLog("[RustBridge] Engine enabled: \(enabled)")
    }

    /// Set modern orthography (true=oà, false=òa)
    static func setModern(_ modern: Bool) {
        ime_modern(modern)
    }

    /// Clear buffer (new session, e.g., on mouse click)
    static func clearBuffer() {
        ime_clear()
    }
}

// MARK: - Keyboard Hook Manager

class KeyboardHookManager {
    static let shared = KeyboardHookManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }

        debugLog("[KeyboardHook] Starting...")

        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        debugLog("[KeyboardHook] Accessibility trusted: \(trusted)")

        if !trusted {
            // Prompt user for permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            debugLog("[KeyboardHook] Requested accessibility permission. Please grant and restart app.")
            return
        }

        // Initialize Rust engine
        RustBridge.initialize()

        // Create event tap for keyDown events
        // Use listenOnly option which doesn't require as strict permissions
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        debugLog("[KeyboardHook] Creating event tap...")

        // Try creating tap - use .cghidEventTap for better compatibility
        var tap: CFMachPort?

        // First try session tap with defaultTap (can modify events)
        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardCallback,
            userInfo: nil
        )

        if tap == nil {
            debugLog("[KeyboardHook] cghidEventTap failed, trying cgSessionEventTap...")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: keyboardCallback,
                userInfo: nil
            )
        }

        if tap == nil {
            debugLog("[KeyboardHook] cgSessionEventTap failed, trying cgAnnotatedSessionEventTap...")
            tap = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: keyboardCallback,
                userInfo: nil
            )
        }

        guard let finalTap = tap else {
            debugLog("[KeyboardHook] ALL event tap methods FAILED!")
            debugLog("[KeyboardHook] Opening System Settings for Input Monitoring...")

            // Show alert and open System Settings
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Cần quyền Input Monitoring"
                alert.informativeText = "GoNhanh cần quyền Input Monitoring để gõ tiếng Việt.\n\n1. Mở System Settings > Privacy & Security > Input Monitoring\n2. Bật GoNhanh\n3. Khởi động lại app"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Mở System Settings")
                alert.addButton(withTitle: "Hủy")

                if alert.runModal() == .alertFirstButtonReturn {
                    // Open Input Monitoring settings
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return
        }

        debugLog("[KeyboardHook] Event tap created successfully")

        eventTap = finalTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, finalTap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: finalTap, enable: true)
            isRunning = true
            debugLog("[KeyboardHook] Started successfully, listening for keys...")
        }
    }

    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false
        debugLog("[KeyboardHook] Stopped")
    }

    func getTap() -> CFMachPort? {
        return eventTap
    }
}

// MARK: - Keyboard Callback

private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled event - re-enable
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        debugLog("[KeyboardHook] Event tap was disabled, re-enabling...")
        if let tap = KeyboardHookManager.shared.getTap() {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // Only handle key down
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    let caps = flags.contains(.maskShift) || flags.contains(.maskAlphaShift)
    let ctrl = flags.contains(.maskCommand) || flags.contains(.maskControl) ||
               flags.contains(.maskAlternate)

    debugLog("[KeyboardHook] Key: \(keyCode), caps=\(caps), ctrl=\(ctrl)")

    // Process key through Rust engine
    if let (backspace, chars) = RustBridge.processKey(keyCode: keyCode, caps: caps, ctrl: ctrl) {
        debugLog("[KeyboardHook] Output: backspace=\(backspace), chars=\(chars)")

        // Use atomic text replacement to fix Chrome/Excel autocomplete issues
        // Instead of backspace+type (which can cause "dính chữ"), we:
        // 1. Select text with Shift+Left
        // 2. Type replacement (automatically replaces selection)
        sendTextReplacement(backspaceCount: backspace, chars: chars, proxy: proxy)

        // Consume original event
        return nil
    }

    // Pass through
    return Unmanaged.passUnretained(event)
}

// MARK: - App Detection

/// Check if current frontmost app is a terminal/CLI app
private func isTerminalApp() -> Bool {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        return false
    }

    let bundleId = frontApp.bundleIdentifier ?? ""
    let appName = frontApp.localizedName ?? ""

    // List of known terminal apps
    let terminalBundleIds = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.qvacua.VimR",
        "org.vim.MacVim",
        "com.microsoft.VSCode",      // VS Code integrated terminal
        "com.jetbrains.",            // JetBrains IDEs
    ]

    let terminalAppNames = [
        "Terminal",
        "iTerm",
        "Alacritty",
        "WezTerm",
        "Hyper",
        "kitty",
    ]

    // Check bundle ID
    for id in terminalBundleIds {
        if bundleId.contains(id) {
            return true
        }
    }

    // Check app name
    for name in terminalAppNames {
        if appName.contains(name) {
            return true
        }
    }

    return false
}

// MARK: - Send Keys

/// Smart text replacement - uses different methods based on app type
/// - Terminal/CLI: Use backspace (selection doesn't work well)
/// - Browser/Office: Use Shift+Left selection (fixes autocomplete issues)
private func sendTextReplacement(backspaceCount: Int, chars: [Character], proxy: CGEventTapProxy) {
    if isTerminalApp() {
        // Terminal mode: use backspace
        sendTextReplacementWithBackspace(backspaceCount: backspaceCount, chars: chars, proxy: proxy)
    } else {
        // GUI app mode: use selection for atomic replacement
        sendTextReplacementWithSelection(backspaceCount: backspaceCount, chars: chars, proxy: proxy)
    }
}

/// Terminal-friendly: backspace then type
private func sendTextReplacementWithBackspace(backspaceCount: Int, chars: [Character], proxy: CGEventTapProxy) {
    let source = CGEventSource(stateID: .privateState)

    // Send backspaces
    for _ in 0..<backspaceCount {
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    // Send new characters
    let string = String(chars)
    let utf16 = Array(string.utf16)

    if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
       let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}

/// GUI app-friendly: select then replace (atomic, fixes Chrome/Excel autocomplete)
private func sendTextReplacementWithSelection(backspaceCount: Int, chars: [Character], proxy: CGEventTapProxy) {
    let source = CGEventSource(stateID: .privateState)

    if backspaceCount > 0 {
        // Select text with Shift+Left Arrow
        for _ in 0..<backspaceCount {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: false) {
                down.flags = .maskShift
                up.flags = .maskShift
                down.post(tap: .cgSessionEventTap)
                up.post(tap: .cgSessionEventTap)
            }
        }
    }

    // Send replacement characters (replaces selection)
    let string = String(chars)
    let utf16 = Array(string.utf16)

    if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
       let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}

