//
//  RecordingManager.swift
//  SnapFree
//
//  Screen recording via ScreenCaptureKit (SCStream) + AVAssetWriter.
//  Records the main display to an .mov file in the SnapFree folder.
//

import AVFoundation
import ScreenCaptureKit
import AppKit

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    
    static let shared = RecordingManager()
    
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?
    
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?      // system audio (SCStream)
    private var micInput: AVAssetWriterInput?        // microphone (AVCaptureSession)
    private var outputURL: URL?
    private var sessionStarted = false
    private let cameraOverlay = CameraOverlayController()
    private let micRecorder = MicrophoneRecorder()
    
    // Dedicated queue for sample-buffer delivery.
    private let sampleQueue = DispatchQueue(label: "com.snapfree.recording.samples")
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public control
    
    func toggle() async {
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }
    
    func start() async {
        guard !isRecording else { return }
        
        let settings = SettingsStore.shared
        
        // Request ALL required permissions up front and wait for the user's
        // response before doing anything. If screen recording, or an enabled
        // camera / microphone, is denied, abort cleanly (the user was shown an
        // alert with a shortcut to System Settings).
        let permissionsOK = await PermissionManager.shared.ensureRecordingPermissions(
            wantsCamera: settings.recordCamera,
            wantsMicrophone: settings.recordMicrophone
        )
        guard permissionsOK else {
            print("⚠️ Recording aborted: required permissions not granted")
            return
        }
        
        // Show the face-cam overlay first so it's on screen (and recorded).
        // Permission is already granted at this point, so the preview starts
        // immediately and has time to warm up.
        if settings.recordCamera {
            cameraOverlay.show()
            // Give the camera a moment to warm up before capture starts.
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        
        // Optional countdown before recording begins.
        if settings.recordShowCountdown {
            await runCountdown(from: settings.recordCountdownSeconds)
        }
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first else {
                print("❌ Recording: no display found")
                return
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            let config = SCStreamConfiguration()
            // Native (retina) pixel size, then optionally scale down to the
            // chosen max resolution while preserving aspect ratio.
            let nativeW = display.width * 2
            let nativeH = display.height * 2
            if let maxH = settings.recordMaxResolution.maxHeight, nativeH > maxH {
                let ratio = Double(maxH) / Double(nativeH)
                config.height = maxH
                config.width = Int((Double(nativeW) * ratio).rounded())
            } else {
                config.width = nativeW
                config.height = nativeH
            }
            let fps = max(1, settings.recordFPS)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 6
            config.showsCursor = settings.recordShowCursor
            
            // System audio capture (macOS 13+).
            let wantsSystemAudio = settings.recordSystemAudio
            if #available(macOS 13.0, *), wantsSystemAudio {
                config.capturesAudio = true
            }
            
            let wantsMic = settings.recordMicrophone
            
            try setupWriter(width: config.width, height: config.height,
                            withSystemAudio: wantsSystemAudio, withMic: wantsMic)
            
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if #available(macOS 13.0, *), wantsSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            try await stream.startCapture()
            
            // Start the microphone (separate AVCaptureSession) and feed its
            // samples into the mic audio track.
            if wantsMic {
                micRecorder.onSample = { [weak self] buffer in
                    Task { @MainActor in self?.appendMic(buffer) }
                }
                _ = micRecorder.start()
            }
            
            self.stream = stream
            self.isRecording = true
            print("🔴 Recording started → \(outputURL?.lastPathComponent ?? "?")")
        } catch {
            print("❌ Recording start failed: \(error)")
            cameraOverlay.hide()
            micRecorder.stop()
            cleanup()
        }
    }
    
    /// Show a simple full-screen countdown overlay (3…2…1) before recording.
    private func runCountdown(from seconds: Int) async {
        guard seconds > 0 else { return }
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        label.alignment = .center
        label.font = .systemFont(ofSize: 120, weight: .bold)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        label.layer?.cornerRadius = 24
        panel.contentView = label
        
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - 100,
                y: screen.frame.midY - 100
            ))
        }
        panel.orderFront(nil)
        
        for n in stride(from: seconds, through: 1, by: -1) {
            label.stringValue = "\(n)"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        panel.orderOut(nil)
    }
    
    func stop() async {
        guard isRecording else { return }
        isRecording = false
        
        cameraOverlay.hide()
        micRecorder.stop()
        
        do {
            try await stream?.stopCapture()
        } catch {
            print("⚠️ stopCapture error: \(error)")
        }
        stream = nil
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        if let writer = assetWriter {
            await writer.finishWriting()
            if writer.status == .completed, let url = outputURL {
                print("✅ Recording saved: \(url.path)")
                lastRecordingURL = url
                revealInFinder(url)
                notifySaved(url)
            } else {
                print("❌ Recording writer status: \(writer.status.rawValue)")
            }
        }
        cleanup()
    }
    
    // MARK: - Writer setup
    
    private func setupWriter(width: Int, height: Int, withSystemAudio: Bool, withMic: Bool) throws {
        try StorageManager.shared.ensureSaveDirectory()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "SnapFree Recording \(formatter.string(from: Date())).mov"
        let url = StorageManager.shared.defaultSaveURL.appendingPathComponent(name)
        outputURL = url
        
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        
        if writer.canAdd(input) {
            writer.add(input)
        }
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]
        
        // System audio track (from SCStream).
        if withSystemAudio {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) { writer.add(aInput) }
            audioInput = aInput
        } else {
            audioInput = nil
        }
        
        // Microphone track (from AVCaptureSession). A separate track keeps the
        // two sources from clobbering each other's timing.
        if withMic {
            let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            mInput.expectsMediaDataInRealTime = true
            if writer.canAdd(mInput) { writer.add(mInput) }
            micInput = mInput
        } else {
            micInput = nil
        }
        
        assetWriter = writer
        videoInput = input
        sessionStarted = false
    }
    
    private func cleanup() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        outputURL = nil
        sessionStarted = false
    }
    
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func notifySaved(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Recording Saved"
        alert.informativeText = "Saved to:\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - SCStreamDelegate

extension RecordingManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("⚠️ Stream stopped with error: \(error)")
        Task { @MainActor in
            self.isRecording = false
            self.cleanup()
        }
    }
}

// MARK: - SCStreamOutput

extension RecordingManager: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        
        if type == .screen {
            // Only append complete video frames.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else { return }
            Task { @MainActor in
                self.appendVideo(sampleBuffer)
            }
        } else if type == .audio {
            Task { @MainActor in
                self.appendAudio(sampleBuffer)
            }
        }
    }
    
    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter, let input = videoInput else { return }
        
        if !sessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            sessionStarted = true
        }
        
        if input.isReadyForMoreMediaData, writer.status == .writing {
            input.append(sampleBuffer)
        }
    }
    
    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // Audio can only be appended after the session has started on the
        // video track (which establishes the timeline).
        guard sessionStarted,
              let writer = assetWriter, let input = audioInput,
              input.isReadyForMoreMediaData, writer.status == .writing else { return }
        input.append(sampleBuffer)
    }
    
    private func appendMic(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted,
              let writer = assetWriter, let input = micInput,
              input.isReadyForMoreMediaData, writer.status == .writing else { return }
        input.append(sampleBuffer)
    }
}
