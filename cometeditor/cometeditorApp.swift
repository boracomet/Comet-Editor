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

    init() {
        // configure sync olarak çalışır — ContentView.task başlamadan baseURL set olur
        CometAnalytics.shared.configure(
            apiKey: "changeme_sdk_key_at_least_32_chars_here",
            baseURL: "http://localhost:3001"
        )
    }

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
}
