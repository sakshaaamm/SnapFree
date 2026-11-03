//
//  HistoryWindowController.swift
//  SnapFree
//
//  Hosts the capture-history grid in a standalone window.
//

import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    
    convenience init(onEdit: @escaping (CaptureItem) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapFree History"
        window.isReleasedWhenClosed = false
        window.center()
        
        self.init(window: window)
        
        window.contentView = NSHostingView(rootView: HistoryView(onEdit: onEdit))
    }
    
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
