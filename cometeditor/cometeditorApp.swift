//
//  cometeditorApp.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

@main
struct cometeditorApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @StateObject private var appState = GlobalAppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(\.locale, Locale(identifier: appLanguage))
                .environmentObject(appState)
                .id(appLanguage)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
