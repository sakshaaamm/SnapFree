//
//  QuickAccessView.swift
//  SnapFree
//
//  Phase 3: Quick Access - Floating Preview View
//

import SwiftUI

struct QuickAccessView: View {
    let capture: CaptureItem
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: (CaptureItem) -> Void
    let onClose: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main preview image with corner tools
            ZStack {
                Image(nsImage: capture.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 160, maxHeight: 120)
                    .cornerRadius(6)
                    .shadow(radius: 2)
                
                // Tool buttons on 4 corners
                VStack {
                    HStack {
                        // Top-left: Copy
                        CornerButton(icon: "doc.on.doc", action: onCopy)
                        Spacer()
                        // Top-right: Save
                        CornerButton(icon: "square.and.arrow.down", action: onSave)
                    }
                    Spacer()
                    HStack {
                        // Bottom-left: Edit
                        CornerButton(icon: "pencil", action: { onEdit(capture) })
                        Spacer()
                        // Bottom-right: Close (dismiss without action)
                        CornerButton(icon: "xmark", action: onClose)
                    }
                }
                .padding(4)
            }
            .frame(width: 160, height: 120)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CornerButton: View {
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isHovered ? Color.black.opacity(0.8) : Color.black.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    QuickAccessView(
        capture: CaptureItem(
            type: .area,
            image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!
        ),
        onCopy: {},
        onSave: {},
        onEdit: { _ in },
        onClose: {}
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}
