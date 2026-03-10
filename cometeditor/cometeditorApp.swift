//
//  cometeditorApp.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

@main
struct cometeditorApp: App {
    @StateObject private var appState = GlobalAppState()
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var windowState = WindowStateObserver()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 520)
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
                .environmentObject(appState)
                .environmentObject(languageManager)
                .environmentObject(windowState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
