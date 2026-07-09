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
    private var pressedKeycodes = Set<UInt16>()
    
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
