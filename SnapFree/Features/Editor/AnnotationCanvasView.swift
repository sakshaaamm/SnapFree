//
//  AnnotationCanvasView.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Interactive Canvas View
//

import SwiftUI

struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var model: AnnotationCanvasModel
    
    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.model = model
        view.setupView()
        return view
    }
    
    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.model = model
        nsView.needsDisplay = true
    }
}

// MARK: - NSView Implementation

class AnnotationCanvasNSView: NSView {
    
    var model: AnnotationCanvasModel?
    
    // Drawing state
    private var isDrawing = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    
    // Text input
    private var textField: NSTextField?
    
    // Crop state
    private var isCropping = false
    private var cropRect: CGRect = .zero
    
    // Move state (dragging a selected annotation)
    private var isMoving = false
    private var moveStartImagePoint: CGPoint = .zero
    private var movedAnnotationID: UUID?
    private var moveOriginalFrame: CGRect = .zero
    
    // Freehand pen state
    private var isPenDrawing = false
    private var penPoints: [CGPoint] = []
    
    // MARK: - Setup
    
    func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let model = model else { return }
        
        // Draw the image centered and scaled to fit
        let imageSize = model.image.size
        let viewSize = bounds.size
        
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2
        
        let imageRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
        
        // Draw image
        model.image.draw(in: imageRect)
        
        // Draw annotations
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Scale and translate context for annotations
        context?.translateBy(x: offsetX, y: offsetY)
        context?.scaleBy(x: scale, y: scale)
        
        for annotation in model.annotations {
            if annotation is PixelateAnnotation {
                // Pixelate is drawn differently
                drawPixelateRegion(annotation as! PixelateAnnotation, in: context!, scale: scale)
            } else if annotation is BlurAnnotation {
                // Blur is drawn differently
                drawBlurRegion(annotation as! BlurAnnotation, in: context!, scale: scale)
            } else {
                annotation.draw(in: context!, on: model.image)
            }
        }
        
        // Draw current drawing
        if isDrawing {
            drawCurrentAnnotation(in: context!, scale: scale)
        }
        
        // Draw in-progress freehand stroke
        if isPenDrawing, penPoints.count > 1 {
            context?.saveGState()
            context?.setStrokeColor(NSColor(model.currentColor).cgColor)
            context?.setLineWidth(model.lineWidth)
            context?.setLineCap(.round)
            context?.setLineJoin(.round)
            context?.move(to: penPoints[0])
            for p in penPoints.dropFirst() { context?.addLine(to: p) }
            context?.strokePath()
            context?.restoreGState()
        }
        
        // Draw crop overlay
        if isCropping {
            drawCropOverlay(in: context!, scale: scale)
        }
        
        // Draw selection indicator
        if let selected = model.selectedAnnotation {
            drawSelectionIndicator(for: selected, in: context!)
        }
        
        context?.restoreGState()
    }
    
    private func drawPixelateRegion(_ annotation: PixelateAnnotation, in context: CGContext, scale: CGFloat) {
        // Render the ACTUAL pixelation so the editor preview matches export.
        guard let model = model,
              let patch = model.effectPatch(.pixelate(scale: annotation.pixelSize),
                                            region: annotation.frame) else {
            // Fallback: gray fill if the effect could not be produced.
            context.setFillColor(NSColor.gray.withAlphaComponent(0.6).cgColor)
            context.fill(annotation.frame)
            return
        }
        context.saveGState()
        context.draw(patch, in: annotation.frame)
        context.restoreGState()
    }
    
    private func drawBlurRegion(_ annotation: BlurAnnotation, in context: CGContext, scale: CGFloat) {
        // Render the ACTUAL blur so the editor preview matches export.
        guard let model = model,
              let patch = model.effectPatch(.blur(radius: annotation.blurRadius),
                                            region: annotation.frame) else {
            context.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
            context.fill(annotation.frame)
            return
        }
        context.saveGState()
        context.draw(patch, in: annotation.frame)
        context.restoreGState()
    }
    
    private func drawCurrentAnnotation(in context: CGContext, scale: CGFloat) {
        guard let model = model else { return }
        
        // Preview the current drawing
        let previewFrame = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        
        let nsColor = NSColor(model.currentColor)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(model.lineWidth)
        
        context.setLineWidth(model.lineWidth)
        
        switch model.currentTool {
        case .arrow:
            var arrow = ArrowAnnotation(start: startPoint, end: currentPoint, color: model.currentColor)
            arrow.lineWidth = model.lineWidth
            arrow.draw(in: context, on: model.image)
            
        case .rectangle:
            context.stroke(previewFrame)
            
        case .circle:
            context.strokeEllipse(in: previewFrame)
            
        case .line:
            context.move(to: startPoint)
            context.addLine(to: currentPoint)
            context.strokePath()
            
        case .highlight:
            // Spotlight preview: dim everything outside the selection.
            let bounds = CGRect(origin: .zero, size: model.image.size)
            context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            let outside = CGMutablePath()
            outside.addRect(bounds)
            outside.addRect(previewFrame)
            context.addPath(outside)
            context.fillPath(using: .evenOdd)
            
        case .textHighlight:
            // Preview the search box as a light marker tint.
            context.setFillColor(NSColor(model.currentColor).withAlphaComponent(0.25).cgColor)
            context.fill(previewFrame)
            
        case .blur, .pixelate:
            context.setFillColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
            context.fill(previewFrame)
            
        case .select, .pen, .text, .counter, .crop:
            // Pen previews via penPoints; text/counter place on click; crop
            // draws its own overlay; select has no preview.
            break
        }
    }
    
    private func drawCropOverlay(in context: CGContext, scale: CGFloat) {
        // Dim the entire image
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fill(bounds)
        
        // Clear the crop area
        context.clear(cropRect)
        
        // Draw crop border
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.stroke(cropRect)
        
        // Draw grid lines (rule of thirds)
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        
        // Vertical lines
        let thirdWidth = cropRect.width / 3
        context.move(to: CGPoint(x: cropRect.minX + thirdWidth, y: cropRect.minY))
        context.addLine(to: CGPoint(x: cropRect.minX + thirdWidth, y: cropRect.maxY))
        context.move(to: CGPoint(x: cropRect.minX + 2 * thirdWidth, y: cropRect.minY))
        context.addLine(to: CGPoint(x: cropRect.minX + 2 * thirdWidth, y: cropRect.maxY))
        
        // Horizontal lines
        let thirdHeight = cropRect.height / 3
        context.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + thirdHeight))
        context.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + thirdHeight))
        context.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + 2 * thirdHeight))
        context.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + 2 * thirdHeight))
        
        context.strokePath()
    }
    
    private func drawSelectionIndicator(for annotation: any AnnotationProtocol, in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(annotation.frame.insetBy(dx: -4, dy: -4))
        context.setLineDash(phase: 0, lengths: [])
        
        // Draw resize handles
        let handleSize: CGFloat = 8
        let handles = [
            annotation.frame.origin,
            CGPoint(x: annotation.frame.maxX, y: annotation.frame.minY),
            CGPoint(x: annotation.frame.minX, y: annotation.frame.maxY),
            CGPoint(x: annotation.frame.maxX, y: annotation.frame.maxY)
        ]
        
        context.setFillColor(NSColor.systemBlue.cgColor)
        for handle in handles {
            let handleRect = CGRect(
                x: handle.x - handleSize / 2,
                y: handle.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fillEllipse(in: handleRect)
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        guard let model = model else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        
        // Convert to image coordinates
        let imageCoords = convertToImageCoordinates(location)
        
        if model.currentTool == .text {
            // Show text input
            showTextInput(at: imageCoords)
            return
        }
        
        if model.currentTool == .counter {
            // Click to drop a numbered badge.
            let counter = model.makeCounter(at: imageCoords)
            let command = AddAnnotationCommand(annotation: counter, canvas: model)
            model.history.execute(command)
            needsDisplay = true
            return
        }
        
        if model.currentTool == .pen {
            // Begin a freehand stroke.
            isPenDrawing = true
            penPoints = [imageCoords]
            needsDisplay = true
            return
        }
        
        if model.currentTool == .crop {
            isCropping = true
            startPoint = imageCoords
            currentPoint = imageCoords
            return
        }
        
        if model.currentTool == .textHighlight {
            // Detect text in the drawn box and highlight just the text lines.
            isDrawing = true
            startPoint = imageCoords
            currentPoint = imageCoords
            return
        }
        
        // Only the Select tool moves existing annotations. Every drawing tool
        // always starts a NEW annotation so they stack on top of each other.
        if model.currentTool == .select {
            model.selectAnnotation(at: imageCoords)
            if let selected = model.selectedAnnotation {
                isMoving = true
                movedAnnotationID = selected.id
                moveOriginalFrame = selected.frame
                moveStartImagePoint = imageCoords
            }
            return
        }
        
        // Start drawing a new annotation (stacks on top of existing ones).
        model.selectedAnnotation = nil
        isDrawing = true
        startPoint = imageCoords
        currentPoint = imageCoords
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let model = model else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        let imageCoords = convertToImageCoordinates(location)
        
        if isPenDrawing {
            penPoints.append(imageCoords)
            needsDisplay = true
            return
        }
        
        if isCropping {
            // Update crop rect during drag so the overlay is visible
            currentPoint = imageCoords
            cropRect = CGRect(
                x: min(startPoint.x, currentPoint.x),
                y: min(startPoint.y, currentPoint.y),
                width: abs(currentPoint.x - startPoint.x),
                height: abs(currentPoint.y - startPoint.y)
            )
            needsDisplay = true
            return
        }
        
        if isMoving, let id = movedAnnotationID {
            let dx = imageCoords.x - moveStartImagePoint.x
            let dy = imageCoords.y - moveStartImagePoint.y
            model.moveAnnotation(id: id, to: moveOriginalFrame.offsetBy(dx: dx, dy: dy))
            needsDisplay = true
            return
        }
        
        currentPoint = imageCoords
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let model = model else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        let imageCoords = convertToImageCoordinates(location)
        
        if isCropping {
            // Finalize crop
            isCropping = false
            let finalCropRect = CGRect(
                x: min(startPoint.x, imageCoords.x),
                y: min(startPoint.y, imageCoords.y),
                width: abs(imageCoords.x - startPoint.x),
                height: abs(imageCoords.y - startPoint.y)
            )
            print("🧪 crop mouseUp: rect=\(finalCropRect) imageSizeBefore=\(model.image.size)")
            
            if finalCropRect.width > 10 && finalCropRect.height > 10 {
                // Use the command so crop is undoable.
                let command = CropCommand(cropRect: finalCropRect, canvas: model)
                model.history.execute(command)
                print("🧪 crop done: imageSizeAfter=\(model.image.size)")
            } else {
                print("🧪 crop SKIPPED (too small)")
            }
            needsDisplay = true
            return
        }
        
        if isPenDrawing {
            isPenDrawing = false
            penPoints.append(imageCoords)
            if penPoints.count > 1 {
                let pen = model.makePen(points: penPoints)
                let command = AddAnnotationCommand(annotation: pen, canvas: model)
                model.history.execute(command)
            }
            penPoints = []
            needsDisplay = true
            return
        }
        
        if isMoving, let id = movedAnnotationID {
            isMoving = false
            let dx = imageCoords.x - moveStartImagePoint.x
            let dy = imageCoords.y - moveStartImagePoint.y
            let newFrame = moveOriginalFrame.offsetBy(dx: dx, dy: dy)
            
            // Only record an undoable move if it actually moved.
            if abs(dx) > 1 || abs(dy) > 1 {
                let command = MoveAnnotationCommand(
                    annotationID: id,
                    from: moveOriginalFrame,
                    to: newFrame,
                    canvas: model
                )
                // The frame is already at newFrame from the live drag; execute
                // via history so undo/redo works (execute re-applies newFrame).
                model.history.execute(command)
            }
            movedAnnotationID = nil
            needsDisplay = true
            return
        }
        
        if isDrawing {
            isDrawing = false
            
            if model.currentTool == .textHighlight {
                let region = CGRect(
                    x: min(startPoint.x, imageCoords.x),
                    y: min(startPoint.y, imageCoords.y),
                    width: abs(imageCoords.x - startPoint.x),
                    height: abs(imageCoords.y - startPoint.y)
                )
                highlightDetectedText(in: region)
                needsDisplay = true
                return
            }
            
            // Create annotation
            if let annotation = model.createAnnotation(from: startPoint, to: imageCoords) {
                print("🧪 mouseUp: created \(annotation.type) frame=\(annotation.frame) (tool=\(model.currentTool))")
                let command = AddAnnotationCommand(annotation: annotation, canvas: model)
                model.history.execute(command)
                print("🧪 mouseUp: now \(model.annotations.count) annotations")
            } else {
                print("🧪 mouseUp: createAnnotation returned nil (tool=\(model.currentTool))")
            }
            
            needsDisplay = true
        }
    }
    
    /// Run OCR over `region` and add a highlighter mark over the detected text
    /// the drag crosses — like selecting text with a cursor.
    private func highlightDetectedText(in region: CGRect) {
        guard let model = model else { return }
        let image = model.image
        let color = model.currentColor
        
        // A thin horizontal drag (text-selection gesture) has near-zero height;
        // expand it a little vertically so it reliably catches the line.
        var search = region
        if search.height < 12 {
            let cy = search.midY
            search = CGRect(x: search.minX, y: cy - 8, width: max(search.width, 1), height: 16)
        }
        // Require a meaningful horizontal drag.
        guard search.width > 6 else { return }
        
        Task { @MainActor in
            guard let boxes = try? await OCRManager.shared.detectTextBoxes(in: image, within: search),
                  !boxes.isEmpty else {
                return
            }
            for box in boxes {
                let padded = box.insetBy(dx: -1, dy: -2)
                let highlight = ShapeAnnotation(type: .textHighlight, frame: padded, color: color)
                let command = AddAnnotationCommand(annotation: highlight, canvas: model)
                model.history.execute(command)
            }
            self.needsDisplay = true
        }
    }
    
    // MARK: - Text Input
    
    private func showTextInput(at imagePoint: CGPoint) {
        textField?.removeFromSuperview()
        
        // Place the field at the matching VIEW coordinate (image coords are
        // offset + scaled relative to the view).
        let viewPoint = convertToViewCoordinates(imagePoint)
        
        let fontSize = model?.textSize ?? 16
        let fieldHeight = max(24, fontSize + 8)
        let textField = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 240, height: fieldHeight))
        textField.placeholderString = "Enter text..."
        textField.font = .systemFont(ofSize: fontSize)
        textField.textColor = NSColor(model?.currentColor ?? .black)
        textField.bezelStyle = .roundedBezel
        textField.delegate = self
        textField.target = self
        textField.action = #selector(textFieldEntered(_:))
        
        addSubview(textField)
        self.textField = textField
        window?.makeFirstResponder(textField)
    }
    
    @objc private func textFieldEntered(_ sender: NSTextField) {
        let text = sender.stringValue
        guard let model = model, !text.isEmpty else {
            textField?.removeFromSuperview()
            textField = nil
            return
        }
        
        // Convert the field's view-space origin back to image coordinates so
        // the annotation lands where the field was shown.
        let imageOrigin = convertToImageCoordinates(sender.frame.origin)
        
        let annotation = TextAnnotation(text: text, at: imageOrigin, color: model.currentColor,
                                        font: .systemFont(ofSize: model.textSize))
        let command = AddAnnotationCommand(annotation: annotation, canvas: model)
        model.history.execute(command)
        
        textField?.removeFromSuperview()
        textField = nil
        needsDisplay = true
    }
    
    // MARK: - Coordinate Conversion
    
    private func convertToImageCoordinates(_ viewPoint: CGPoint) -> CGPoint {
        guard let model = model else { return viewPoint }
        
        let imageSize = model.image.size
        let viewSize = bounds.size
        
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2
        
        let imageX = (viewPoint.x - offsetX) / scale
        let imageY = (viewPoint.y - offsetY) / scale
        
        return CGPoint(x: imageX, y: imageY)
    }
    
    /// Inverse of `convertToImageCoordinates`: image space → view space.
    private func convertToViewCoordinates(_ imagePoint: CGPoint) -> CGPoint {
        guard let model = model else { return imagePoint }
        
        let imageSize = model.image.size
        let viewSize = bounds.size
        
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2
        
        return CGPoint(x: imagePoint.x * scale + offsetX, y: imagePoint.y * scale + offsetY)
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
}

// MARK: - NSTextFieldDelegate

extension AnnotationCanvasNSView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        textFieldEntered(textField)
    }
}

// MARK: - Placeholder Types

struct CropAnnotation: AnnotationProtocol {
    let id: UUID = UUID()
    let type: AnnotationType = .crop
    var frame: CGRect
    var color: Color = .clear
    var opacity: Double = 1.0
    
    func draw(in context: CGContext, on image: NSImage) {}
    func contains(_ point: CGPoint) -> Bool { frame.contains(point) }
}
