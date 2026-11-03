//
//  StorageManager.swift
//  SnapFree
//
//  Phase 1: Foundation - File Storage
//

import AppKit
import UniformTypeIdentifiers

class StorageManager {
    static let shared = StorageManager()
    
    private init() {}
    
    // Default save location
    var defaultSaveURL: URL {
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return picturesURL.appendingPathComponent("SnapFree")
    }
    
    // Ensure save directory exists
    func ensureSaveDirectory() throws {
        if !FileManager.default.fileExists(atPath: defaultSaveURL.path) {
            try FileManager.default.createDirectory(at: defaultSaveURL, withIntermediateDirectories: true)
        }
    }
    
    /// Save image to disk
    /// - Parameters:
    ///   - image: The image to save
    ///   - filename: Optional custom filename (without extension)
    ///   - format: Image format (PNG or JPEG)
    /// - Returns: URL of saved file
    @discardableResult
    func saveImage(_ image: NSImage, filename: String? = nil, format: ImageFormat = .png) throws -> URL {
        try ensureSaveDirectory()
        
        let name = filename ?? generateFilename()
        let url = defaultSaveURL.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: format.bitmapType, properties: [:]) else {
            throw StorageError.encodingFailed
        }
        
        try data.write(to: url)
        print("✅ Saved image to: \(url.path)")
        return url
    }
    
    /// Show system save panel and save image
    func saveImageWithPanel(_ image: NSImage) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = generateFilename()
        panel.directoryURL = defaultSaveURL
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        
        do {
            try saveImage(image, to: url)
            return url
        } catch {
            print("❌ Failed to save: \(error)")
            return nil
        }
    }
    
    private func saveImage(_ image: NSImage, to url: URL) throws {
        let format: ImageFormat = url.pathExtension.lowercased() == "jpg" ? .jpeg : .png
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: format.bitmapType, properties: [:]) else {
            throw StorageError.encodingFailed
        }
        
        try data.write(to: url)
    }
    
    private func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "SnapFree \(formatter.string(from: Date()))"
    }
}

// MARK: - Supporting Types

enum ImageFormat: String, CaseIterable {
    case png
    case jpeg
    
    var fileExtension: String {
        rawValue
    }
    
    var bitmapType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
}

enum StorageError: LocalizedError {
    case encodingFailed
    case writeFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode image data"
        case .writeFailed(let error): return "Failed to write file: \(error.localizedDescription)"
        }
    }
}
