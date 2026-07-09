import Foundation

struct GamepadPacket: Equatable {
    let timestamp: UInt32
    let packetType: UInt8
    let buttons: UInt16
    let leftStickX: Int16
    let leftStickY: Int16
    let rightStickX: Int16
    let rightStickY: Int16
    let leftTrigger: UInt8
    let rightTrigger: UInt8
}

class GamepadController {
    private var lastPacket: GamepadPacket?
    private var processedPacketCount = 0
    private let logEveryPacketCount = 30
    
    private let buttonNames: [(mask: UInt16, name: String)] = [
        (0x0001, "A"),
        (0x0002, "B"),
        (0x0004, "X"),
        (0x0008, "Y"),
        (0x0010, "LB"),
        (0x0020, "RB"),
        (0x0040, "LS"),
        (0x0080, "RS"),
        (0x0100, "Start"),
        (0x0200, "Back"),
        (0x0400, "DPadUp"),
        (0x0800, "DPadDown"),
        (0x1000, "DPadLeft"),
        (0x2000, "DPadRight")
    ]
    
    func processIncomingNetworkData(_ data: Data) {
        guard data.count >= 17 else {
            print("🎮 [GamepadPacket] Invalid length:\(data.count)")
            return
        }
        
        guard let packet = unpackGamepadPacket(from: data) else { return }
        guard packet.packetType == 0x03 else { return }
        
        processedPacketCount += 1
        logPacketIfNeeded(packet)
        lastPacket = packet
    }
    
    private func unpackGamepadPacket(from data: Data) -> GamepadPacket? {
        guard let timestamp = readLittleEndianUInt32(from: data, offset: 0),
              let buttons = readLittleEndianUInt16(from: data, offset: 5),
              let leftStickX = readLittleEndianInt16(from: data, offset: 7),
              let leftStickY = readLittleEndianInt16(from: data, offset: 9),
              let rightStickX = readLittleEndianInt16(from: data, offset: 11),
              let rightStickY = readLittleEndianInt16(from: data, offset: 13) else {
            return nil
        }
        
        return GamepadPacket(
            timestamp: timestamp,
            packetType: data[4],
            buttons: buttons,
            leftStickX: leftStickX,
            leftStickY: leftStickY,
            rightStickX: rightStickX,
            rightStickY: rightStickY,
            leftTrigger: data[15],
            rightTrigger: data[16]
        )
    }
    
    private func logPacketIfNeeded(_ packet: GamepadPacket) {
        let buttonChanged = packet.buttons != lastPacket?.buttons
        let triggerChanged = packet.leftTrigger != lastPacket?.leftTrigger
            || packet.rightTrigger != lastPacket?.rightTrigger
        let shouldLogPacket = processedPacketCount % logEveryPacketCount == 0
            || buttonChanged
            || triggerChanged
        
        guard shouldLogPacket else { return }
        
        let latencyMs = packetLatencyMilliseconds(from: packet.timestamp)
        let pressedButtons = pressedButtonNames(from: packet.buttons).joined(separator: ",")
        let buttonsDescription = pressedButtons.isEmpty ? "none" : pressedButtons
        
        print("🎮 [GamepadPacket] latency:\(latencyMs)ms, buttons:\(buttonsDescription), rawButtons:\(packet.buttons), LS:(\(packet.leftStickX),\(packet.leftStickY)), RS:(\(packet.rightStickX),\(packet.rightStickY)), LT:\(packet.leftTrigger), RT:\(packet.rightTrigger)")
    }
    
    private func pressedButtonNames(from buttons: UInt16) -> [String] {
        buttonNames.compactMap { button in
            buttons & button.mask != 0 ? button.name : nil
        }
    }
    
    private func packetLatencyMilliseconds(from packetTimestamp: UInt32) -> Int32 {
        let currentMilliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
        let currentTimestamp = UInt32(truncatingIfNeeded: currentMilliseconds)
        let wrappedDelta = currentTimestamp &- packetTimestamp
        return Int32(bitPattern: wrappedDelta)
    }
    
    private func readLittleEndianInt16(from data: Data, offset: Int) -> Int16? {
        guard let value = readLittleEndianUInt16(from: data, offset: offset) else { return nil }
        return Int16(bitPattern: value)
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
