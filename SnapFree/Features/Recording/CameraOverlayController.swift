//
//  CameraOverlayController.swift
//  SnapFree
//
//  A small floating webcam preview shown during screen recording. Because the
//  screen recorder (SCStream) captures the whole display, this overlay window
//  is included in the recording — giving a picture-in-picture face cam.
//

import AppKit
import AVFoundation

@MainActor
final class CameraOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.snapfree.camera.session")
    
    /// Show the webcam preview in a floating rounded window.
    /// Camera permission is requested up front by PermissionManager before
    /// recording starts, so by the time this runs access is already authorized.
    func show() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            print("⚠️ Camera access not authorized — enable it in System Settings → Privacy → Camera")
            return
        }
        startSession()
    }
    
    private func startSession() {
        guard panel == nil else { return }
        
        let settings = SettingsStore.shared
        let base = CGFloat(settings.recordCameraSize)
        let shape = settings.recordCameraShape
        let size = shape.size(base: base)
        let cornerRadius: CGFloat = {
            switch shape {
            case .circle: return min(size.width, size.height) / 2
            case .square: return 16
            case .rectangle: return 14
            }
        }()
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.cgColor
        container.layer?.borderWidth = 3
        panel.contentView = container
        
        // Position bottom-right of the main screen.
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - size.width - 30,
                y: screen.visibleFrame.minY + 30
            ))
        }
        
        // Configure the capture session.
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("⚠️ No camera device available")
            return
        }
        session.addInput(input)
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = container.bounds
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = cornerRadius
        preview.masksToBounds = true
        container.layer?.addSublayer(preview)
        
        self.panel = panel
        self.session = session
        self.previewLayer = preview
        
        panel.orderFront(nil)
        
        sessionQueue.async {
            session.startRunning()
        }
    }
    
    /// Hide the preview and stop the camera.
    func hide() {
        let session = self.session
        sessionQueue.async {
            session?.stopRunning()
        }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        previewLayer = nil
        self.session = nil
    }
}
