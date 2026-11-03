//
//  CaptureItem.swift
//  SnapFree
//
//  Phase 1: Foundation - Capture Data Model
//

import Foundation
import SwiftUI

struct CaptureItem: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: CaptureType
    let image: NSImage
    let sourceAppName: String?
    
    // Equatable: two captures are equal if they share the same id
    static func == (lhs: CaptureItem, rhs: CaptureItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // Computed properties
    var thumbnail: NSImage {
        // Return a smaller version for history
        let maxSize: CGFloat = 200
        let ratio = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        return resized
    }
    
    var filename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "SnapFree \(formatter.string(from: timestamp))"
    }
    
    init(type: CaptureType, image: NSImage, sourceAppName: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.image = image
        self.sourceAppName = sourceAppName
    }
    
    /// Full initializer used when reconstructing an item (e.g. from history).
    init(id: UUID, timestamp: Date, type: CaptureType, image: NSImage, sourceAppName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.image = image
        self.sourceAppName = sourceAppName
    }
}
