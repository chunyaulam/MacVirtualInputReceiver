import SwiftUI
import Darwin

struct ContentView: View {
    @State private var udpManager = UDPListenerManager()
    @State private var isServerRunning = false
    @State private var serverAddress: String?
    
    private let serverPort: UInt16 = 8567
    
    var body: some View {
        VStack(spacing: 20) {
            
            Button(isServerRunning ? "Stop Server" : "Start Server") {
                toggleServer()
            }
            .buttonStyle(.borderedProminent)
            .tint(isServerRunning ? .red : .accentColor)
            
            if let serverAddress {
                Text("Server running on \(serverAddress)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 360, height: 220)
    }
    
    private func toggleServer() {
        isServerRunning.toggle()
        
        if isServerRunning {
            udpManager.startListening(port: serverPort)
            serverAddress = "\(localIPAddress() ?? "Unknown IP"):\(serverPort)"
        } else {
            udpManager.stopListening()
            serverAddress = nil
        }
    }
    
    private func localIPAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        
        var fallbackAddress: String?
        var pointer = interfaces
        
        while pointer != nil {
            guard let interface = pointer?.pointee else {
                pointer = pointer?.pointee.ifa_next
                continue
            }
            
            defer { pointer = interface.ifa_next }
            
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  let name = String(validatingUTF8: interface.ifa_name),
                  name != "lo0" else {
                continue
            }
            
            var address = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                &address,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            
            guard result == 0, let ipAddress = String(validatingUTF8: hostname) else { continue }
            
            if name == "en0" || name == "en1" {
                return ipAddress
            }
            
            fallbackAddress = fallbackAddress ?? ipAddress
        }
        
        return fallbackAddress
    }
}

#Preview {
    ContentView()
}
