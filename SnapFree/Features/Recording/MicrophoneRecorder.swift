//
//  MicrophoneRecorder.swift
//  SnapFree
//
//  Captures microphone audio via AVCaptureSession and forwards sample buffers
//  to a handler so RecordingManager can write them into a dedicated audio
//  track (mixed alongside system audio from SCStream).
//

import AVFoundation

final class MicrophoneRecorder: NSObject {
    
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.snapfree.mic.samples")
    
    /// Called for every microphone sample buffer while running.
    var onSample: ((CMSampleBuffer) -> Void)?
    
    private(set) var isRunning = false
    
    /// Request permission and start capturing. Returns true if the mic started.
    func start() -> Bool {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("⚠️ Microphone unavailable")
            return false
        }
        
        session.beginConfiguration()
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        
        queue.async { [session] in
            session.startRunning()
        }
        isRunning = true
        return true
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        let s = session
        queue.async {
            s.stopRunning()
        }
        onSample = nil
    }
}

extension MicrophoneRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSample?(sampleBuffer)
    }
}
