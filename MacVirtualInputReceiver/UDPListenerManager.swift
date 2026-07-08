import Foundation
import Network

class UDPListenerManager {
    var listener: NWListener?
    let queue = DispatchQueue(label: "com.example.udp.listener")
    private let mouseController = MouseController()

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
        if data.count == 16 {
            mouseController.processIncomingNetworkData(data)
        } else {
            let message = String(data: data, encoding: .utf8)
            print("📩 [String] FROM \(connection.endpoint) -> \(message ?? "EMPTY DATA")")
        }
    }
}
