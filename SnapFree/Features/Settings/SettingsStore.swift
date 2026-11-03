//
//  SettingsStore.swift
//  SnapFree
//
//  Central, persisted user settings backed by UserDefaults. All managers read
//  from here so the Preferences UI actually changes behavior.
//

import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    
    static let shared = SettingsStore()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private enum Key {
        static let copyToClipboard = "copyToClipboard"
        static let autoSave = "autoSave"
        static let playSound = "playSound"
        static let showPreview = "showPreview"
        static let imageFormat = "imageFormat"
        static let saveLocationBookmark = "saveLocationBookmark"
        static let launchAtLogin = "launchAtLogin"
        // Recording
        static let recordMicrophone = "recordMicrophone"
        static let recordSystemAudio = "recordSystemAudio"
        static let recordShowCursor = "recordShowCursor"
        static let recordShowCountdown = "recordShowCountdown"
        static let recordCountdownSeconds = "recordCountdownSeconds"
        static let recordCamera = "recordCamera"
        static let recordMaxResolution = "recordMaxResolution"
        static let recordFPS = "recordFPS"
        static let recordCameraSize = "recordCameraSize"
        static let recordCameraShape = "recordCameraShape"
    }
    
    // MARK: - Published settings
    
    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }
    
    @Published var autoSave: Bool {
        didSet { defaults.set(autoSave, forKey: Key.autoSave) }
    }
    
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }
    
    @Published var showPreview: Bool {
        didSet { defaults.set(showPreview, forKey: Key.showPreview) }
    }
    
    @Published var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }
    
    // MARK: - Recording settings
    
    @Published var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: Key.recordMicrophone) }
    }
    
    @Published var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: Key.recordSystemAudio) }
    }
    
    @Published var recordShowCursor: Bool {
        didSet { defaults.set(recordShowCursor, forKey: Key.recordShowCursor) }
    }
    
    @Published var recordShowCountdown: Bool {
        didSet { defaults.set(recordShowCountdown, forKey: Key.recordShowCountdown) }
    }
    
    @Published var recordCountdownSeconds: Int {
        didSet { defaults.set(recordCountdownSeconds, forKey: Key.recordCountdownSeconds) }
    }
    
    @Published var recordCamera: Bool {
        didSet { defaults.set(recordCamera, forKey: Key.recordCamera) }
    }
    
    @Published var recordMaxResolution: RecordingResolution {
        didSet { defaults.set(recordMaxResolution.rawValue, forKey: Key.recordMaxResolution) }
    }
    
    @Published var recordFPS: Int {
        didSet { defaults.set(recordFPS, forKey: Key.recordFPS) }
    }
    
    /// Diameter / size of the face-cam bubble in points.
    @Published var recordCameraSize: Double {
        didSet { defaults.set(recordCameraSize, forKey: Key.recordCameraSize) }
    }
    
    @Published var recordCameraShape: CameraShape {
        didSet { defaults.set(recordCameraShape.rawValue, forKey: Key.recordCameraShape) }
    }
    
    // MARK: - Init (register defaults)
    
    private init() {
        defaults.register(defaults: [
            Key.copyToClipboard: true,
            Key.autoSave: false,
            Key.playSound: true,
            Key.showPreview: true,
            Key.imageFormat: ImageFormat.png.rawValue,
            Key.launchAtLogin: false,
            Key.recordMicrophone: false,
            Key.recordSystemAudio: true,
            Key.recordShowCursor: true,
            Key.recordShowCountdown: true,
            Key.recordCountdownSeconds: 3,
            Key.recordCamera: false,
            Key.recordMaxResolution: RecordingResolution.original.rawValue,
            Key.recordFPS: 60,
            Key.recordCameraSize: 180.0,
            Key.recordCameraShape: CameraShape.circle.rawValue
        ])
        
        copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)
        autoSave = defaults.bool(forKey: Key.autoSave)
        playSound = defaults.bool(forKey: Key.playSound)
        showPreview = defaults.bool(forKey: Key.showPreview)
        imageFormat = ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "png") ?? .png
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        recordMicrophone = defaults.bool(forKey: Key.recordMicrophone)
        recordSystemAudio = defaults.bool(forKey: Key.recordSystemAudio)
        recordShowCursor = defaults.bool(forKey: Key.recordShowCursor)
        recordShowCountdown = defaults.bool(forKey: Key.recordShowCountdown)
        recordCountdownSeconds = defaults.integer(forKey: Key.recordCountdownSeconds)
        recordCamera = defaults.bool(forKey: Key.recordCamera)
        recordMaxResolution = RecordingResolution(rawValue: defaults.string(forKey: Key.recordMaxResolution) ?? "original") ?? .original
        recordFPS = defaults.integer(forKey: Key.recordFPS)
        recordCameraSize = defaults.double(forKey: Key.recordCameraSize)
        recordCameraShape = CameraShape(rawValue: defaults.string(forKey: Key.recordCameraShape) ?? "circle") ?? .circle
    }
    
    // MARK: - Launch at Login
    
    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("❌ Launch-at-login change failed: \(error)")
        }
    }
}

// MARK: - Recording Resolution

enum RecordingResolution: String, CaseIterable, Identifiable {
    case original
    case uhd4k = "4k"
    case qhd1440 = "1440p"
    case fhd1080 = "1080p"
    case hd720 = "720p"
    case sd480 = "480p"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .original: return "Original"
        case .uhd4k: return "4K"
        case .qhd1440: return "1440p"
        case .fhd1080: return "1080p"
        case .hd720: return "720p"
        case .sd480: return "480p"
        }
    }
    
    /// Maximum output height in pixels (nil = keep native resolution).
    var maxHeight: Int? {
        switch self {
        case .original: return nil
        case .uhd4k: return 2160
        case .qhd1440: return 1440
        case .fhd1080: return 1080
        case .hd720: return 720
        case .sd480: return 480
        }
    }
}

// MARK: - Face Cam Shape

enum CameraShape: String, CaseIterable, Identifiable {
    case circle
    case square
    case rectangle   // 16:9 landscape

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    
    /// Pixel dimensions for a given base size.
    func size(base: CGFloat) -> CGSize {
        switch self {
        case .circle, .square:
            return CGSize(width: base, height: base)
        case .rectangle:
            return CGSize(width: base * 16.0 / 9.0, height: base)
        }
    }
}
