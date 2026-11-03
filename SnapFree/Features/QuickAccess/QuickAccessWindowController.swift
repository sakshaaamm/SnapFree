//
//  QuickAccessWindowController.swift
//  SnapFree
//
//  Phase 3: Quick Access - Floating Preview Window Controller
//

import AppKit
import SwiftUI

class QuickAccessWindowController: NSWindowController {
    
    private var capture: CaptureItem?
    private var onCopy: (() -> Void)?
    private var onSave: (() -> Void)?
    private var onEdit: ((CaptureItem) -> Void)?
    
    convenience init(capture: CaptureItem, onCopy: @escaping () -> Void, onSave: @escaping () -> Void, onEdit: @escaping (CaptureItem) -> Void) {
        self.init()
        
        self.capture = capture
        self.onCopy = onCopy
        self.onSave = onSave
        self.onEdit = onEdit
        
        let contentView = QuickAccessView(
            capture: capture,
            onCopy: { [weak self] in
                self?.close()
                onCopy()
            },
            onSave: { [weak self] in
                self?.close()
                onSave()
            },
            onEdit: { [weak self] item in
                self?.close()
                onEdit(item)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: contentView)
        
        // Position at bottom right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowOrigin = NSPoint(
                x: screenFrame.maxX - 340,
                y: screenFrame.minY + 20
            )
            window.setFrameOrigin(windowOrigin)
        }
        
        self.window = window
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        // No auto-dismiss - user must click to close
    }
}
