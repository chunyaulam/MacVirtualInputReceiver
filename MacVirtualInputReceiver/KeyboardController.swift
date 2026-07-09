import CoreGraphics
import ApplicationServices
import Foundation

struct KeyboardPacket {
    let timestamp: UInt32
    let packetType: UInt8
    let action: UInt8
    let keycode: UInt16
    let modifiers: UInt8
}

class KeyboardController {
    private let keyUpAction: UInt8 = 0x00
    private let keyDownAction: UInt8 = 0x01
    private let unicodeTextChannel: UInt8 = 0x03
    private let controlKeyChannel: UInt8 = 0x04
    private var pressedKeycodes = Set<UInt16>()
    
    func handleIncomingKeyboardPacket(data: Data) {
        guard let channel = data.first else {
            print("⌨️ [KeyboardPacket] Empty packet")
            return
        }
        
        switch channel {
        case unicodeTextChannel:
            handleUnicodeTextPacket(data)
        case controlKeyChannel:
            handleControlKeyPacket(data)
        default:
            print("⌨️ [KeyboardPacket] Unsupported channel:\(channel), bytes:\(data.count)")
        }
    }
    
    func processIncomingNetworkData(_ data: Data) {
        guard data.count >= 9 else {
            print("⌨️ [KeyboardPacket] Invalid length:\(data.count)")
            return
        }
        
        guard let packet = unpackKeyboardPacket(from: data) else { return }
        guard packet.packetType == 0x02 else { return }
        
        switch packet.action {
        case keyUpAction, keyDownAction:
            postKeyboardEvent(packet)
        default:
            print("⌨️ [KeyboardPacket] Unknown action:\(packet.action), keycode:\(packet.keycode)")
        }
    }
    
    private func unpackKeyboardPacket(from data: Data) -> KeyboardPacket? {
        guard let timestamp = readLittleEndianUInt32(from: data, offset: 0),
              let keycode = readLittleEndianUInt16(from: data, offset: 6) else {
            return nil
        }
        
        return KeyboardPacket(
            timestamp: timestamp,
            packetType: data[4],
            action: data[5],
            keycode: keycode,
            modifiers: data[8]
        )
    }
    
    private func handleUnicodeTextPacket(_ data: Data) {
        guard AXIsProcessTrusted() else {
            print("⌨️ [UnicodeText] Blocked: Accessibility permission is not granted")
            return
        }
        
        let payload = data.dropFirst()
        guard !payload.isEmpty else {
            print("⌨️ [UnicodeText] Empty UTF-8 payload")
            return
        }
        
        guard let string = String(data: payload, encoding: .utf8) else {
            print("⌨️ [UnicodeText] Invalid UTF-8 payload, bytes:\(payload.count)")
            return
        }
        
        let utf16CodeUnits = Array(string.utf16)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            return
        }
        
        utf16CodeUnits.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        event.post(tap: .cghidEventTap)
        
        print("⌨️ [UnicodeText] inserted characters:\(string.count), utf16Units:\(utf16CodeUnits.count)")
    }
    
    private func handleControlKeyPacket(_ data: Data) {
        guard AXIsProcessTrusted() else {
            print("⌨️ [ControlKey] Blocked: Accessibility permission is not granted")
            return
        }
        
        guard data.count >= 2 else {
            print("⌨️ [ControlKey] Missing action byte")
            return
        }
        
        let action = data[1]
        guard let keycode = controlKeycode(for: action) else {
            print("⌨️ [ControlKey] Unsupported action:\(action)")
            return
        }
        
        postControlKey(keycode)
        print("⌨️ [ControlKey] action:\(action), keycode:\(keycode)")
    }
    
    private func controlKeycode(for action: UInt8) -> CGKeyCode? {
        switch action {
        case 1:
            return 0x33
        case 2:
            return 0x24
        case 3:
            return 0x30
        case 4:
            return 0x35
        default:
            return nil
        }
    }
    
    private func postControlKey(_ keycode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func postKeyboardEvent(_ packet: KeyboardPacket) {
        guard AXIsProcessTrusted() else {
            print("⌨️ [KeyboardEvent] Blocked: Accessibility permission is not granted")
            return
        }
        
        let isKeyDown = packet.action == keyDownAction
        if isKeyDown {
            pressedKeycodes.insert(packet.keycode)
        } else if pressedKeycodes.remove(packet.keycode) == nil {
            print("⌨️ [KeyboardEvent] Warning: received keyUp without previous keyDown for keycode:\(packet.keycode)")
        }
        
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(packet.keycode),
            keyDown: isKeyDown
        ) else {
            return
        }
        
        event.flags = eventFlags(from: packet.modifiers)
        event.post(tap: .cgSessionEventTap)
        
        let actionName = isKeyDown ? "down" : "up"
        let latencyMs = packetLatencyMilliseconds(from: packet.timestamp)
        print("⌨️ [KeyboardEvent] keycode:\(packet.keycode), action:\(actionName), modifiers:\(packet.modifiers), latency:\(latencyMs)ms")
    }
    
    private func eventFlags(from modifiers: UInt8) -> CGEventFlags {
        var flags = CGEventFlags()
        
        if modifiers & 0x01 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x02 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x04 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x08 != 0 { flags.insert(.maskCommand) }
        
        return flags
    }
    
    private func packetLatencyMilliseconds(from packetTimestamp: UInt32) -> Int32 {
        let currentMilliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
        let currentTimestamp = UInt32(truncatingIfNeeded: currentMilliseconds)
        let wrappedDelta = currentTimestamp &- packetTimestamp
        return Int32(bitPattern: wrappedDelta)
    }
    
    private func readLittleEndianUInt16(from data: Data, offset: Int) -> UInt16? {
        guard offset + 1 < data.count else { return nil }
        
        return UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }
    
    private func readLittleEndianUInt32(from data: Data, offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
