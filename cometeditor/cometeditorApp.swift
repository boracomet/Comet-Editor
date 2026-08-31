//
//  cometeditorApp.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI
import AppKit

@main
struct cometeditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = GlobalAppState()
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var windowState = WindowStateObserver()
    @StateObject private var videoProcessor = VideoProcessor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 520)
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
                .environmentObject(appState)
                .environmentObject(languageManager)
                .environmentObject(windowState)
                .environmentObject(videoProcessor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Pencere kapat butonuna (⌘W veya kırmızı X) basılınca uygulamayı tamamen kapat.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTempFiles()
    }

    private func cleanupTempFiles() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("ve_preview_") || file.lastPathComponent.hasPrefix("ve_thumb_") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
