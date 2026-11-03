//
//  CaptureManager.swift
//  SnapFree
//
//  Phase 1: Foundation - Capture Coordinator
//

import SwiftUI
import ScreenCaptureKit
import CoreImage

@MainActor
class CaptureManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CaptureManager()
    
    // MARK: - Published State
    
    @Published var isCapturing = false
    @Published var lastCapture: CaptureItem?
    @Published var captureError: String?
    
    // MARK: - Dependencies
    
    private let displayManager = DisplayManager.shared
    private let storageManager = StorageManager.shared
    private let clipboardManager = ClipboardManager.shared
    
    private init() {}
    
    // MARK: - Capture Methods
    
    /// Capture full screen
    func captureFullScreen() {
        Task {
            await performCapture(.fullScreen)
        }
    }
    
    /// Capture a selected area
    func captureArea() {
        Task {
            await performCapture(.area)
        }
    }
    
    /// Capture a selected window
    func captureWindow() {
        Task {
            await performCapture(.window)
        }
    }
    
    /// Capture a selected area and extract its text via OCR (copied to clipboard).
    func captureTextArea() {
        Task {
            await performTextCapture()
        }
    }
    
    // MARK: - OCR Capture
    
    private func performTextCapture() async {
        isCapturing = true
        captureError = nil
        
        do {
            try await displayManager.refreshContent()
            let image = try await captureAreaImage()
            
            let text = try await OCRManager.shared.recognizeText(in: image)
            OCRManager.shared.copyTextToClipboard(text)
            
            if SettingsStore.shared.playSound {
                playCaptureSound()
            }
            print("🔤 OCR captured \(text.count) characters — copied to clipboard")
        } catch CaptureError.cancelled {
            // User cancelled the selection; nothing to do.
        } catch {
            captureError = error.localizedDescription
            print("❌ OCR capture failed: \(error)")
            presentOCRError(error)
        }
        
        isCapturing = false
    }
    
    private func presentOCRError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Text Capture"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Private Implementation
    
    private func performCapture(_ type: CaptureType) async {
        isCapturing = true
        captureError = nil
        
        do {
            // Refresh display content
            try await displayManager.refreshContent()
            
            let image: NSImage
            
            switch type {
            case .fullScreen:
                image = try await captureFullScreenImage()
                
            case .area:
                // Show area selection overlay
                image = try await captureAreaImage()
                
            case .window:
                // Show window selection overlay
                image = try await captureWindowImage()
            }
            
            // Create capture item
            let capture = CaptureItem(type: type, image: image)
            self.lastCapture = capture
            
            // Play capture sound (if enabled)
            if SettingsStore.shared.playSound {
                playCaptureSound()
            }
            
            // Copy / save / history / preview handling
            handleCaptureResult(capture)
            
        } catch {
            captureError = error.localizedDescription
            print("❌ Capture failed: \(error)")
        }
        
        isCapturing = false
    }
    
    // MARK: - Capture Implementations
    
    private func captureFullScreenImage() async throws -> NSImage {
        guard let display = displayManager.displayAtMouseLocation() ?? displayManager.mainDisplay else {
            throw CaptureError.noDisplay
        }
        
        return try await captureDisplay(display)
    }
    
    private func captureAreaImage() async throws -> NSImage {
        // Show area selection overlay. The returned rect is in screen-local
        // points with a top-left origin, for the display where the selection
        // was made.
        let rect = try await SelectionOverlayManager.shared.requestAreaSelection()
        
        // Capture the display where the user is currently working. For the
        // common single-display case this is always the main display.
        try await displayManager.refreshContent()
        
        guard let display = displayManager.displayAtMouseLocation() ?? displayManager.mainDisplay else {
            throw CaptureError.noDisplay
        }
        
        // Capture full display
        let fullImage = try await captureDisplay(display)
        
        // Crop to selected area
        return cropImage(fullImage, to: rect)
    }
    
    private func captureWindowImage() async throws -> NSImage {
        // Show window selection overlay
        guard let window = try await SelectionOverlayManager.shared.requestWindowSelection() else {
            throw CaptureError.noWindow
        }
        
        let image = try await captureWindow(window)
        let capture = CaptureItem(type: .window, image: image, sourceAppName: window.owningApplication?.applicationName)
        self.lastCapture = capture
        return image
    }
    
    // MARK: - ScreenCaptureKit Wrappers
    
    private func captureDisplay(_ display: SCDisplay) async throws -> NSImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // display.width/height are in POINTS. To get a sharp (non-blurry)
        // screenshot on Retina displays we must capture at native PIXEL
        // resolution, i.e. multiplied by the backing scale factor.
        let scale = backingScale(for: display)
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }
        
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        
        // Report the NSImage size in POINTS so downstream cropping math stays
        // correct, while the backing CGImage keeps full pixel detail.
        return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
    }
    
    private func captureWindow(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        // Capture at native pixel resolution for a sharp image.
        let scale = backingScaleForMainDisplay()
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }
        
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        
        return NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
    }
    
    /// Backing scale factor (1 for standard, 2 for Retina) for a given SCDisplay.
    private func backingScale(for display: SCDisplay) -> CGFloat {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }
    
    private func backingScaleForMainDisplay() -> CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }
    
    // MARK: - Helpers
    
    private func convertCGImageToNSImage(_ cgImage: CGImage) -> NSImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        return image
    }
    
    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        
        // `rect` arrives in screen-local points with a TOP-LEFT origin (already
        // flipped by the overlay view). The CGImage is in pixels with a
        // top-left origin too, so we only need to apply the backing scale.
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        
        guard let croppedCG = cgImage.cropping(to: pixelRect) else {
            return image
        }
        
        return NSImage(cgImage: croppedCG, size: NSSize(width: rect.width, height: rect.height))
    }
    
    private func playCaptureSound() {
        NSSound(named: "Grab")?.play()
    }
    
    // MARK: - Result Handling
    
    private func handleCaptureResult(_ capture: CaptureItem) {
        let settings = SettingsStore.shared
        
        // Always keep a persistent history record.
        HistoryManager.shared.add(capture)
        
        // Copy to clipboard if enabled (default on).
        if settings.copyToClipboard {
            clipboardManager.copyImage(capture.image)
        }
        
        // Optionally auto-save to the configured location.
        if settings.autoSave {
            try? StorageManager.shared.saveImage(
                capture.image,
                format: settings.imageFormat
            )
        }
        
        showCaptureNotification(capture)
    }
    
    private func showCaptureNotification(_ capture: CaptureItem) {
        print("📸 \(capture.type.rawValue) screenshot captured")
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplay
    case noWindow
    case cancelled
    case captureFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .noWindow: return "No window selected"
        case .cancelled: return "Capture cancelled"
        case .captureFailed(let error): return "Capture failed: \(error.localizedDescription)"
        }
    }
}
