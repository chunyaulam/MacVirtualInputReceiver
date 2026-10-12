import SwiftUI

struct ContentView: View {
    @ObservedObject var serverController: ServerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: serverController.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(serverController.isServerRunning ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(serverController.isServerRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                    
                    if let serverAddress = serverController.serverAddress {
                        Text(serverAddress)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("UDP listener is not active")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 10) {
                Image(systemName: serverController.isAccessibilityTrusted ? "keyboard.badge.ellipsis" : "exclamationmark.triangle.fill")
                    .foregroundColor(serverController.isAccessibilityTrusted ? .secondary : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(serverController.isAccessibilityTrusted ? "Keyboard Permission Ready" : "Accessibility Permission Needed")
                        .font(.subheadline)
                    
                    if !serverController.isAccessibilityTrusted {
                        Text("Required for posting keyboard and mouse events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if !serverController.isAccessibilityTrusted {
                    Button("Allow") {
                        serverController.requestAccessibilityPermission()
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button(serverController.isServerRunning ? "Stop Server" : "Start Server") {
                    serverController.toggleServer()
                }
                .buttonStyle(.borderedProminent)
                .tint(serverController.isServerRunning ? .red : .accentColor)
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            serverController.refreshAccessibilityTrust()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !serverController.isAccessibilityTrusted {
                    serverController.refreshAccessibilityTrust()
                }
            }
        }
    }
}

#Preview {
    ContentView(serverController: ServerController(autoStart: false))
}
