//
//  MacVirtualInputReceiverApp.swift
//  MacVirtualInputReceiver
//
//  Created by Derek LAM on 6/7/2026.
//

import SwiftUI
import AppKit
import ApplicationServices
import Combine
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class ServerController: ObservableObject {
    @Published private(set) var isServerRunning = false
    @Published private(set) var serverAddress: String?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    
    private let udpManager = UDPListenerManager()
    private let serverPort: UInt16 = 8567
    
    init(autoStart: Bool = true) {
        if autoStart {
            startServer()
        }
    }
    
    func toggleServer() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }
    
    func startServer() {
        guard !isServerRunning else { return }
        
        refreshAccessibilityTrust()
        udpManager.startListening(port: serverPort)
        serverAddress = "\(localIPAddress() ?? "Unknown IP"):\(serverPort)"
        isServerRunning = true
    }
    
    func stopServer() {
        guard isServerRunning else { return }
        
        udpManager.stopListening()
        serverAddress = nil
        isServerRunning = false
    }
    
    func refreshAccessibilityTrust() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        udpManager.refreshAccessibilityTrust()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
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
            
            guard let ifaAddr = interface.ifa_addr,
                  ifaAddr.pointee.sa_family == UInt8(AF_INET),
                  let name = String(validatingUTF8: interface.ifa_name),
                  name != "lo0" else {
                continue
            }
            
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                ifaAddr,
                socklen_t(ifaAddr.pointee.sa_len),
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

@main
struct MacVirtualInputReceiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var serverController = ServerController()
    
    var body: some Scene {
        MenuBarExtra(
            "Mac Virtual Input Receiver",
            systemImage: serverController.isServerRunning ? "computermouse.fill" : "computermouse"
        ) {
            ContentView(serverController: serverController)
        }
        .menuBarExtraStyle(.window)
    }
}
