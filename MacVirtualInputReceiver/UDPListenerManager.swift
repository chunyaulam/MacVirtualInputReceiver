import Foundation
import Network

final class UDPListenerManager {
    var listener: NWListener?
    let queue = DispatchQueue(label: "com.example.udp.listener")
    private let mouseController = MouseController()
    private let keyboardController = KeyboardController()
    private let gamepadController = GamepadController()
    private let packetTypeOffset = 4
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    func refreshAccessibilityTrust() {
        keyboardController.refreshAccessibilityTrust()
    }

    func startListening(port: UInt16) {
        do {
            let parameters = NWParameters.udp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: parameters, on: nwPort)
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewConnection(newConnection)
            }
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("🟢 UDP Listener Started, Listening Port: \(port)")
                case .failed(let error):
                    print("🔴 Listener Failed: \(error.localizedDescription)")
                case .cancelled:
                    print("⚪ Listener Cancelled")
                default:
                    break
                }
            }
            
            listener?.start(queue: queue)
        } catch {
            print("Unable Start UDP Listener: \(error)")
        }
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for connection in self.activeConnections.values {
                connection.cancel()
            }
            self.activeConnections.removeAll()
            self.keyboardController.releaseAllKeys()
            self.mouseController.releaseAllButtons()
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = ObjectIdentifier(connection)
        activeConnections[connectionId] = connection
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .failed, .cancelled:
                self.queue.async {
                    self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        receiveNextPacket(on: connection)
    }
    
    private func receiveNextPacket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] content, _, _, error in
            guard let self = self else { return }
            
            if let error = error {
                #if DEBUG
                print("Error on receiving UDP data: \(error)")
                #endif
                connection.cancel()
                self.queue.async {
                    self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                }
                return
            }
            
            if let data = content, !data.isEmpty {
                self.handleReceivedData(data, from: connection)
            }
            
            self.receiveNextPacket(on: connection)
        }
    }
    
    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        if isIncomingKeyboardPacket(data) {
            keyboardController.handleIncomingKeyboardPacket(data: data)
            return
        }
        
        guard data.count > packetTypeOffset else {
            #if DEBUG
            let message = String(data: data, encoding: .utf8)
            print("📩 [Unknown] FROM \(connection.endpoint) -> \(message ?? "Missing packet type")")
            #endif
            return
        }
        
        let start = data.startIndex
        let packetType = data[start + packetTypeOffset]
        
        switch packetType {
        case 0x01:
            mouseController.processIncomingNetworkData(data)
        case 0x02:
            handleKeyboardData(data, from: connection)
        case 0x03:
            handleGamepadData(data, from: connection)
        default:
            #if DEBUG
            print("📩 [Unknown] FROM \(connection.endpoint) -> packetType:\(packetType), bytes:\(data.count)")
            #endif
        }
    }
    
    private func handleKeyboardData(_ data: Data, from connection: NWConnection) {
        keyboardController.processIncomingNetworkData(data)
    }
    
    private func handleGamepadData(_ data: Data, from connection: NWConnection) {
        gamepadController.processIncomingNetworkData(data)
    }
    
    private func isIncomingKeyboardPacket(_ data: Data) -> Bool {
        guard let firstByte = data.first else { return false }
        
        // Control key packets: [0x04, action]
        if firstByte == 0x04 && data.count == 2 {
            return true
        }
        
        // Unicode keyboard packets: [0x03, ...utf8 bytes...]
        // Standard packets: [timestamp(4), type(1), ...]
        if firstByte == 0x03 {
            // If it's too short to be a standard packet (9 bytes min for Keyboard), it must be Unicode
            if data.count < 9 {
                return true
            }
            
            // If it could be a standard packet, check the packet type at offset 4
            let start = data.startIndex
            let packetType = data[start + packetTypeOffset]
            // If packet type is not Mouse(0x01), Keyboard(0x02), or Gamepad(0x03), it's likely Unicode
            if packetType != 0x01 && packetType != 0x02 && packetType != 0x03 {
                return true
            }
        }
        
        return false
    }
}
