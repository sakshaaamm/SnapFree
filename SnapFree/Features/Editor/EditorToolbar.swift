//
//  EditorToolbar.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Toolbar
//

import SwiftUI

struct EditorToolbar: View {
    let selectedTool: AnnotationTool
    let selectedColor: Color
    let lineWidth: CGFloat
    let textSize: CGFloat
    let blurRadius: CGFloat
    let pixelSize: CGFloat
    let canUndo: Bool
    let canRedo: Bool
    
    let onToolSelected: (AnnotationTool) -> Void
    let onColorChanged: (Color) -> Void
    let onLineWidthChanged: (CGFloat) -> Void
    let onTextSizeChanged: (CGFloat) -> Void
    let onBlurRadiusChanged: (CGFloat) -> Void
    let onPixelSizeChanged: (CGFloat) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    
    @State private var showColorPicker = false
    @State private var showLineWidthPicker = false
    
    // Preset colors
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .brown,
        .black, .gray, .white
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tools row
            HStack(spacing: 4) {
                // Select / move
                toolButton(.select)
                
                Divider()
                    .frame(height: 24)
                
                // Shape tools
                Group {
                    toolButton(.arrow)
                    toolButton(.rectangle)
                    toolButton(.circle)
                    toolButton(.line)
                }
                
                Divider()
                    .frame(height: 24)
                
                // Drawing + marking tools
                Group {
                    toolButton(.pen)
                    toolButton(.highlight)
                    toolButton(.textHighlight)
                    toolButton(.text)
                    toolButton(.counter)
                }
                
                Divider()
                    .frame(height: 24)
                
                // Redaction tools
                Group {
                    toolButton(.blur)
                    toolButton(.pixelate)
                }
                
                Divider()
                    .frame(height: 24)
                
                // Crop tool
                toolButton(.crop)
                
                Spacer()
                
                // Undo/Redo
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canUndo)
                .help("Undo (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)
                
                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canRedo)
                .help("Redo (⌘⇧Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])
                
                Divider()
                    .frame(height: 24)
                
                // Color picker
                colorPickerButton
                
                // Line width
                lineWidthButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            colorPickerPopover
        }
        .popover(isPresented: $showLineWidthPicker, arrowEdge: .bottom) {
            lineWidthPopover
        }
    }
    
    // MARK: - Tool Button
    
    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: { onToolSelected(tool) }) {
            Image(systemName: tool.icon)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .tint(selectedTool == tool ? .accentColor : .primary)
        .help(tool.displayName)
    }
    
    // MARK: - Color Picker
    
    private var colorPickerButton: some View {
        Button(action: { showColorPicker.toggle() }) {
            Circle()
                .fill(selectedColor)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: 1)
                )
        }
        .buttonStyle(.borderless)
        .help("Color")
    }
    
    private var colorPickerPopover: some View {
        VStack(spacing: 8) {
            Text("Color")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .onTapGesture {
                            onColorChanged(color)
                            showColorPicker = false
                        }
                }
            }
            
            ColorPicker("Custom", selection: Binding(
                get: { selectedColor },
                set: { onColorChanged($0) }
            ))
            .labelsHidden()
        }
        .padding()
    }
    
    // MARK: - Contextual Size Control
    
    // The size control adapts to the active tool: text size for the text tool,
    // blur radius for blur, pixel size for pixelate, otherwise line width.
    private var sizeConfig: (label: String, icon: String, value: CGFloat, range: ClosedRange<CGFloat>, unit: String, set: (CGFloat) -> Void) {
        switch selectedTool {
        case .text:
            return ("Text Size", "textformat.size", textSize, 8...96, "pt", onTextSizeChanged)
        case .blur:
            return ("Blur Level", "drop.fill", blurRadius, 2...50, "", onBlurRadiusChanged)
        case .pixelate:
            return ("Pixelate Level", "square.grid.3x3.fill", pixelSize, 4...60, "", onPixelSizeChanged)
        default:
            return ("Line Width", "line.horizontal.3", lineWidth, 1...20, "px", onLineWidthChanged)
        }
    }
    
    private var lineWidthButton: some View {
        let config = sizeConfig
        return Button(action: { showLineWidthPicker.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: config.icon)
                Text("\(Int(config.value))")
                    .font(.caption)
                    .monospacedDigit()
            }
            .frame(width: 48, height: 28)
        }
        .buttonStyle(.borderless)
        .help(config.label)
    }
    
    private var lineWidthPopover: some View {
        let config = sizeConfig
        return VStack(spacing: 8) {
            Text(config.label)
                .font(.headline)
            
            Slider(value: Binding(
                get: { config.value },
                set: { config.set($0) }
            ), in: config.range, step: 1)
            .frame(width: 180)
            
            Text("\(Int(config.value)) \(config.unit)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    EditorToolbar(
        selectedTool: .arrow,
        selectedColor: .red,
        lineWidth: 3,
        textSize: 16,
        blurRadius: 10,
        pixelSize: 10,
        canUndo: true,
        canRedo: false,
        onToolSelected: { _ in },
        onColorChanged: { _ in },
        onLineWidthChanged: { _ in },
        onTextSizeChanged: { _ in },
        onBlurRadiusChanged: { _ in },
        onPixelSizeChanged: { _ in },
        onUndo: {},
        onRedo: {}
    )
}
