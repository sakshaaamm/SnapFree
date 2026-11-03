//
//  CaptureType.swift
//  SnapFree
//
//  Phase 1: Foundation - Capture Types
//

import Foundation

enum CaptureType: String, CaseIterable {
    case fullScreen = "Full Screen"
    case area = "Area"
    case window = "Window"
    
    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.fill"
        case .area: return "selectionframe"
        case .window: return "uiwindow.split.2x1"
        }
    }
}
