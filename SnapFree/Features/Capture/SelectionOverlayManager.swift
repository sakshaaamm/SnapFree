//
//  SelectionOverlayManager.swift
//  SnapFree
//
//  Phase 1: Foundation - Selection Overlay Coordinator
//

import AppKit
import ScreenCaptureKit

@MainActor
class SelectionOverlayManager {
    
    // MARK: - Singleton
    
    static let shared = SelectionOverlayManager()
    
    // MARK: - State
    
    var selectedRect: CGRect?
    var selectedWindow: SCWindow?
    
    // MARK: - Private Properties
    
    private var areaSelectionContinuation: CheckedContinuation<CGRect, Error>?
    private var windowSelectionContinuation: CheckedContinuation<SCWindow?, Error>?
    
    // Strong references to the currently-shown overlay windows. ARC owns them;
    // we never call close() on them (which would double-release because a
    // borderless window defaults to isReleasedWhenClosed = true).
    private var areaWindows: [NSWindow] = []
    private var highlightWindows: [NSWindow] = []
    
    // MARK: - Overlay Window Factory
    
    private func makeOverlayWindow(screenFrame: NSRect, contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Critical: do NOT auto-release on close. We manage lifetime via ARC.
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = contentView
        return window
    }
    
    /// Hide the given windows and release our references so ARC can
    /// deallocate them cleanly on a later run-loop turn.
    private func dismiss(_ windows: inout [NSWindow]) {
        let toDismiss = windows
        windows = []
        for window in toDismiss {
            window.orderOut(nil)
            // Drop the content view so no pending event handler keeps a
            // reference to the window while it is torn down.
            window.contentView = nil
        }
        // `toDismiss` goes out of scope here; ARC releases the windows.
    }
    
    // MARK: - Area Selection
    
    /// Show area selection overlay and wait for user to select a region
    func requestAreaSelection() async throws -> CGRect {
        selectedRect = nil
        
        // Clean up any leftover windows from a previous run.
        dismiss(&areaWindows)
        
        var windows: [NSWindow] = []
        for screen in NSScreen.screens {
            // The view uses screen-local coordinates (origin 0,0), while the
            // window is positioned at the screen's global frame.
            let localFrame = NSRect(origin: .zero, size: screen.frame.size)
            let contentView = AreaSelectionOverlayView(frame: localFrame, screen: screen)
            let window = makeOverlayWindow(screenFrame: screen.frame, contentView: contentView)
            windows.append(window)
        }
        areaWindows = windows
        
        for window in areaWindows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            self.areaSelectionContinuation = continuation
        }
    }
    
    func confirmAreaSelection(_ rect: CGRect) {
        let continuation = areaSelectionContinuation
        areaSelectionContinuation = nil
        dismiss(&areaWindows)
        continuation?.resume(returning: rect)
    }
    
    func cancelAreaSelection() {
        let continuation = areaSelectionContinuation
        areaSelectionContinuation = nil
        dismiss(&areaWindows)
        continuation?.resume(throwing: CaptureError.cancelled)
    }
    
    // MARK: - Window Selection
    
    /// Show window selection overlay and wait for user to select a window
    func requestWindowSelection() async throws -> SCWindow? {
        let displayManager = DisplayManager.shared
        try await displayManager.refreshContent()
        
        dismiss(&highlightWindows)
        
        var windows: [NSWindow] = []
        for screen in NSScreen.screens {
            let contentView = WindowHighlightOverlayView(frame: screen.frame)
            let window = makeOverlayWindow(screenFrame: screen.frame, contentView: contentView)
            windows.append(window)
        }
        highlightWindows = windows
        
        for window in highlightWindows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            self.windowSelectionContinuation = continuation
        }
    }
    
    func confirmWindowSelection(_ window: SCWindow?) {
        let continuation = windowSelectionContinuation
        windowSelectionContinuation = nil
        dismiss(&highlightWindows)
        continuation?.resume(returning: window)
    }
    
    func cancelWindowSelection() {
        let continuation = windowSelectionContinuation
        windowSelectionContinuation = nil
        dismiss(&highlightWindows)
        continuation?.resume(throwing: CaptureError.cancelled)
    }
    
    // Private init to enforce singleton
    private init() {}
}
