//
//  SettingsView.swift
//  SnapFree
//
//  Phase 3: Settings - Preferences Window (wired to SettingsStore)
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            
            RecordingSettingsView()
                .tabItem { Label("Recording", systemImage: "video") }
            
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "folder") }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    
    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Play Sound on Capture", isOn: $settings.playSound)
                Toggle("Show Preview After Capture", isOn: $settings.showPreview)
            }
            
            Section("After Capture") {
                Toggle("Copy to Clipboard", isOn: $settings.copyToClipboard)
                Toggle("Auto-save to Folder", isOn: $settings.autoSave)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Recording

struct RecordingSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    
    var body: some View {
        Form {
            Section("Audio") {
                Toggle("Record System Audio", isOn: $settings.recordSystemAudio)
                Toggle("Record Microphone", isOn: $settings.recordMicrophone)
            }
            
            Section("Video") {
                Picker("Max Resolution", selection: $settings.recordMaxResolution) {
                    ForEach(RecordingResolution.allCases) { res in
                        Text(res.displayName).tag(res)
                    }
                }
                Picker("Frame Rate", selection: $settings.recordFPS) {
                    Text("24 FPS").tag(24)
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
            }
            
            Section("Camera") {
                Toggle("Record Camera (Face Cam)", isOn: $settings.recordCamera)
                if settings.recordCamera {
                    Picker("Shape", selection: $settings.recordCameraShape) {
                        ForEach(CameraShape.allCases) { shape in
                            Text(shape.displayName).tag(shape)
                        }
                    }
                    HStack {
                        Text("Camera Size")
                        Slider(value: $settings.recordCameraSize, in: 100...320)
                        Text("\(Int(settings.recordCameraSize))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Shows a floating webcam bubble that is included in the recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Cursor") {
                Toggle("Show Cursor While Recording", isOn: $settings.recordShowCursor)
            }
            
            Section("Countdown") {
                Toggle("Show Countdown Before Recording", isOn: $settings.recordShowCountdown)
                if settings.recordShowCountdown {
                    Stepper("Countdown: \(settings.recordCountdownSeconds)s",
                            value: $settings.recordCountdownSeconds, in: 1...10)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Global Shortcuts") {
                shortcutRow("Capture Area", "⌃⌥⌘1")
                shortcutRow("Capture Fullscreen", "⌃⌥⌘2")
                shortcutRow("Capture Window", "⌃⌥⌘3")
                shortcutRow("Capture Text (OCR)", "⌃⌥⌘4")
                shortcutRow("Record Screen", "⌃⌥⌘5")
            }
            Section {
                Text("Global shortcuts work anywhere, even when SnapFree is in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Storage

struct StorageSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    
    var body: some View {
        Form {
            Section("Save Location") {
                HStack {
                    Text(StorageManager.shared.defaultSaveURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal in Finder") {
                        try? StorageManager.shared.ensureSaveDirectory()
                        NSWorkspace.shared.open(StorageManager.shared.defaultSaveURL)
                    }
                }
            }
            
            Section("File Format") {
                Picker("Format", selection: $settings.imageFormat) {
                    Text("PNG").tag(ImageFormat.png)
                    Text("JPEG").tag(ImageFormat.jpeg)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
