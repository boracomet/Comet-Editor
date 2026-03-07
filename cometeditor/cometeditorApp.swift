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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
                .environmentObject(appState)
                .environmentObject(languageManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
