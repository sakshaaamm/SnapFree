//
//  AppDelegate.swift
//  SnapFree
//
//  Phase 1: Foundation - App Lifecycle & Permissions
//

import SwiftUI
import ScreenCaptureKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Capture manager reference (using singleton)
    private var captureManager = CaptureManager.shared
    
    // Persistent menu bar item. Held strongly so it never disappears.
    private var statusBarController: StatusBarController?
    
    // Keep a process-info activity to prevent the system from terminating
    // this background (LSUIElement) app automatically.
    private var terminationAssertion: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the persistent status bar item.
        statusBarController = StatusBarController()
        
        // Prevent automatic/sudden termination that causes the app to be
        // killed and relaunched (which re-triggers the permission prompt).
        ProcessInfo.processInfo.disableAutomaticTermination("SnapFree menu bar app must stay alive")
        ProcessInfo.processInfo.disableSuddenTermination()
        
        // Hold an activity assertion so the app is never considered idle.
        terminationAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.background, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "SnapFree menu bar app must stay alive"
        )
        
        // Request screen recording permission on launch
        Task {
            let hasPermission = await checkScreenRecordingPermission()
            if !hasPermission {
                // Only show alert once per launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showPermissionAlert()
                }
            }
        }
        
        // Setup global shortcuts
        ShortcutManager.shared.setCaptureManager(captureManager)
        ShortcutManager.shared.registerAllHotKeys()
        
        print("✅ SnapFree launched - Global shortcuts registered")
    }
    
    // Menu bar apps have no windows; never terminate because of that.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Permissions
    
    @MainActor
    private func checkScreenRecordingPermission() async -> Bool {
        do {
            // This will trigger the permission request if not already granted
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            print("✅ Screen recording permission granted. Found \(content.windows.count) windows")
            return true
        } catch {
            print("❌ Screen recording permission denied: \(error.localizedDescription)")
            return false
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup - unregister hot keys
        ShortcutManager.shared.unregisterAllHotKeys()
        
        // Release the activity assertion
        if let assertion = terminationAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            terminationAssertion = nil
        }
    }
    

    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "SnapFree needs screen recording permission to capture screenshots.\n\nPlease grant permission in System Settings > Privacy & Security > Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}
