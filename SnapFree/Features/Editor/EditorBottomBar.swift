//
//  EditorBottomBar.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Bottom Bar
//

import SwiftUI

struct EditorBottomBar: View {
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    var onShare: (NSView?) -> Void = { _ in }
    
    var body: some View {
        HStack {
            // Cancel button
            Button(action: onCancel) {
                Text("Cancel")
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            // Export options
            Menu {
                Button("Copy to Clipboard") {
                    onCopy()
                }
                Button("Save…") {
                    onSave()
                }
                Divider()
                Button("Share…") {
                    onShare(shareAnchor.view)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Invisible anchor used to position the macOS share sheet.
            shareAnchor
                .frame(width: 1, height: 1)
            
            // Quick actions
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // A tiny NSView we can anchor the share picker to.
    private let shareAnchor = ShareAnchorView()
}

/// A minimal NSViewRepresentable that exposes its backing NSView so the
/// native share sheet can be anchored to a real on-screen rectangle.
struct ShareAnchorView: NSViewRepresentable {
    final class Holder {
        var view: NSView?
    }
    let holder = Holder()
    var view: NSView? { holder.view }
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        holder.view = v
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}

#Preview {
    EditorBottomBar(
        onSave: {},
        onCopy: {},
        onCancel: {}
    )
}
