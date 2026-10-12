import CoreGraphics
import Foundation

struct MousePacket {
    let timestamp: UInt32
    let packetType: UInt8
    let buttons: UInt8
    let deltaX: Float
    let deltaY: Float
    let scrollWheel: Int8
    let hScrollWheel: Int8
}

final class MouseController {
    private var lastButtonsMask: UInt8 = 0
    private var virtualMousePosition: CGPoint = .zero
    private var isPositionInitialized = false
    private var processedPacketCount = 0
    private let logEveryPacketCount = 60
    
    func releaseAllButtons() {
        if lastButtonsMask != 0 {
            handleButtonsBitmask(0)
        }
    }
    
    func processIncomingNetworkData(_ data: Data) {
        guard data.count >= 16 else { return }
        guard let packet = unpackMousePacket(from: data) else { return }
        guard packet.packetType == 0x01 else { return }
        
        processedPacketCount += 1
        #if DEBUG
        let shouldLogPacket = processedPacketCount % logEveryPacketCount == 0
            || packet.buttons != lastButtonsMask
            || packet.scrollWheel != 0
            || packet.hScrollWheel != 0
        
        if shouldLogPacket {
            let latencyMs = packetLatencyMilliseconds(from: packet.timestamp)
            print("📦 [MousePacket] latency:\(latencyMs)ms, buttons:\(packet.buttons), dx:\(packet.deltaX), dy:\(packet.deltaY), scroll:\(packet.scrollWheel), hScroll:\(packet.hScrollWheel)")
        }
        #endif
        
        if packet.deltaX != 0 || packet.deltaY != 0 {
            moveMouseRelative(dx: CGFloat(packet.deltaX), dy: CGFloat(packet.deltaY))
        }
        
        handleButtonsBitmask(packet.buttons)
        
        if packet.scrollWheel != 0 || packet.hScrollWheel != 0 {
            scrollMouse(vertical: Int32(packet.scrollWheel), horizontal: Int32(packet.hScrollWheel))
        }
    }
    
    private func currentMouseLocation() -> CGPoint {
        if let current = CGEvent(source: nil)?.location {
            virtualMousePosition = current
            isPositionInitialized = true
            return current
        }
        
        if !isPositionInitialized {
            let mainBounds = CGDisplayBounds(CGMainDisplayID())
            virtualMousePosition = CGPoint(x: mainBounds.midX, y: mainBounds.midY)
            isPositionInitialized = true
        }
        
        return virtualMousePosition
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
        
        let start = data.startIndex
        return MousePacket(
            timestamp: timestamp,
            packetType: data[start + 4],
            buttons: data[start + 5],
            deltaX: Float(bitPattern: deltaXBits),
            deltaY: Float(bitPattern: deltaYBits),
            scrollWheel: Int8(bitPattern: data[start + 14]),
            hScrollWheel: Int8(bitPattern: data[start + 15])
        )
    }
    
    private func readLittleEndianUInt32(from data: Data, offset: Int) -> UInt32? {
        let start = data.startIndex + offset
        guard start + 3 < data.endIndex else { return nil }
        
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }
    
    private func moveMouseRelative(dx: CGFloat, dy: CGFloat) {
        let current = currentMouseLocation()
        let targetLocation = clampedMouseLocation(
            CGPoint(x: current.x + dx, y: current.y + dy)
        )
        virtualMousePosition = targetLocation
        
        let isLeftDown = (lastButtonsMask & 0x01) != 0
        let isRightDown = (lastButtonsMask & 0x02) != 0
        let isMiddleDown = (lastButtonsMask & 0x04) != 0
        
        let eventType: CGEventType
        let mouseButton: CGMouseButton
        
        if isLeftDown {
            eventType = .leftMouseDragged
            mouseButton = .left
        } else if isRightDown {
            eventType = .rightMouseDragged
            mouseButton = .right
        } else if isMiddleDown {
            eventType = .otherMouseDragged
            mouseButton = .center
        } else {
            eventType = .mouseMoved
            mouseButton = .left
        }
        
        if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: targetLocation, mouseButton: mouseButton) {
            if isMiddleDown {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            event.post(tap: .cghidEventTap)
        }
    }
    
    private func clampedMouseLocation(_ location: CGPoint) -> CGPoint {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return location
        }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return location
        }
        
        for display in displays {
            if CGDisplayBounds(display).contains(location) {
                return location
            }
        }
        
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let clampedX = max(mainBounds.minX, min(location.x, mainBounds.maxX))
        let clampedY = max(mainBounds.minY, min(location.y, mainBounds.maxY))
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    private func scrollMouse(vertical: Int32, horizontal: Int32) {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    private func handleButtonsBitmask(_ currentMask: UInt8) {
        let currentLocation = currentMouseLocation()
        
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
                if button == .center {
                    event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                }
                event.post(tap: .cghidEventTap)
            }
        } else if !isCurrentPressed && isLastPressed {
            if let event = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: pos, mouseButton: button) {
                if button == .center {
                    event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                }
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
