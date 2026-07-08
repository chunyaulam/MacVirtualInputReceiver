import CoreGraphics
import AppKit

struct MousePacket {
    let timestamp: UInt32
    let packetType: UInt8
    let buttons: UInt8
    let deltaX: Float
    let deltaY: Float
    let scrollWheel: Int8
    let hScrollWheel: Int8
}

class MouseController {
    private var lastButtonsMask: UInt8 = 0
    private var virtualMousePosition: CGPoint = .zero
    private var isPositionInitialized = false
    private var processedPacketCount = 0
    private let logEveryPacketCount = 60
    
    func processIncomingNetworkData(_ data: Data) {
        guard data.count >= 16 else { return }
        guard let packet = unpackMousePacket(from: data) else { return }
        guard packet.packetType == 0x01 else { return }
        
        processedPacketCount += 1
        let shouldLogPacket = processedPacketCount % logEveryPacketCount == 0
            || packet.buttons != lastButtonsMask
            || packet.scrollWheel != 0
            || packet.hScrollWheel != 0
        
        if shouldLogPacket {
            let latencyMs = packetLatencyMilliseconds(from: packet.timestamp)
            print("📦 [MousePacket] timestamp:\(packet.timestamp), latency:\(latencyMs)ms, buttons:\(packet.buttons), dx:\(packet.deltaX), dy:\(packet.deltaY), scroll:\(packet.scrollWheel), hScroll:\(packet.hScrollWheel)")
        }
        
        if packet.deltaX != 0 || packet.deltaY != 0 {
            moveMouseRelative(dx: CGFloat(packet.deltaX), dy: CGFloat(packet.deltaY))
        }
        
        handleButtonsBitmask(packet.buttons)
        
        if packet.scrollWheel != 0 || packet.hScrollWheel != 0 {
            scrollMouse(vertical: Int32(packet.scrollWheel), horizontal: Int32(packet.hScrollWheel))
        }
    }
    
    private func initializeMousePositionIfNeeded() {
        guard !isPositionInitialized else { return }
        
        if let current = CGEvent(source: nil)?.location {
            virtualMousePosition = current
        } else if let screen = NSScreen.main {
            virtualMousePosition = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        }
        
        isPositionInitialized = true
    }
    
    private func packetLatencyMilliseconds(from packetTimestamp: UInt32) -> Int32 {
        let currentMilliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
        let currentTimestamp = UInt32(truncatingIfNeeded: currentMilliseconds)
        let wrappedDelta = currentTimestamp &- packetTimestamp
        return Int32(bitPattern: wrappedDelta)
    }
    
    private func unpackMousePacket(from data: Data) -> MousePacket? {
        guard data.count >= 16,
              let timestamp = readLittleEndianUInt32(from: data, offset: 0),
              let deltaXBits = readLittleEndianUInt32(from: data, offset: 6),
              let deltaYBits = readLittleEndianUInt32(from: data, offset: 10) else {
            return nil
        }
        
        return MousePacket(
            timestamp: timestamp,
            packetType: data[4],
            buttons: data[5],
            deltaX: Float(bitPattern: deltaXBits),
            deltaY: Float(bitPattern: deltaYBits),
            scrollWheel: Int8(bitPattern: data[14]),
            hScrollWheel: Int8(bitPattern: data[15])
        )
    }
    
    private func readLittleEndianUInt32(from data: Data, offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
    
    private func moveMouseRelative(dx: CGFloat, dy: CGFloat) {
        initializeMousePositionIfNeeded()
        
        let previousLocation = virtualMousePosition
        let targetLocation = clampedMouseLocation(
            CGPoint(x: virtualMousePosition.x + dx, y: virtualMousePosition.y + dy)
        )
        virtualMousePosition = targetLocation
        
        let isLeftDown = (lastButtonsMask & 0x01) != 0
        let eventType: CGEventType = isLeftDown ? .leftMouseDragged : .mouseMoved
        
        if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: targetLocation, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
            if processedPacketCount % logEveryPacketCount == 0 {
                print("🖱️ [MouseEvent] \(eventType) dx:\(dx), dy:\(dy), from:\(previousLocation), to:\(targetLocation)")
            }
        }
    }
    
    private func clampedMouseLocation(_ location: CGPoint) -> CGPoint {
        guard let screenFrame = NSScreen.main?.frame else { return location }
        
        let clampedX = max(screenFrame.minX, min(location.x, screenFrame.maxX))
        let clampedY = max(screenFrame.minY, min(location.y, screenFrame.maxY))
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    private func scrollMouse(vertical: Int32, horizontal: Int32) {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0) {
            event.post(tap: .cghidEventTap)
            print("🛞 [MouseEvent] verticalScroll:\(vertical), horizontalScroll:\(horizontal)")
        }
    }
    
    private func handleButtonsBitmask(_ currentMask: UInt8) {
        initializeMousePositionIfNeeded()
        let currentLocation = virtualMousePosition
        
        compareAndPostButton(maskBit: 0x01, currentMask: currentMask, lastMask: lastButtonsMask, pos: currentLocation, downType: .leftMouseDown, upType: .leftMouseUp, button: .left, buttonName: "left")
        compareAndPostButton(maskBit: 0x02, currentMask: currentMask, lastMask: lastButtonsMask, pos: currentLocation, downType: .rightMouseDown, upType: .rightMouseUp, button: .right, buttonName: "right")
        compareAndPostButton(maskBit: 0x04, currentMask: currentMask, lastMask: lastButtonsMask, pos: currentLocation, downType: .otherMouseDown, upType: .otherMouseUp, button: .center, buttonName: "middle")
        
        lastButtonsMask = currentMask
    }
    
    private func compareAndPostButton(maskBit: UInt8, currentMask: UInt8, lastMask: UInt8, pos: CGPoint, downType: CGEventType, upType: CGEventType, button: CGMouseButton, buttonName: String) {
        let isCurrentPressed = (currentMask & maskBit) != 0
        let isLastPressed = (lastMask & maskBit) != 0
        
        if isCurrentPressed && !isLastPressed {
            if let event = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: pos, mouseButton: button) {
                event.post(tap: .cghidEventTap)
                print("🖱️ [MouseEvent] \(buttonName) down at:\(pos)")
            }
        } else if !isCurrentPressed && isLastPressed {
            if let event = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: pos, mouseButton: button) {
                event.post(tap: .cghidEventTap)
                print("🖱️ [MouseEvent] \(buttonName) up at:\(pos)")
            }
        }
    }
}
