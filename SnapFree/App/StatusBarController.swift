//
//  StatusBarController.swift
//  SnapFree
//
//  Persistent menu bar status item (replaces SwiftUI MenuBarExtra, which
//  loses its item after triggering capture overlays).
//

import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class StatusBarController {
    
    private let statusItem: NSStatusItem
    private let captureManager = CaptureManager.shared
    private var quickAccessController: QuickAccessWindowController?
    private var editorControllers: [EditorWindowController] = []
    private var historyWindowController: HistoryWindowController?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Create a persistent status item with a fixed length.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.fill",
                accessibilityDescription: "SnapFree"
            )
            button.image?.isTemplate = true
        }
        
        statusItem.menu = buildMenu()
        statusItem.isVisible = true
        
        observeCaptures()
    }
    
    // MARK: - Capture Observation
    
    private func observeCaptures() {
        // When a new capture completes, show the quick-access preview.
        captureManager.$lastCapture
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] capture in
                guard SettingsStore.shared.showPreview else { return }
                self?.showQuickAccess(for: capture)
            }
            .store(in: &cancellables)
        
        // Keep the menu title / status icon in sync with the recording state.
        RecordingManager.shared.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateRecordingMenuTitle()
            }
            .store(in: &cancellables)
    }
    
    private func showQuickAccess(for capture: CaptureItem) {
        // Dismiss any existing preview first.
        quickAccessController?.close()
        
        let controller = QuickAccessWindowController(
            capture: capture,
            onCopy: {
                ClipboardManager.shared.copyImage(capture.image)
            },
            onSave: {
                try? StorageManager.shared.saveImage(capture.image)
            },
            onEdit: { [weak self] item in
                self?.openEditor(with: item)
            }
        )
        quickAccessController = controller
        controller.show()
    }
    
    // MARK: - Editor
    
    func openEditor(with capture: CaptureItem) {
        let controller = EditorWindowController(capture: capture)
        editorControllers.append(controller)
        
        // Remove the controller from our retention list when its window closes.
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.editorControllers.removeAll { $0 === controller }
                }
            }
        }
        
        controller.show()
    }
    
    // MARK: - Menu Construction
    
    /// Build a menu item with an SF Symbol icon (matching CleanShot X's layout).
    private func item(_ title: String, symbol: String, action: Selector,
                      key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = self
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.isTemplate = true
        menuItem.image = image
        return menuItem
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Capture Area
        menu.addItem(item("Capture Area", symbol: "viewfinder",
                          action: #selector(captureArea),
                          key: "1", modifiers: [.control, .option, .command]))
        
        // Capture Fullscreen
        menu.addItem(item("Capture Fullscreen", symbol: "display",
                          action: #selector(captureFullScreen),
                          key: "2", modifiers: [.control, .option, .command]))
        
        // Capture Window
        menu.addItem(item("Capture Window", symbol: "macwindow",
                          action: #selector(captureWindow),
                          key: "3", modifiers: [.control, .option, .command]))
        
        // Scrolling Capture
        menu.addItem(item("Scrolling Capture", symbol: "arrow.down.square",
                          action: #selector(captureScrolling)))
        
        // Self-Timer
        menu.addItem(item("Self-Timer", symbol: "timer",
                          action: #selector(captureSelfTimer)))
        
        // Capture Text (OCR)
        menu.addItem(item("Capture Text (OCR)", symbol: "textformat.abc",
                          action: #selector(captureText),
                          key: "4", modifiers: [.control, .option, .command]))
        
        // Record Screen
        let record = item("Record Screen", symbol: "video",
                          action: #selector(toggleRecording),
                          key: "5", modifiers: [.control, .option, .command])
        menu.addItem(record)
        recordingMenuItem = record
        
        // Show Desktop Icons
        let desktopIcons = item("Show Desktop Icons", symbol: "eye",
                                action: #selector(toggleDesktopIcons))
        desktopIcons.state = desktopIconsHidden ? .off : .on
        menu.addItem(desktopIcons)
        desktopIconsMenuItem = desktopIcons
        
        menu.addItem(.separator())
        
        // Open...
        menu.addItem(item("Open…", symbol: "folder",
                          action: #selector(openFile)))
        
        // Pin to the Screen...
        menu.addItem(item("Pin to the Screen…", symbol: "pin",
                          action: #selector(pinToScreen)))
        
        menu.addItem(.separator())
        
        // Capture History...
        menu.addItem(item("Capture History…", symbol: "clock.arrow.circlepath",
                          action: #selector(openHistory),
                          key: "h", modifiers: [.command, .shift]))
        
        menu.addItem(.separator())
        
        // About SnapFree...
        menu.addItem(item("About SnapFree…", symbol: "info.circle",
                          action: #selector(showAbout)))
        
        // Settings...
        menu.addItem(item("Settings…", symbol: "gearshape",
                          action: #selector(openPreferences),
                          key: ",", modifiers: [.command]))
        
        // Quit
        menu.addItem(item("Quit", symbol: "power",
                          action: #selector(quit),
                          key: "q", modifiers: [.command]))
        
        return menu
    }
    
    private weak var desktopIconsMenuItem: NSMenuItem?
    private var desktopIconsHidden = false
    
    private weak var recordingMenuItem: NSMenuItem?
    
    // MARK: - Actions
    
    @objc private func captureFullScreen() {
        captureManager.captureFullScreen()
    }
    
    @objc private func captureArea() {
        captureManager.captureArea()
    }
    
    @objc private func captureWindow() {
        captureManager.captureWindow()
    }
    
    @objc private func captureText() {
        captureManager.captureTextArea()
    }
    
    @objc private func captureScrolling() {
        ScrollingCaptureManager.shared.start { [weak self] image in
            let capture = CaptureItem(type: .area, image: image)
            HistoryManager.shared.add(capture)
            self?.openEditor(with: capture)
        }
    }
    
    @objc private func captureSelfTimer() {
        // Capture the full screen after a 5-second delay.
        let delay: TimeInterval = 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.captureManager.captureFullScreen()
        }
    }
    
    @objc private func toggleDesktopIcons() {
        desktopIconsHidden.toggle()
        let value = desktopIconsHidden ? "false" : "true"
        // Toggle Finder's desktop icon visibility.
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", value]
        try? task.run()
        task.waitUntilExit()
        
        let restart = Process()
        restart.launchPath = "/usr/bin/killall"
        restart.arguments = ["Finder"]
        try? restart.run()
        
        desktopIconsMenuItem?.state = desktopIconsHidden ? .off : .on
    }
    
    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        
        if panel.runModal() == .OK, let url = panel.url,
           let image = NSImage(contentsOf: url) {
            let capture = CaptureItem(type: .area, image: image)
            openEditor(with: capture)
        }
    }
    
    @objc private func pinToScreen() {
        // Pin the most recent capture as a floating always-on-top window.
        guard let capture = captureManager.lastCapture else {
            let alert = NSAlert()
            alert.messageText = "Pin to the Screen"
            alert.informativeText = "Take a screenshot first, then pin it to the screen."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        showPinnedWindow(for: capture)
    }
    
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SnapFree"
        ])
    }
    
    // MARK: - Pinned Window
    
    private var pinnedWindows: [NSWindow] = []
    
    private func showPinnedWindow(for capture: CaptureItem) {
        let imageSize = capture.image.size
        // Scale down large captures so the pin is a reasonable floating size.
        let maxDimension: CGFloat = 400
        let scale = min(1, maxDimension / max(imageSize.width, imageSize.height))
        let windowSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let container = NSView(frame: NSRect(origin: .zero, size: windowSize))
        container.wantsLayer = true
        
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: windowSize))
        imageView.image = capture.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        
        // Close button in the top-right corner of the pin.
        let closeButton = NSButton(frame: NSRect(x: windowSize.width - 26, y: windowSize.height - 26, width: 20, height: 20))
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        closeButton.layer?.cornerRadius = 10
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.target = self
        closeButton.action = #selector(closePinnedWindow(_:))
        container.addSubview(closeButton)
        
        window.contentView = container
        
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - windowSize.width / 2,
                y: screen.visibleFrame.midY - windowSize.height / 2
            ))
        }
        
        window.makeKeyAndOrderFront(nil)
        pinnedWindows.append(window)
    }
    
    @objc private func closePinnedWindow(_ sender: NSButton) {
        // Close the window that hosts this button.
        if let window = sender.window {
            window.orderOut(nil)
            pinnedWindows.removeAll { $0 === window }
        }
    }
    
    @objc private func toggleRecording() {
        if RecordingManager.shared.isRecording {
            Task { @MainActor in await RecordingManager.shared.stop() }
        } else {
            // Show the pre-recording control bar to pick options, then start.
            RecordingControlBarController.shared.present()
        }
    }
    
    private func updateRecordingMenuTitle() {
        recordingMenuItem?.title = RecordingManager.shared.isRecording
            ? "Stop Recording"
            : "Record Screen"
        recordingMenuItem?.image = NSImage(
            systemSymbolName: RecordingManager.shared.isRecording ? "stop.circle" : "video",
            accessibilityDescription: "Record Screen"
        )
        recordingMenuItem?.image?.isTemplate = true
        // Update the status bar icon to show recording state.
        if let button = statusItem.button {
            let symbol = RecordingManager.shared.isRecording ? "record.circle.fill" : "camera.fill"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SnapFree")
            button.image?.isTemplate = !RecordingManager.shared.isRecording
            button.contentTintColor = RecordingManager.shared.isRecording ? .systemRed : nil
        }
    }
    
    @objc private func openHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(
                onEdit: { [weak self] item in
                    self?.openEditor(with: item)
                }
            )
        }
        historyWindowController?.show()
    }
    
    @objc private func openPreferences() {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "SnapFree Preferences"
        settingsWindow.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
