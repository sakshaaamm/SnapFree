//
//  OCRManager.swift
//  SnapFree
//
//  Text recognition (OCR) on a captured image using the Vision framework.
//

import Vision
import AppKit

@MainActor
final class OCRManager {
    
    static let shared = OCRManager()
    
    private init() {}
    
    enum OCRError: LocalizedError {
        case invalidImage
        case noText
        
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Could not read the image for text recognition."
            case .noText: return "No readable text was found in the selection."
            }
        }
    }
    
    /// Recognize text in the given image. Returns the joined recognized lines.
    func recognizeText(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noText)
                    return
                }
                
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                
                if text.isEmpty {
                    continuation.resume(throwing: OCRError.noText)
                } else {
                    continuation.resume(returning: text)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Detect text line bounding boxes in `image`. Returns rectangles in image
    /// POINTS with a BOTTOM-LEFT origin (matching the annotation canvas space),
    /// optionally restricted to text whose center lies inside `regionPoints`.
    func detectTextBoxes(in image: NSImage, within regionPoints: CGRect? = nil) async throws -> [CGRect] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        
        let pointSize = image.size
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Vision boxes are normalized [0,1] with a BOTTOM-LEFT origin,
                // which already matches the canvas. Scale to image points.
                var boxes: [CGRect] = []
                for obs in observations {
                    let bb = obs.boundingBox
                    let rect = CGRect(
                        x: bb.origin.x * pointSize.width,
                        y: bb.origin.y * pointSize.height,
                        width: bb.width * pointSize.width,
                        height: bb.height * pointSize.height
                    )
                    if let region = regionPoints {
                        // Keep any text line that the selection overlaps.
                        if !region.intersects(rect) { continue }
                        // Clip the highlight to the horizontal span of the
                        // selection so a partial drag highlights only the part
                        // of the line the user dragged across (text-selection
                        // feel), while keeping the full line height.
                        let clippedX = max(rect.minX, region.minX)
                        let clippedMaxX = min(rect.maxX, region.maxX)
                        if clippedMaxX > clippedX {
                            boxes.append(CGRect(x: clippedX, y: rect.minY,
                                                width: clippedMaxX - clippedX,
                                                height: rect.height))
                        }
                        continue
                    }
                    boxes.append(rect)
                }
                continuation.resume(returning: boxes)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Copy recognized text to the clipboard as plain text.
    func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
