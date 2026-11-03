//
//  SnapFreeApp.swift
//  SnapFree
//
//  Phase 1: Foundation - Menu Bar App Entry Point
//

import SwiftUI

@main
struct SnapFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // The menu bar item is managed manually in AppDelegate via
        // StatusBarController. A Settings scene keeps the app alive without
        // showing any window on launch.
        Settings {
            EmptyView()
        }
    }
}
