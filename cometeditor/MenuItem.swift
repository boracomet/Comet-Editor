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

    var title: LocalizedStringKey? {
        switch self {
        case .main: return nil
        case .tools: return "menu.tools"
        }
    }

    var items: [MenuItem] {
        switch self {
        case .main: return [.home]
        case .tools: return [.convertImage, .videoConvert, .videoEdit, .stockImage, .pdfEdit, .qrCode, .bgRemove, .ocr, .fontDownload]
        }
    }
}

enum MenuItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case convertImage
    case videoConvert
    case stockImage
    case pdfEdit
    case qrCode
    case bgRemove
    case ocr
    case fontDownload
    case videoEdit
    case team

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "menu.home"
        case .convertImage: return "menu.convertImage"
        case .videoConvert: return "menu.videoConvert"
        case .stockImage: return "menu.stockImage"
        case .pdfEdit: return "menu.pdfEdit"
        case .qrCode: return "menu.qrCode"
        case .bgRemove: return "menu.bgRemove"
        case .ocr: return "menu.ocr"
        case .fontDownload: return "menu.fontDownload"
        case .videoEdit: return "menu.videoEdit"
        case .team: return "menu.team"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .convertImage: return "photo.on.rectangle.angled"
        case .videoConvert: return "video.fill"
        case .stockImage: return "photo.stack.fill"
        case .pdfEdit: return "doc.text.fill"
        case .qrCode: return "qrcode"
        case .bgRemove: return "person.and.background.dotted"
        case .ocr: return "text.viewfinder"
        case .fontDownload: return "character.textbox"
        case .videoEdit: return "film.stack"
        case .team: return "person.3.fill"
        }
    }

    var badge: String? { nil }
}
