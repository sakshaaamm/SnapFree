//
//  EditorView.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Main Editor View
//

import SwiftUI

struct EditorView: View {
    let capture: CaptureItem
    var onClose: () -> Void
    
    @StateObject private var canvasModel: AnnotationCanvasModel
    
    init(capture: CaptureItem, onClose: @escaping () -> Void = {}) {
        self.capture = capture
        self.onClose = onClose
        _canvasModel = StateObject(wrappedValue: AnnotationCanvasModel(image: capture.image))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            EditorToolbar(
                selectedTool: canvasModel.currentTool,
                selectedColor: canvasModel.currentColor,
                lineWidth: canvasModel.lineWidth,
                textSize: canvasModel.textSize,
                blurRadius: canvasModel.blurRadius,
                pixelSize: canvasModel.pixelSize,
                canUndo: canvasModel.history.canUndo,
                canRedo: canvasModel.history.canRedo,
                onToolSelected: { tool in
                    canvasModel.currentTool = tool
                },
                onColorChanged: { color in
                    canvasModel.currentColor = color
                },
                onLineWidthChanged: { width in
                    canvasModel.lineWidth = width
                },
                onTextSizeChanged: { size in
                    canvasModel.textSize = size
                },
                onBlurRadiusChanged: { radius in
                    canvasModel.blurRadius = radius
                },
                onPixelSizeChanged: { size in
                    canvasModel.pixelSize = size
                },
                onUndo: {
                    canvasModel.history.undo()
                },
                onRedo: {
                    canvasModel.history.redo()
                }
            )
            
            // Canvas
            AnnotationCanvasView(model: canvasModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom bar
            EditorBottomBar(
                onSave: { saveImage() },
                onCopy: { copyToClipboard() },
                onCancel: { onClose() },
                onShare: { shareImage($0) }
            )
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    private func saveImage() {
        let finalImage = canvasModel.renderFinalImage()
        
        if let url = StorageManager.shared.saveImageWithPanel(finalImage) {
            print("✅ Saved to: \(url.path)")
            onClose()
        }
    }
    
    private func copyToClipboard() {
        let finalImage = canvasModel.renderFinalImage()
        ClipboardManager.shared.copyImage(finalImage)
        onClose()
    }
    
    private func shareImage(_ sourceView: NSView?) {
        let finalImage = canvasModel.renderFinalImage()
        let picker = NSSharingServicePicker(items: [finalImage])
        if let view = sourceView {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}

#Preview {
    EditorView(capture: CaptureItem(
        type: .area,
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: "Preview")!
    ))
}
