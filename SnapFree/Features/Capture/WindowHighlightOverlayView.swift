//
//  WindowHighlightOverlayView.swift
//  SnapFree
//
//  Phase 1: Foundation - Window Selection UI
//

import AppKit
import ScreenCaptureKit

class WindowHighlightOverlayView: NSView {
    
    // Currently highlighted window
    private var highlightedWindow: SCWindow?
    private var highlightedRect: NSRect = .zero
    
    // Visual properties
    private let highlightColor = NSColor.systemBlue.withAlphaComponent(0.2)
    private let borderColor = NSColor.systemBlue
    private let borderWidth: CGFloat = 3
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw transparent overlay
        NSColor.black.withAlphaComponent(0.1).setFill()
        bounds.fill()
        
        // Draw highlight around selected window
        if !highlightedRect.isEmpty {
            // Clear highlight area
            context.setBlendMode(.destinationOut)
            highlightColor.setFill()
            highlightedRect.fill()
            context.setBlendMode(.normal)
            
            // Draw border
            borderColor.setStroke()
            let borderPath = NSBezierPath(rect: highlightedRect)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()
            
            // Draw window name
            if let window = highlightedWindow {
                drawWindowName(window, in: highlightedRect)
            }
        }
    }
    
    private func drawWindowName(_ window: SCWindow, in rect: NSRect) {
        let appName = window.owningApplication?.applicationName ?? "Unknown"
        let title = window.title ?? ""
        let text = title.isEmpty ? appName : "\(appName) - \(title)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: rect.minX + 8,
            y: rect.minY + 8
        )
        
        // Draw background
        let bgRect = NSRect(
            x: textOrigin.x - 4,
            y: textOrigin.y - 2,
            width: textSize.width + 8,
            height: textSize.height + 4
        )
        NSColor.darkGray.withAlphaComponent(0.8).setFill()
        bgRect.fill()
        
        // Draw text
        text.draw(at: textOrigin, withAttributes: attributes)
    }
    
    // MARK: - Mouse Events
    
    override func mouseMoved(with event: NSEvent) {
        let mouseLocation = convert(event.locationInWindow, from: nil)
        
        // Find window under mouse
        Task { @MainActor in
            if let window = await findWindowAt(mouseLocation) {
                highlightedWindow = window
                highlightedRect = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: window.frame.width,
                    height: window.frame.height
                )
            } else {
                highlightedWindow = nil
                highlightedRect = .zero
            }
            needsDisplay = true
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let window = highlightedWindow {
            Task { @MainActor in
                SelectionOverlayManager.shared.confirmWindowSelection(window)
            }
        } else {
            Task { @MainActor in
                SelectionOverlayManager.shared.cancelWindowSelection()
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            Task { @MainActor in
                SelectionOverlayManager.shared.cancelWindowSelection()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func findWindowAt(_ point: NSPoint) async -> SCWindow? {
        let displayManager = DisplayManager.shared
        
        // Convert to screen coordinates
        let screenPoint = convertToScreen(point)
        
        // Find window containing this point
        return displayManager.otherWindows.first { window in
            window.frame.contains(screenPoint)
        }
    }
    
    private func convertToScreen(_ point: NSPoint) -> CGPoint {
        // NSView coordinates are flipped, need to convert
        let windowPoint = convert(point, to: nil)
        return windowPoint
    }
    
    // MARK: - Hit Testing
    
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Start tracking mouse movements
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}
