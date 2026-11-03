//
//  AreaSelectionOverlayView.swift
//  SnapFree
//
//  Phase 1: Foundation - Area Selection UI
//

import AppKit

class AreaSelectionOverlayView: NSView {
    
    // The screen this overlay covers (used for coordinate conversion)
    let screen: NSScreen
    
    // Selection state
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false
    
    // Visual properties
    private let overlayColor = NSColor.black.withAlphaComponent(0.3)
    private let selectionColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let borderColor = NSColor.systemBlue
    private let borderWidth: CGFloat = 2
    
    // MARK: - Initialization
    
    init(frame frameRect: NSRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw dimmed overlay for entire screen
        overlayColor.setFill()
        bounds.fill()
        
        // If dragging, cut out the selection area
        if isDragging && !currentRect.isEmpty {
            // Clear the selection area (make it bright)
            context.setBlendMode(.destinationOut)
            selectionColor.setFill()
            currentRect.fill()
            context.setBlendMode(.normal)
            
            // Draw border
            borderColor.setStroke()
            let borderPath = NSBezierPath(rect: currentRect)
            borderPath.lineWidth = borderWidth
            borderPath.stroke()
            
            // Draw size indicator
            drawSizeIndicator(in: currentRect)
            
            // Draw crosshairs
            drawCrosshairs(for: currentRect)
        }
    }
    
    private func drawSizeIndicator(in rect: NSRect) {
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = sizeText.size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.minY - textSize.height - 8
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
        sizeText.draw(at: textOrigin, withAttributes: attributes)
    }
    
    private func drawCrosshairs(for rect: NSRect) {
        let dashLength: CGFloat = 10
        let gapLength: CGFloat = 5
        
        borderColor.setStroke()
        
        // Horizontal crosshair at center
        let hPath = NSBezierPath()
        hPath.setLineDash([dashLength, gapLength], count: 2, phase: 0)
        hPath.move(to: NSPoint(x: rect.minX, y: rect.midY))
        hPath.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        hPath.stroke()
        
        // Vertical crosshair at center
        let vPath = NSBezierPath()
        vPath.setLineDash([dashLength, gapLength], count: 2, phase: 0)
        vPath.move(to: NSPoint(x: rect.midX, y: rect.minY))
        vPath.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        vPath.stroke()
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
        currentRect = .zero
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = startPoint else { return }
        
        let currentPoint = convert(event.locationInWindow, from: nil)
        
        // Calculate selection rect
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let width = abs(currentPoint.x - startPoint.x)
        let height = abs(currentPoint.y - startPoint.y)
        
        currentRect = NSRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        
        // If selection is large enough, confirm it
        if currentRect.width > 10 && currentRect.height > 10 {
            // Convert the view-local selection (bottom-left origin) into a
            // rect relative to this screen with a TOP-LEFT origin, which is
            // the coordinate space ScreenCaptureKit's screenshot uses.
            let selection = currentRect
            let screenHeight = screen.frame.height
            
            // currentRect is in view coordinates == screen-local coordinates
            // (the window exactly covers the screen). Flip Y so the origin is
            // at the top of the screen instead of the bottom.
            let flippedRect = CGRect(
                x: selection.origin.x,
                y: screenHeight - selection.origin.y - selection.height,
                width: selection.width,
                height: selection.height
            )
            
            Task { @MainActor in
                SelectionOverlayManager.shared.confirmAreaSelection(flippedRect)
            }
        } else {
            // Cancel if too small
            Task { @MainActor in
                SelectionOverlayManager.shared.cancelAreaSelection()
            }
        }
        
        startPoint = nil
        needsDisplay = true
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            Task { @MainActor in
                SelectionOverlayManager.shared.cancelAreaSelection()
            }
        }
    }
    
    // MARK: - Hit Testing
    
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}
