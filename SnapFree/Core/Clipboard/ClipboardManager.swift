//
//  ClipboardManager.swift
//  SnapFree
//
//  Phase 1: Foundation - Clipboard Operations
//

import AppKit

class ClipboardManager {
    static let shared = ClipboardManager()
    
    private init() {}
    
    /// Copy image to clipboard
    func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    /// Copy file path to clipboard
    func copyFilePath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .fileURL)
    }
}
