//
//  AnnotationCanvasModel.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Canvas Data Model
//

import SwiftUI
import CoreImage

/// The data model for the annotation canvas
class AnnotationCanvasModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var image: NSImage
    @Published var annotations: [any AnnotationProtocol] = []
    @Published var selectedAnnotation: (any AnnotationProtocol)?
    @Published var currentTool: AnnotationTool = .arrow
    @Published var currentColor: Color = .red
    @Published var lineWidth: CGFloat = 3
    @Published var textSize: CGFloat = 16
    @Published var blurRadius: CGFloat = 10
    @Published var pixelSize: CGFloat = 10
    
    // MARK: - History
    
    let history = EditHistory()
    
    // MARK: - Initialization
    
    init(image: NSImage) {
        self.image = image
    }
    
    // MARK: - Annotation Management
    
    func addAnnotation(_ annotation: any AnnotationProtocol) {
        annotations.append(annotation)
    }
    
    func removeAnnotation(_ annotation: any AnnotationProtocol) {
        annotations.removeAll { $0.id == annotation.id }
    }
    
    func insertAnnotation(_ annotation: any AnnotationProtocol, at index: Int) {
        if index >= 0 && index <= annotations.count {
            annotations.insert(annotation, at: index)
        }
    }
    
    /// Move an annotation (identified by id) to a new frame. Handles the
    /// special case of arrows, whose start/end points define their geometry.
    func moveAnnotation(id: UUID, to newFrame: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var annotation = annotations[index]
        
        let dx = newFrame.origin.x - annotation.frame.origin.x
        let dy = newFrame.origin.y - annotation.frame.origin.y
        
        if var arrow = annotation as? ArrowAnnotation {
            arrow.startPoint = CGPoint(x: arrow.startPoint.x + dx, y: arrow.startPoint.y + dy)
            arrow.endPoint = CGPoint(x: arrow.endPoint.x + dx, y: arrow.endPoint.y + dy)
            arrow.frame = newFrame
            annotations[index] = arrow
            selectedAnnotation = arrow
        } else if var line = annotation as? ShapeAnnotation, line.type == .line {
            if let s = line.startPoint { line.startPoint = CGPoint(x: s.x + dx, y: s.y + dy) }
            if let e = line.endPoint { line.endPoint = CGPoint(x: e.x + dx, y: e.y + dy) }
            line.frame = newFrame
            annotations[index] = line
            selectedAnnotation = line
        } else if var pen = annotation as? PenAnnotation {
            pen.points = pen.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            pen.frame = newFrame
            annotations[index] = pen
            selectedAnnotation = pen
        } else {
            annotation.frame = newFrame
            annotations[index] = annotation
            selectedAnnotation = annotation
        }
    }
    
    func selectAnnotation(at point: CGPoint) {
        // Find annotation containing point (in reverse order to get topmost)
        for annotation in annotations.reversed() {
            if annotation.contains(point) {
                selectedAnnotation = annotation
                return
            }
        }
        selectedAnnotation = nil
    }
    
    // MARK: - Drawing
    
    func createAnnotation(from startPoint: CGPoint, to endPoint: CGPoint) -> (any AnnotationProtocol)? {
        let frame = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        switch currentTool {
        case .arrow:
            var arrow = ArrowAnnotation(start: startPoint, end: endPoint, color: currentColor)
            arrow.lineWidth = lineWidth
            return arrow
            
        case .rectangle:
            var shape = ShapeAnnotation(type: .rectangle, frame: frame, color: currentColor)
            shape.lineWidth = lineWidth
            return shape
            
        case .circle:
            var shape = ShapeAnnotation(type: .circle, frame: frame, color: currentColor)
            shape.lineWidth = lineWidth
            return shape
            
        case .line:
            var shape = ShapeAnnotation(type: .line, frame: frame, color: currentColor,
                                        startPoint: startPoint, endPoint: endPoint)
            shape.lineWidth = lineWidth
            return shape
            
        case .highlight:
            return ShapeAnnotation(type: .highlight, frame: frame, color: currentColor)
            
        case .blur:
            return BlurAnnotation(frame: frame, blurRadius: blurRadius)
            
        case .pixelate:
            return PixelateAnnotation(frame: frame, pixelSize: pixelSize)
            
        case .select, .textHighlight, .text, .counter, .pen, .crop:
            // Handled separately (select/move, OCR highlight, click-to-place,
            // freehand, or crop).
            return nil
        }
    }
    
    // Running counter for numbered badges.
    private(set) var nextCounterValue: Int = 1
    
    func makeCounter(at center: CGPoint) -> CounterAnnotation {
        // Scale the badge with the line-width control (so it's adjustable).
        let diameter = max(20, lineWidth * 6)
        let annotation = CounterAnnotation(number: nextCounterValue, center: center,
                                           color: currentColor, diameter: diameter)
        nextCounterValue += 1
        return annotation
    }
    
    func makePen(points: [CGPoint]) -> PenAnnotation {
        PenAnnotation(points: points, color: currentColor, lineWidth: lineWidth)
    }
    
    // MARK: - Image Operations
    
    func crop(to rect: CGRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        
        // The crop rect is in image points with a BOTTOM-LEFT origin (canvas
        // space). CGImage.cropping expects pixels with a TOP-LEFT origin, so we
        // flip Y in addition to applying the backing scale.
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: CGFloat(cgImage.height) - (rect.origin.y + rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        
        guard let croppedCG = cgImage.cropping(to: pixelRect) else {
            return image
        }
        
        return NSImage(cgImage: croppedCG, size: NSSize(width: rect.width, height: rect.height))
    }
    
    // MARK: - Export
    
    func renderFinalImage() -> NSImage {
        guard let baseCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("🧪 renderFinalImage: NO baseCG")
            return image
        }
        
        let pixelW = baseCG.width
        let pixelH = baseCG.height
        let pointSize = image.size
        
        let blurCount = annotations.filter { $0 is BlurAnnotation }.count
        let pixCount = annotations.filter { $0 is PixelateAnnotation }.count
        print("🧪 renderFinalImage: \(annotations.count) annotations (blur=\(blurCount), pix=\(pixCount)), base pixels=\(pixelW)x\(pixelH), points=\(pointSize)")
        // Scale from image points (what annotations are stored in) to pixels.
        let sx = CGFloat(pixelW) / pointSize.width
        let sy = CGFloat(pixelH) / pointSize.height
        
        // One bitmap context at full pixel resolution, bottom-left origin —
        // the SAME orientation the on-screen canvas uses. Everything is drawn
        // here so there are no cross-space flip mismatches.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        // 1) Draw the base image filling the whole context.
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        
        // 2) Burn in redaction regions (blur / pixelate) directly in pixel space.
        for annotation in annotations {
            if let blur = annotation as? BlurAnnotation {
                drawRedaction(.blur(radius: blur.blurRadius), region: blur.frame,
                              baseCG: baseCG, sx: sx, sy: sy, into: ctx)
            } else if let pix = annotation as? PixelateAnnotation {
                drawRedaction(.pixelate(scale: pix.pixelSize), region: pix.frame,
                              baseCG: baseCG, sx: sx, sy: sy, into: ctx)
            }
        }
        
        // 3) Draw the vector annotations. They store coordinates in image
        //    POINTS, so scale the context up to pixels first.
        ctx.saveGState()
        ctx.scaleBy(x: sx, y: sy)
        for annotation in annotations {
            if annotation is BlurAnnotation || annotation is PixelateAnnotation { continue }
            annotation.draw(in: ctx, on: image)
        }
        ctx.restoreGState()
        
        guard let outCG = ctx.makeImage() else { return image }
        return NSImage(cgImage: outCG, size: pointSize)
    }
    
    // MARK: - Redaction Effects
    
    enum RedactionEffect {
        case blur(radius: CGFloat)
        case pixelate(scale: CGFloat)
    }
    
    /// Produce a blurred/pixelated CGImage for `region` (given in image POINTS,
    /// bottom-left origin). Used by BOTH the live editor preview and export, so
    /// what you see is what you get. The returned patch is sized to the region
    /// in points and can be drawn directly into a point-space context.
    func effectPatch(_ effect: RedactionEffect, region: CGRect) -> CGImage? {
        guard let baseCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let pointSize = image.size
        let sx = CGFloat(baseCG.width) / pointSize.width
        let sy = CGFloat(baseCG.height) / pointSize.height
        
        // Region (points, bottom-left) → pixels (bottom-left).
        let pixelRegion = CGRect(
            x: region.origin.x * sx,
            y: region.origin.y * sy,
            width: region.width * sx,
            height: region.height * sy
        ).integral
        
        guard pixelRegion.width > 1, pixelRegion.height > 1 else { return nil }
        
        // Crop the base to just the region (+margin so blur has pixels to bleed).
        let margin: CGFloat
        switch effect {
        case .blur(let radius): margin = max(radius * sx * 3, 20)
        case .pixelate: margin = 20
        }
        
        let sourceRect = pixelRegion.insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: baseCG.width, height: baseCG.height))
            .integral
        
        guard sourceRect.width > 1, sourceRect.height > 1,
              let croppedBase = baseCG.cropping(to: sourceRect) else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: croppedBase)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        
        let filtered: CIImage
        switch effect {
        case .blur(let radius):
            guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
            f.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            f.setValue(max(radius * sx, 8), forKey: kCIInputRadiusKey)
            guard let output = f.outputImage else { return nil }
            filtered = output.cropped(to: ciImage.extent)
            
        case .pixelate(let scale):
            guard let f = CIFilter(name: "CIPixellate") else { return nil }
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(max(scale * sx, 8), forKey: kCIInputScaleKey)
            let center = CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY)
            f.setValue(center, forKey: kCIInputCenterKey)
            guard let output = f.outputImage else { return nil }
            filtered = output.cropped(to: ciImage.extent)
        }
        
        // Extract just the region portion (offset within the cropped source).
        let destRect = CGRect(
            x: pixelRegion.origin.x - sourceRect.origin.x,
            y: pixelRegion.origin.y - sourceRect.origin.y,
            width: pixelRegion.width,
            height: pixelRegion.height
        ).integral
        
        return ciContext.createCGImage(filtered, from: destRect)
    }
    
    /// Paint a redaction region into `ctx` at the matching pixel rectangle.
    private func drawRedaction(_ effect: RedactionEffect, region: CGRect,
                               baseCG: CGImage, sx: CGFloat, sy: CGFloat, into ctx: CGContext) {
        let pixelRegion = CGRect(
            x: region.origin.x * sx,
            y: region.origin.y * sy,
            width: region.width * sx,
            height: region.height * sy
        ).integral
        
        guard let patch = effectPatch(effect, region: region) else {
            print("🧪 drawRedaction: no patch for region=\(region)")
            return
        }
        
        ctx.saveGState()
        ctx.draw(patch, in: pixelRegion)
        ctx.restoreGState()
        print("🧪 drawRedaction: patch drawn (\(patch.width)x\(patch.height)) at \(pixelRegion)")
    }
}

// MARK: - Annotation Tool

enum AnnotationTool: String, CaseIterable {
    case select
    case arrow
    case rectangle
    case circle
    case line
    case highlight
    case textHighlight
    case pen
    case text
    case counter
    case blur
    case pixelate
    case crop
    
    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .highlight: return "highlighter"
        case .textHighlight: return "text.redaction"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .counter: return "1.circle.fill"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }
    
    var displayName: String {
        switch self {
        case .select: return "Select / Move"
        case .pen: return "Draw"
        case .counter: return "Number"
        case .highlight: return "Spotlight"
        case .textHighlight: return "Highlight Text"
        default: return rawValue.capitalized
        }
    }
    
    // Tools that are placed with a single click instead of a drag.
    var isClickToPlace: Bool {
        self == .text || self == .counter
    }
    
    var needsDrag: Bool {
        !isClickToPlace && self != .crop && self != .select
    }
}
