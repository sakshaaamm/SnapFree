//
//  HistoryView.swift
//  SnapFree
//
//  Grid of past captures with copy / save / edit / delete actions.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject private var history = HistoryManager.shared
    var onEdit: (CaptureItem) -> Void
    
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(history.entries) { entry in
                            HistoryCell(entry: entry, onEdit: onEdit)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 440)
    }
    
    private var header: some View {
        HStack {
            Text("Capture History")
                .font(.headline)
            Spacer()
            if !history.entries.isEmpty {
                Button(role: .destructive) {
                    history.clearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }
        }
        .padding(12)
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No captures yet")
                .foregroundStyle(.secondary)
            Text("Your screenshots will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cell

private struct HistoryCell: View {
    let entry: HistoryEntry
    var onEdit: (CaptureItem) -> Void
    
    @ObservedObject private var history = HistoryManager.shared
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                
                if isHovering {
                    Button {
                        history.delete(entry)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            
            HStack(spacing: 4) {
                Image(systemName: entry.type.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            if isHovering {
                HStack(spacing: 8) {
                    actionButton("doc.on.doc", "Copy") { copy() }
                    actionButton("square.and.arrow.down", "Save") { save() }
                    actionButton("pencil", "Edit") { edit() }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
    
    private var thumbnail: some View {
        Group {
            if let image = history.image(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func actionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .help(label)
    }
    
    private func copy() {
        if let image = history.image(for: entry) {
            ClipboardManager.shared.copyImage(image)
        }
    }
    
    private func save() {
        if let image = history.image(for: entry) {
            _ = StorageManager.shared.saveImageWithPanel(image)
        }
    }
    
    private func edit() {
        if let item = history.captureItem(for: entry) {
            onEdit(item)
        }
    }
}
