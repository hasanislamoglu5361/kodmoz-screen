import Foundation
import CoreGraphics
import ApplicationServices

/// Tabletten gelen dokunmatik/klavye olaylarını macOS girdisine çevirir.
/// Fare olayları için Erişilebilirlik izni gerekir.
final class InputInjector {
    /// Sanal ekranın masaüstündeki nokta cinsinden konumu.
    var boundsProvider: () -> CGRect = { CGDisplayBounds(CGMainDisplayID()) }
    var naturalScroll = true
    var enabled = true

    private var leftButtonDown = false

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ event: InputEvent) {
        guard enabled else { return }
        switch event {
        case let .move(x, y):
            postMove(to: normalizedPoint(x: x, y: y))

        case let .button(x, y, button, down, clickCount):
            postButton(at: normalizedPoint(x: x, y: y),
                       button: button,
                       down: down,
                       clickCount: max(1, clickCount))

        case let .scroll(dx, dy):
            postScroll(dx: dx, dy: dy)

        case let .key(code, down, meta):
            postKey(androidCode: code, down: down, meta: meta)

        case let .text(text):
            postText(text)
        }
    }

    private func normalizedPoint(x: Double, y: Double) -> CGPoint {
        let bounds = boundsProvider()
        let nx = min(max(x, 0), 1)
        let ny = min(max(y, 0), 1)
        return CGPoint(
            x: bounds.minX + CGFloat(nx) * bounds.width,
            y: bounds.minY + CGFloat(ny) * bounds.height
        )
    }

    private func postMove(to point: CGPoint) {
        let type: CGEventType = leftButtonDown ? .leftMouseDragged : .mouseMoved
        let mouseButton: CGMouseButton = leftButtonDown ? .left : .left
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postButton(at point: CGPoint, button: Int, down: Bool, clickCount: Int) {
        let mouseButton: CGMouseButton
        switch button {
        case 1: mouseButton = .right
        case 2: mouseButton = .center
        default: mouseButton = .left
        }

        let type: CGEventType
        switch (mouseButton, down) {
        case (.left, true):
            type = .leftMouseDown
            leftButtonDown = true
        case (.left, false):
            type = .leftMouseUp
            leftButtonDown = false
        case (.right, true):
            type = .rightMouseDown
        case (.right, false):
            type = .rightMouseUp
        default:
            type = down ? .otherMouseDown : .otherMouseUp
        }

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: Int, dy: Int) {
        // Parmak aşağı = içerik aşağı (doğal kaydırma) → wheel1 pozitif.
        let sign = naturalScroll ? 1.0 : -1.0
        let wheel1 = Int32((Double(dy) * sign).rounded())
        let wheel2 = Int32((Double(dx) * sign).rounded())
        guard wheel1 != 0 || wheel2 != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postText(_ text: String) {
        guard !text.isEmpty else { return }
        let units = Array(text.utf16)
        guard !units.isEmpty else { return }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        units.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func postKey(androidCode: Int, down: Bool, meta: Int) {
        guard let virtualKey = Self.virtualKey(forAndroidCode: androidCode) else { return }
        var flags: CGEventFlags = []
        if meta & 1 != 0 { flags.insert(.maskShift) }
        if meta & 2 != 0 { flags.insert(.maskControl) }
        if meta & 4 != 0 { flags.insert(.maskAlternate) }
        if meta & 8 != 0 { flags.insert(.maskCommand) }

        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: virtualKey,
            keyDown: down
        ) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    /// Android `KeyEvent` anahtar kodları → macOS sanal tuş kodları.
    private static func virtualKey(forAndroidCode code: Int) -> CGKeyCode? {
        switch code {
        case 4: return 53      // BACK → Esc
        case 66: return 36     // ENTER
        case 67: return 51     // DEL → Backspace
        case 112: return 117   // FORWARD_DEL
        case 61: return 48     // TAB
        case 62: return 49     // SPACE
        case 19: return 126    // DPAD_UP
        case 20: return 125    // DPAD_DOWN
        case 21: return 123    // DPAD_LEFT
        case 22: return 124    // DPAD_RIGHT
        case 115: return 57    // CAPS_LOCK
        case 111: return 53    // ESCAPE
        default: return nil
        }
    }
}
