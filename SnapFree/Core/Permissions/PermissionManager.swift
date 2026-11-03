//
//  PermissionManager.swift
//  SnapFree
//
//  Phase 1: Foundation - Permission Handling
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var hasScreenRecordingPermission = false
    
    private init() {}
    
    /// Check if screen recording permission is granted
    @MainActor
    func checkScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            hasScreenRecordingPermission = true
            return true
        } catch {
            hasScreenRecordingPermission = false
            return false
        }
    }
    
    /// Open System Settings to Screen Recording permissions
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Camera & Microphone
    
    /// Request access to a capture device up front, awaiting the user's choice.
    /// Returns true if access is (or becomes) authorized.
    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            // Triggers the system prompt and suspends until the user answers.
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    var cameraAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Ensure every permission the current recording settings require is granted
    /// BEFORE recording starts. Prompts for any not-yet-determined permission and
    /// waits for the response. If something the user asked for is denied, shows a
    /// single alert offering to open System Settings and returns false so the
    /// caller can abort. Returns true when it's safe to begin recording.
    @MainActor
    func ensureRecordingPermissions(wantsCamera: Bool, wantsMicrophone: Bool) async -> Bool {
        // 1. Screen recording is always required.
        let screenOK = await checkScreenRecordingPermission()
        if !screenOK {
            showPermissionAlert(
                title: "Screen Recording Permission Needed",
                message: "SnapFree needs Screen Recording access to record your screen. Enable it in System Settings → Privacy & Security → Screen Recording, then try again.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
            return false
        }
        
        // 2. Camera (only if the user enabled Face Cam).
        if wantsCamera {
            let ok = await requestAccess(for: .video)
            if !ok {
                showPermissionAlert(
                    title: "Camera Permission Needed",
                    message: "Face Cam is on, but Camera access is denied. Enable it in System Settings → Privacy & Security → Camera, or turn off Face Cam before recording.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                )
                return false
            }
        }
        
        // 3. Microphone (only if the user enabled mic recording).
        if wantsMicrophone {
            let ok = await requestAccess(for: .audio)
            if !ok {
                showPermissionAlert(
                    title: "Microphone Permission Needed",
                    message: "Microphone recording is on, but Microphone access is denied. Enable it in System Settings → Privacy & Security → Microphone, or turn off Microphone before recording.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                return false
            }
        }
        
        return true
    }
    
    @MainActor
    private func showPermissionAlert(title: String, message: String, settingsURL: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
