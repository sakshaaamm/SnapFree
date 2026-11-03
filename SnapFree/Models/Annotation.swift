//
//  Annotation.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Annotation Models
//

import Foundation
import SwiftUI

// MARK: - Annotation Protocol

protocol AnnotationProtocol: Identifiable {
    var id: UUID { get }
    var type: AnnotationType { get }
    var frame: CGRect { get set }
    var color: Color { get set }
    var opacity: Double { get set }
    
    func draw(in context: CGContext, on image: NSImage)
    func contains(_ point: CGPoint) -> Bool
}

// MARK: - Annotation Types

enum AnnotationType: String, CaseIterable, Codable {
    case arrow
    case rectangle
    case circle
    case line
    case text
    case blur
    case pixelate
    case highlight
    case textHighlight
    case pen
    case counter
    case crop
    
    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .highlight: return "highlighter"
        case .textHighlight: return "text.redaction"
        case .pen: return "pencil.tip"
        case .counter: return "1.circle.fill"
        case .crop: return "crop"
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Arrow Annotation

struct ArrowAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .arrow
    var frame: CGRect
    var color: Color
    var opacity: Double = 1.0
    
    var startPoint: CGPoint
    var endPoint: CGPoint
    var lineWidth: CGFloat = 3
    var arrowHeadSize: CGFloat = 12
    
    init(start: CGPoint, end: CGPoint, color: Color = .red) {
        self.id = UUID()
        self.startPoint = start
        self.endPoint = end
        self.color = color
        
        // Calculate frame
        let minX = min(start.x, end.x) - arrowHeadSize
        let maxX = max(start.x, end.x) + arrowHeadSize
        let minY = min(start.y, end.y) - arrowHeadSize
        let maxY = max(start.y, end.y) + arrowHeadSize
        self.frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        context.saveGState()
        
        let nsColor = NSColor(color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setAlpha(opacity)
        
        // Draw line
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        
        // Draw arrowhead
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowPoint1 = CGPoint(
            x: endPoint.x - arrowHeadSize * cos(angle - .pi / 6),
            y: endPoint.y - arrowHeadSize * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: endPoint.x - arrowHeadSize * cos(angle + .pi / 6),
            y: endPoint.y - arrowHeadSize * sin(angle + .pi / 6)
        )
        
        context.setFillColor(nsColor.cgColor)
        context.move(to: endPoint)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
        
        context.restoreGState()
    }
    
    func contains(_ point: CGPoint) -> Bool {
        // Check if point is near the line
        let distance = pointToLineDistance(point: point, lineStart: startPoint, lineEnd: endPoint)
        return distance < lineWidth + 5
    }
    
    private func pointToLineDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared == 0 { return hypot(point.x - lineStart.x, point.y - lineStart.y) }
        
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
        let projectionX = lineStart.x + t * dx
        let projectionY = lineStart.y + t * dy
        
        return hypot(point.x - projectionX, point.y - projectionY)
    }
}

// MARK: - Shape Annotation

struct ShapeAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType
    var frame: CGRect
    var color: Color
    var opacity: Double = 1.0
    
    var lineWidth: CGFloat = 3
    var fillColor: Color?
    var cornerRadius: CGFloat = 0
    
    // For .line, preserve the true drag direction (frame corners alone can't
    // distinguish an "uphill" from a "downhill" diagonal).
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    
    init(type: AnnotationType, frame: CGRect, color: Color = .red, fillColor: Color? = nil,
         startPoint: CGPoint? = nil, endPoint: CGPoint? = nil) {
        precondition(type == .rectangle || type == .circle || type == .line || type == .highlight || type == .textHighlight)
        self.id = UUID()
        self.type = type
        self.frame = frame
        self.color = color
        self.fillColor = fillColor
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        context.saveGState()
        
        let nsColor = NSColor(color)
        context.setStrokeColor(nsColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setAlpha(opacity)
        
        if let fillColor = fillColor {
            context.setFillColor(NSColor(fillColor).cgColor)
        }
        
        switch type {
        case .rectangle:
            if fillColor != nil {
                context.fill(frame)
            }
            context.stroke(frame)
            
        case .highlight:
            // Spotlight: keep the selected area at full brightness and dim
            // everything OUTSIDE it, drawing attention to the selection.
            let bounds = CGRect(origin: .zero, size: image.size)
            context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            // Fill the whole image, then punch a clear hole over the selection.
            context.saveGState()
            let outside = CGMutablePath()
            outside.addRect(bounds)
            outside.addRect(frame)
            context.addPath(outside)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
            
        case .textHighlight:
            // Highlighter marker over a line of text: multiply blend keeps the
            // text readable underneath, like a real highlighter pen.
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setFillColor(NSColor(color).withAlphaComponent(0.5).cgColor)
            context.fill(frame)
            context.restoreGState()
            
        case .circle:
            if fillColor != nil {
                context.fillEllipse(in: frame)
            }
            context.strokeEllipse(in: frame)
            
        case .line:
            let p0 = startPoint ?? CGPoint(x: frame.minX, y: frame.minY)
            let p1 = endPoint ?? CGPoint(x: frame.maxX, y: frame.maxY)
            context.move(to: p0)
            context.addLine(to: p1)
            context.strokePath()
            
        default:
            break
        }
        
        context.restoreGState()
    }
    
    func contains(_ point: CGPoint) -> Bool {
        frame.insetBy(dx: -lineWidth, dy: -lineWidth).contains(point)
    }
}

// MARK: - Text Annotation

struct TextAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .text
    var frame: CGRect
    var color: Color
    var opacity: Double = 1.0
    
    var text: String
    var font: NSFont
    var alignment: NSTextAlignment
    
    init(text: String, at point: CGPoint, color: Color = .black, font: NSFont = .systemFont(ofSize: 16)) {
        self.id = UUID()
        self.text = text
        self.color = color
        self.font = font
        self.alignment = .left
        
        // Calculate frame based on text size
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = text.size(withAttributes: attributes)
        self.frame = CGRect(origin: point, size: CGSize(width: size.width + 8, height: size.height + 4))
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        context.saveGState()
        
        let nsColor = NSColor(color)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: frame.origin.x + 4, y: frame.origin.y + 2, width: frame.width - 8, height: frame.height - 4)
        
        // Create text drawing context
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        attributedString.draw(in: textRect)
        
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
    
    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

// MARK: - Blur Annotation

struct BlurAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .blur
    var frame: CGRect
    var color: Color = .clear
    var opacity: Double = 1.0
    
    var blurRadius: CGFloat = 10
    
    init(frame: CGRect, blurRadius: CGFloat = 10) {
        self.id = UUID()
        self.frame = frame
        self.blurRadius = blurRadius
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        // Blur is applied separately during export
        // This is just a placeholder for the region
    }
    
    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
    
    func applyBlur(to image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return image
        }
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(blurRadius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = blurFilter?.outputImage else {
            return image
        }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return image
        }
        
        return NSImage(cgImage: cgImage, size: image.size)
    }
}

// MARK: - Pixelate Annotation

struct PixelateAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .pixelate
    var frame: CGRect
    var color: Color = .clear
    var opacity: Double = 1.0
    
    var pixelSize: CGFloat = 10
    
    init(frame: CGRect, pixelSize: CGFloat = 10) {
        self.id = UUID()
        self.frame = frame
        self.pixelSize = pixelSize
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        // Pixelation is applied separately during export
    }
    
    func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

// MARK: - Pen (Freehand) Annotation

struct PenAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .pen
    var frame: CGRect
    var color: Color
    var opacity: Double = 1.0
    
    var points: [CGPoint]
    var lineWidth: CGFloat
    
    init(points: [CGPoint], color: Color = .red, lineWidth: CGFloat = 3) {
        self.id = UUID()
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.frame = PenAnnotation.boundingBox(of: points, padding: lineWidth)
    }
    
    static func boundingBox(of points: [CGPoint], padding: CGFloat) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX - padding, y: minY - padding,
                      width: (maxX - minX) + padding * 2,
                      height: (maxY - minY) + padding * 2)
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        guard points.count > 1 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor(color).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setAlpha(opacity)
        
        context.move(to: points[0])
        for p in points.dropFirst() {
            context.addLine(to: p)
        }
        context.strokePath()
        context.restoreGState()
    }
    
    func contains(_ point: CGPoint) -> Bool {
        // Hit-test against any segment of the stroke.
        guard points.count > 1 else { return frame.contains(point) }
        for i in 0..<(points.count - 1) {
            if distance(from: point, toSegment: points[i], points[i + 1]) < lineWidth + 6 {
                return true
            }
        }
        return false
    }
    
    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

// MARK: - Counter (Numbered Badge) Annotation

struct CounterAnnotation: AnnotationProtocol {
    let id: UUID
    let type: AnnotationType = .counter
    var frame: CGRect
    var color: Color
    var opacity: Double = 1.0
    
    var number: Int
    var diameter: CGFloat
    
    init(number: Int, center: CGPoint, color: Color = .red, diameter: CGFloat = 32) {
        self.id = UUID()
        self.number = number
        self.color = color
        self.diameter = diameter
        self.frame = CGRect(x: center.x - diameter / 2,
                            y: center.y - diameter / 2,
                            width: diameter,
                            height: diameter)
    }
    
    func draw(in context: CGContext, on image: NSImage) {
        context.saveGState()
        context.setAlpha(opacity)
        
        // Filled circle
        context.setFillColor(NSColor(color).cgColor)
        context.fillEllipse(in: frame)
        
        // White ring
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: frame.insetBy(dx: 1, dy: 1))
        
        // Number text, centered
        let text = "\(number)"
        let fontSize = diameter * 0.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textOrigin = CGPoint(x: frame.midX - textSize.width / 2,
                                 y: frame.midY - textSize.height / 2)
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: textOrigin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        
        context.restoreGState()
    }
    
    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        return hypot(dx, dy) <= diameter / 2
    }
}
