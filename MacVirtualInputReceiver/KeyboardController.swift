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

final class KeyboardController {
    private let keyUpAction: UInt8 = 0x00
    private let keyDownAction: UInt8 = 0x01
    private let unicodeTextChannel: UInt8 = 0x03
    private let controlKeyChannel: UInt8 = 0x04
    private var pressedKeycodes = Set<UInt16>()
    private var processedPacketCount = 0
    private let logEveryPacketCount = 60
    
    private var cachedAccessibilityTrusted: Bool = AXIsProcessTrusted()
    private var lastAccessibilityCheck: Date = Date()
    
    var isAccessibilityGranted: Bool {
        if cachedAccessibilityTrusted { return true }
        if Date().timeIntervalSince(lastAccessibilityCheck) > 1.0 {
            cachedAccessibilityTrusted = AXIsProcessTrusted()
            lastAccessibilityCheck = Date()
        }
        return cachedAccessibilityTrusted
    }
    
    func refreshAccessibilityTrust() {
        cachedAccessibilityTrusted = AXIsProcessTrusted()
        lastAccessibilityCheck = Date()
    }
    
    func releaseAllKeys() {
        guard !pressedKeycodes.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for keycode in pressedKeycodes {
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keycode),
                keyDown: false
            )
            keyUp?.post(tap: .cghidEventTap)
        }
        pressedKeycodes.removeAll()
    }
    
    func handleIncomingKeyboardPacket(data: Data) {
        guard let channel = data.first else {
            return
        }
        
        switch channel {
        case unicodeTextChannel:
            handleUnicodeTextPacket(data)
        case controlKeyChannel:
            handleControlKeyPacket(data)
        default:
            break
        }
    }
    
    func processIncomingNetworkData(_ data: Data) {
        guard data.count >= 9 else { return }
        guard let packet = unpackKeyboardPacket(from: data) else { return }
        guard packet.packetType == 0x02 else { return }
        
        switch packet.action {
        case keyUpAction, keyDownAction:
            postKeyboardEvent(packet)
        default:
            break
        }
    }
    
    private func unpackKeyboardPacket(from data: Data) -> KeyboardPacket? {
        guard let timestamp = readLittleEndianUInt32(from: data, offset: 0),
              let keycode = readLittleEndianUInt16(from: data, offset: 6) else {
            return nil
        }
        
        let start = data.startIndex
        return KeyboardPacket(
            timestamp: timestamp,
            packetType: data[start + 4],
            action: data[start + 5],
            keycode: keycode,
            modifiers: data[start + 8]
        )
    }
    
    private func handleUnicodeTextPacket(_ data: Data) {
        guard isAccessibilityGranted else { return }
        
        let payload = data.dropFirst()
        guard !payload.isEmpty,
              let string = String(data: payload, encoding: .utf8) else {
            return
        }
        
        let utf16CodeUnits = Array(string.utf16)
        let maxChunkSize = 20
        for i in stride(from: 0, to: utf16CodeUnits.count, by: maxChunkSize) {
            let end = min(i + maxChunkSize, utf16CodeUnits.count)
            let chunk = Array(utf16CodeUnits[i..<end])
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                continue
            }
            
            chunk.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            event.post(tap: .cghidEventTap)
        }
    }
    
    private func handleControlKeyPacket(_ data: Data) {
        guard isAccessibilityGranted else { return }
        guard data.count >= 2 else { return }
        
        let action = data[data.startIndex + 1]
        guard let keycode = controlKeycode(for: action) else { return }
        
        postControlKey(keycode)
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
        guard isAccessibilityGranted else { return }
        
        let isKeyDown = packet.action == keyDownAction
        if isKeyDown {
            pressedKeycodes.insert(packet.keycode)
        } else {
            pressedKeycodes.remove(packet.keycode)
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
        event.post(tap: .cghidEventTap)
        
        processedPacketCount += 1
        #if DEBUG
        if processedPacketCount % logEveryPacketCount == 0 {
            let actionName = isKeyDown ? "down" : "up"
            let latencyMs = packetLatencyMilliseconds(from: packet.timestamp)
            print("⌨️ [KeyboardEvent] keycode:\(packet.keycode), action:\(actionName), modifiers:\(packet.modifiers), latency:\(latencyMs)ms")
        }
        #endif
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
        let start = data.startIndex + offset
        guard start + 1 < data.endIndex else { return nil }
        
        return UInt16(data[start])
            | (UInt16(data[start + 1]) << 8)
    }
    
    private func readLittleEndianUInt32(from data: Data, offset: Int) -> UInt32? {
        let start = data.startIndex + offset
        guard start + 3 < data.endIndex else { return nil }
        
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }
}
