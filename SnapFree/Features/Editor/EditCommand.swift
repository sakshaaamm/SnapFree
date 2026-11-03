//
//  EditCommand.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Command Pattern for Undo/Redo
//

import AppKit

// MARK: - Command Protocol

protocol EditCommand {
    func execute()
    func undo()
    func redo()
}

// MARK: - Add Annotation Command

class AddAnnotationCommand: EditCommand {
    private let annotation: any AnnotationProtocol
    private weak var canvas: AnnotationCanvasModel?
    
    init(annotation: any AnnotationProtocol, canvas: AnnotationCanvasModel) {
        self.annotation = annotation
        self.canvas = canvas
    }
    
    func execute() {
        canvas?.addAnnotation(annotation)
    }
    
    func undo() {
        canvas?.removeAnnotation(annotation)
    }
    
    func redo() {
        execute()
    }
}

// MARK: - Remove Annotation Command

class RemoveAnnotationCommand: EditCommand {
    private let annotation: any AnnotationProtocol
    private let index: Int
    private weak var canvas: AnnotationCanvasModel?
    
    init(annotation: any AnnotationProtocol, index: Int, canvas: AnnotationCanvasModel) {
        self.annotation = annotation
        self.index = index
        self.canvas = canvas
    }
    
    func execute() {
        canvas?.removeAnnotation(annotation)
    }
    
    func undo() {
        canvas?.insertAnnotation(annotation, at: index)
    }
    
    func redo() {
        execute()
    }
}

// MARK: - Move Annotation Command

class MoveAnnotationCommand: EditCommand {
    private let annotationID: UUID
    private let oldFrame: CGRect
    private let newFrame: CGRect
    private weak var canvas: AnnotationCanvasModel?
    
    init(annotationID: UUID, from oldFrame: CGRect, to newFrame: CGRect, canvas: AnnotationCanvasModel) {
        self.annotationID = annotationID
        self.oldFrame = oldFrame
        self.newFrame = newFrame
        self.canvas = canvas
    }
    
    func execute() {
        canvas?.moveAnnotation(id: annotationID, to: newFrame)
    }
    
    func undo() {
        canvas?.moveAnnotation(id: annotationID, to: oldFrame)
    }
    
    func redo() {
        execute()
    }
}

// MARK: - Resize Annotation Command

class ResizeAnnotationCommand: EditCommand {
    private let annotation: any AnnotationProtocol
    private let oldFrame: CGRect
    private let newFrame: CGRect
    
    init(annotation: any AnnotationProtocol, from oldFrame: CGRect, to newFrame: CGRect) {
        self.annotation = annotation
        self.oldFrame = oldFrame
        self.newFrame = newFrame
    }
    
    func execute() {
        // Apply new frame
    }
    
    func undo() {
        // Restore old frame
    }
    
    func redo() {
        execute()
    }
}

// MARK: - Crop Command

class CropCommand: EditCommand {
    private let cropRect: CGRect
    private var originalImage: NSImage?
    private var croppedImage: NSImage?
    private weak var canvas: AnnotationCanvasModel?
    
    init(cropRect: CGRect, canvas: AnnotationCanvasModel) {
        self.cropRect = cropRect
        self.canvas = canvas
    }
    
    func execute() {
        guard let canvas = canvas else { return }
        originalImage = canvas.image
        croppedImage = canvas.crop(to: cropRect)
        canvas.image = croppedImage!
    }
    
    func undo() {
        guard let original = originalImage else { return }
        canvas?.image = original
    }
    
    func redo() {
        guard let cropped = croppedImage else { return }
        canvas?.image = cropped
    }
}
