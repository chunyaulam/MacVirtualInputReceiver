import Foundation
import Network

class UDPListenerManager {
    var listener: NWListener?
    let queue = DispatchQueue(label: "com.example.udp.listener")
    private let mouseController = MouseController()
    private let keyboardController = KeyboardController()
    private let gamepadController = GamepadController()
    private let packetTypeOffset = 4

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
                    print("🟢 UDP Listener Started，Listening Port: \(port)")
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
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextPacket(on: connection)
    }
    
    private func receiveNextPacket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] content, _, _, error in
            if let error = error {
                print("Error on receiving UDP data: \(error)")
                connection.cancel()
                return
            }
            
            if let data = content, !data.isEmpty {
                self?.handleReceivedData(data, from: connection)
            }
            
            self?.receiveNextPacket(on: connection)
        }
    }
    
    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        if isIncomingKeyboardPacket(data) {
            keyboardController.handleIncomingKeyboardPacket(data: data)
            return
        }
        
        guard data.count > packetTypeOffset else {
            let message = String(data: data, encoding: .utf8)
            print("📩 [Unknown] FROM \(connection.endpoint) -> \(message ?? "Missing packet type")")
            return
        }
        
        let packetType = data[packetTypeOffset]
        
        switch packetType {
        case 0x01:
            mouseController.processIncomingNetworkData(data)
        case 0x02:
            handleKeyboardData(data, from: connection)
        case 0x03:
            handleGamepadData(data, from: connection)
        default:
            print("📩 [Unknown] FROM \(connection.endpoint) -> packetType:\(packetType), bytes:\(data.count)")
        }
    }
    
    private func handleKeyboardData(_ data: Data, from connection: NWConnection) {
        keyboardController.processIncomingNetworkData(data)
    }
    
    private func handleGamepadData(_ data: Data, from connection: NWConnection) {
        gamepadController.processIncomingNetworkData(data)
    }
    
    private func isIncomingKeyboardPacket(_ data: Data) -> Bool {
        guard let channel = data.first else { return false }
        
        switch channel {
        case 0x03:
            return data.count <= packetTypeOffset || data[packetTypeOffset] != 0x03
        case 0x04:
            return data.count >= 2
        default:
            return false
        }
    }
}
