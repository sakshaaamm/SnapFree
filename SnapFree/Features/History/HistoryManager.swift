//
//  HistoryManager.swift
//  SnapFree
//
//  Persistent capture history. Saves each capture's image to disk and keeps
//  a JSON index so history survives app relaunches.
//

import AppKit
import Combine

/// A lightweight, Codable record of a past capture.
struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let typeRaw: String
    let imageFilename: String      // file name within the history directory
    let sourceAppName: String?
    
    var type: CaptureType {
        CaptureType(rawValue: typeRaw) ?? .area
    }
}

@MainActor
final class HistoryManager: ObservableObject {
    
    static let shared = HistoryManager()
    
    @Published private(set) var entries: [HistoryEntry] = []
    
    private let maxEntries = 100
    private let fileManager = FileManager.default
    
    private init() {
        try? ensureDirectory()
        load()
    }
    
    // MARK: - Locations
    
    /// ~/Library/Application Support/SnapFree/History
    private var historyDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("SnapFree", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }
    
    private var indexURL: URL {
        historyDirectory.appendingPathComponent("index.json")
    }
    
    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: historyDirectory.path) {
            try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Public API
    
    /// Record a new capture into history (writes its PNG + updates the index).
    func add(_ capture: CaptureItem) {
        do {
            try ensureDirectory()
            
            let filename = "\(capture.id.uuidString).png"
            let url = historyDirectory.appendingPathComponent(filename)
            
            if let data = pngData(from: capture.image) {
                try data.write(to: url)
            }
            
            let entry = HistoryEntry(
                id: capture.id,
                timestamp: capture.timestamp,
                typeRaw: capture.type.rawValue,
                imageFilename: filename,
                sourceAppName: capture.sourceAppName
            )
            
            entries.insert(entry, at: 0)
            trimIfNeeded()
            save()
        } catch {
            print("❌ Failed to add history entry: \(error)")
        }
    }
    
    /// Load the NSImage for a history entry from disk.
    func image(for entry: HistoryEntry) -> NSImage? {
        let url = historyDirectory.appendingPathComponent(entry.imageFilename)
        return NSImage(contentsOf: url)
    }
    
    /// Reconstruct a CaptureItem (used when opening an entry in the editor).
    func captureItem(for entry: HistoryEntry) -> CaptureItem? {
        guard let image = image(for: entry) else { return nil }
        return CaptureItem(
            id: entry.id,
            timestamp: entry.timestamp,
            type: entry.type,
            image: image,
            sourceAppName: entry.sourceAppName
        )
    }
    
    func delete(_ entry: HistoryEntry) {
        let url = historyDirectory.appendingPathComponent(entry.imageFilename)
        try? fileManager.removeItem(at: url)
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func clearAll() {
        for entry in entries {
            let url = historyDirectory.appendingPathComponent(entry.imageFilename)
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll()
        save()
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            // Keep only entries whose image file still exists.
            entries = decoded.filter {
                fileManager.fileExists(
                    atPath: historyDirectory.appendingPathComponent($0.imageFilename).path
                )
            }
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL)
        } catch {
            print("❌ Failed to save history index: \(error)")
        }
    }
    
    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let overflow = entries[maxEntries...]
        for entry in overflow {
            let url = historyDirectory.appendingPathComponent(entry.imageFilename)
            try? fileManager.removeItem(at: url)
        }
        entries = Array(entries.prefix(maxEntries))
    }
    
    // MARK: - Helpers
    
    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
