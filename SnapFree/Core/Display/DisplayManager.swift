//
//  DisplayManager.swift
//  SnapFree
//
//  Phase 1: Foundation - Multi-Display Support
//

import AppKit
import ScreenCaptureKit

class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    
    private init() {}
    
    /// Refresh the list of available displays and windows
    @MainActor
    func refreshContent() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        self.displays = content.displays
        self.windows = content.windows
        
        print("🖥️ Found \(displays.count) displays, \(windows.count) windows")
    }
    
    /// Get the main display
    var mainDisplay: SCDisplay? {
        displays.first { $0.displayID == CGMainDisplayID() }
    }
    
    /// Get display at mouse cursor location
    func displayAtMouseLocation() -> SCDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        return displays.first { $0.frame.contains(NSPoint(x: mouseLocation.x, y: mouseLocation.y)) }
    }
    
    /// Get windows belonging to a specific app
    func windowsForApp(named appName: String) -> [SCWindow] {
        windows.filter { $0.owningApplication?.applicationName == appName }
    }
    
    /// Get windows excluding the current app
    var otherWindows: [SCWindow] {
        windows.filter { 
            $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier 
        }
    }
}
