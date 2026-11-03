//
//  EditHistory.swift
//  SnapFree
//
//  Phase 2: Annotation Editor - Undo/Redo Stack
//

import Foundation
import Combine

/// Manages the undo/redo history for the annotation editor
class EditHistory: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    
    // MARK: - Private Properties
    
    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []
    private let maxHistorySize: Int
    
    // MARK: - Initialization
    
    init(maxHistorySize: Int = 50) {
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Public Methods
    
    /// Execute a command and add it to the undo stack
    func execute(_ command: EditCommand) {
        command.execute()
        
        undoStack.append(command)
        redoStack.removeAll()
        
        // Limit history size
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
        
        updateState()
    }
    
    /// Undo the last command
    func undo() {
        guard let command = undoStack.popLast() else { return }
        
        command.undo()
        redoStack.append(command)
        
        updateState()
    }
    
    /// Redo the last undone command
    func redo() {
        guard let command = redoStack.popLast() else { return }
        
        command.redo()
        undoStack.append(command)
        
        updateState()
    }
    
    /// Clear all history
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }
    
    // MARK: - Private Methods
    
    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
