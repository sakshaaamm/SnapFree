//
//  RecordingControlBar.swift
//  SnapFree
//
//  Pre-recording control bar shown when the user chooses "Record Screen".
//  Lets them pick screen-only vs screen + face cam, FPS and quality, then
//  start. While recording, a compact bar shows elapsed time and a stop button.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class RecordingControlBarController {
    
    static let shared = RecordingControlBarController()
    private init() {}
    
    private var panel: NSPanel?
    
    /// Show the setup bar so the user can configure and start a recording.
    func present() {
        // If a recording is already running, stop it instead.
        if RecordingManager.shared.isRecording {
            Task { await RecordingManager.shared.stop() }
            return
        }
        
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        
        let view = RecordingControlBar(
            onStart: { [weak self] in
                self?.dismiss()
                Task { await RecordingManager.shared.start() }
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )
        
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let size = NSSize(width: 540, height: max(fitting.height, 170))
        hosting.frame = NSRect(origin: .zero, size: size)
        
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.contentView = hosting
        
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 120
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
    
    func dismiss() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

// MARK: - Setup Bar View

struct RecordingControlBar: View {
    let onStart: () -> Void
    let onCancel: () -> Void
    
    @ObservedObject private var settings = SettingsStore.shared
    
    var body: some View {
        VStack(spacing: 14) {
            // Mode row: screen only vs screen + facecam, plus audio/cursor.
            HStack(spacing: 8) {
                toggleChip(icon: "camera.fill", label: "Face Cam",
                           isOn: $settings.recordCamera)
                toggleChip(icon: "speaker.wave.2.fill", label: "System Audio",
                           isOn: $settings.recordSystemAudio)
                toggleChip(icon: "mic.fill", label: "Microphone",
                           isOn: $settings.recordMicrophone)
                toggleChip(icon: "cursorarrow", label: "Cursor",
                           isOn: $settings.recordShowCursor)
                toggleChip(icon: "timer", label: "Countdown",
                           isOn: $settings.recordShowCountdown)
            }
            
            // Quality row.
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Quality").foregroundStyle(.secondary).font(.caption)
                    Picker("", selection: $settings.recordMaxResolution) {
                        ForEach(RecordingResolution.allCases) { res in
                            Text(res.displayName).tag(res)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                
                HStack(spacing: 6) {
                    Text("FPS").foregroundStyle(.secondary).font(.caption)
                    Picker("", selection: $settings.recordFPS) {
                        Text("24").tag(24)
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }
                
                if settings.recordCamera {
                    HStack(spacing: 6) {
                        Text("Shape").foregroundStyle(.secondary).font(.caption)
                        Picker("", selection: $settings.recordCameraShape) {
                            ForEach(CameraShape.allCases) { shape in
                                Text(shape.displayName).tag(shape)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
            }
            
            if settings.recordCamera {
                HStack(spacing: 6) {
                    Text("Cam Size").foregroundStyle(.secondary).font(.caption)
                    Slider(value: $settings.recordCameraSize, in: 100...320)
                        .frame(width: 200)
                    Text("\(Int(settings.recordCameraSize))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            
            // Action row.
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                
                Button(action: onStart) {
                    Label("Start Recording", systemImage: "record.circle")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                .tint(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func toggleChip(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 72, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn.wrappedValue ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
