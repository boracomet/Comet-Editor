//
//  MenuItem.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

enum MenuSection: String, CaseIterable {
    case main
    case tools
    case document

    var title: LocalizedStringKey? {
        switch self {
        case .main: return nil
        case .tools: return "menu.tools"
        case .document: return "menu.document"
        }
    }

    var items: [MenuItem] {
        switch self {
        case .main: return [.home]
        case .tools: return [.convertImage, .videoConvert]
        case .document: return [.pdfEdit, .qrCode]
        }
    }
}

enum MenuItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case convertImage
    case videoConvert
    case pdfEdit
    case qrCode

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "menu.home"
        case .convertImage: return "menu.convertImage"
        case .videoConvert: return "menu.videoConvert"
        case .pdfEdit: return "menu.pdfEdit"
        case .qrCode: return "menu.qrCode"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .convertImage: return "photo.on.rectangle.angled"
        case .videoConvert: return "video.fill"
        case .pdfEdit: return "doc.text.fill"
        case .qrCode: return "qrcode"
        }
    }
}
