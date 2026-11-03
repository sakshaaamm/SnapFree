//
//  ShortcutManager.swift
//  SnapFree
//
//  Phase 3: Quick Access - Global Keyboard Shortcuts
//

import Foundation
import Carbon
import SwiftUI

/// Manages global keyboard shortcuts for SnapFree
class ShortcutManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ShortcutManager()
    
    // MARK: - Published State
    
    @Published var shortcuts: [Shortcut] = []
    @Published var isRecording = false
    @Published var recordedShortcut: Shortcut?
    
    // MARK: - Private Properties
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var captureManager: CaptureManager?
    
    // MARK: - Initialization
    
    private init() {
        loadDefaultShortcuts()
        setupEventHandler()
    }
    
    deinit {
        unregisterAllHotKeys()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
    
    // MARK: - Default Shortcuts
    
    private func loadDefaultShortcuts() {
        // IMPORTANT: macOS reserves ⌘⇧3 (full-screen shot), ⌘⇧4 (area shot) and
        // ⌘⇧5 (screenshot bar). Using those would fire BOTH macOS and SnapFree,
        // producing two screenshots. We use ⌃⌥⌘ (Control+Option+Command), which
        // macOS leaves free, so only SnapFree responds.
        let mods: NSEvent.ModifierFlags = [.control, .option, .command]
        shortcuts = [
            Shortcut(
                id: "captureArea",
                name: "Capture Area",
                keyCode: 18, // '1'
                modifiers: mods,
                action: { [weak self] in
                    Task { @MainActor in self?.captureManager?.captureArea() }
                }
            ),
            Shortcut(
                id: "captureFullScreen",
                name: "Capture Full Screen",
                keyCode: 19, // '2'
                modifiers: mods,
                action: { [weak self] in
                    Task { @MainActor in self?.captureManager?.captureFullScreen() }
                }
            ),
            Shortcut(
                id: "captureWindow",
                name: "Capture Window",
                keyCode: 20, // '3'
                modifiers: mods,
                action: { [weak self] in
                    Task { @MainActor in self?.captureManager?.captureWindow() }
                }
            )
        ]
    }
    
    // MARK: - Setup
    
    func setCaptureManager(_ manager: CaptureManager) {
        self.captureManager = manager
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            let shortcutManager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr {
                shortcutManager.handleHotKeyPress(hotKeyID.id)
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
    
    // MARK: - Registration
    
    func registerAllHotKeys() {
        unregisterAllHotKeys()
        
        for (index, shortcut) in shortcuts.enumerated() {
            registerHotKey(shortcut, id: UInt32(index))
        }
    }
    
    private func registerHotKey(_ shortcut: Shortcut, id: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x53465052) // 'SFPR' - SnapFree Prefix
        hotKeyID.id = id
        
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRefs[id]
        )
        
        if status != noErr {
            print("❌ Failed to register hot key: \(shortcut.name)")
        }
    }
    
    func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
    
    // MARK: - Event Handling
    
    private func handleHotKeyPress(_ id: UInt32) {
        guard let index = shortcuts.indices.first(where: { UInt32($0) == id }) else { return }
        let shortcut = shortcuts[index]
        shortcut.action?()
    }
    
    // MARK: - Shortcut Management
    
    func updateShortcut(_ shortcut: Shortcut, keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index].keyCode = keyCode
            shortcuts[index].modifiers = modifiers
            registerAllHotKeys()
        }
    }
}

// MARK: - Shortcut Model

struct Shortcut: Identifiable {
    let id: String
    let name: String
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags
    var action: (() -> Void)?
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        
        return carbon
    }
    
    private func keyCodeToString(_ code: UInt32) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        default: return "?"
        }
    }
}


