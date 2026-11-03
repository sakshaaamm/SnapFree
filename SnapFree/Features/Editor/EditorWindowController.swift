//
//  EditorWindowController.swift
//  SnapFree
//
//  Hosts the SwiftUI annotation editor in a standalone window.
//

import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
    
    convenience init(capture: CaptureItem) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapFree Editor"
        window.isReleasedWhenClosed = false
        window.center()
        
        self.init(window: window)
        
        let root = EditorView(capture: capture) { [weak self] in
            // onClose: dismiss the editor window
            self?.close()
        }
        window.contentView = NSHostingView(rootView: root)
    }
    
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
