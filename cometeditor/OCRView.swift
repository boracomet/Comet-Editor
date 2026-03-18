//
//  OCRView.swift
//  cometeditor
//
//  Vision VNRecognizeTextRequest — sıfır dışa bağımlılık
//

import SwiftUI
import Vision
import UniformTypeIdentifiers

struct OCRView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver

    @State private var isEditing = false
    @State private var isDropTargeted = false
    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 0) {
            // Sol: Resim
            leftPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Sağ: Metin çıktısı
            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
    }

    // MARK: - Sol Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                if appState.ocrImage != nil {
                    Button {
                        reset()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey("ocr.clear"))
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        openFilePicker()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey("ocr.newFile"))
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                if appState.ocrIsProcessing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(LocalizedStringKey("ocr.processing"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .opacity(appState.ocrImage != nil || appState.ocrIsProcessing ? 1 : 0)

            if appState.ocrImage != nil { Divider() }

            if let img = appState.ocrImage {
                GeometryReader { geo in
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .onDrop(of: [UTType.image], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                dropZone
            }
        }
    }

    // MARK: - Sağ Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Sağ toolbar
            HStack(spacing: 8) {
                Spacer()

                if !appState.ocrRecognizedText.isEmpty {
                    Button {
                        isEditing.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey(isEditing ? "alert.ok" : "ocr.edit"))
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.ocrRecognizedText, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey(isCopied ? "ocr.copied" : "ocr.copy"))
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 52)

            Divider()

            if appState.ocrRecognizedText.isEmpty && !appState.ocrIsProcessing {
                VStack(spacing: 12) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text(LocalizedStringKey("ocr.result.placeholder"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEditing {
                TextEditor(text: $appState.ocrRecognizedText)
                    .font(.system(size: 13))
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(appState.ocrRecognizedText)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        Button { openFilePicker() } label: {
            VStack(spacing: 16) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                VStack(spacing: 6) {
                    Text(LocalizedStringKey("ocr.drop.title"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(LocalizedStringKey("ocr.drop.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .padding(24)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: [UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .bmp, .tiff, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(url: url)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                DispatchQueue.main.async { loadImage(url: url) }
            }
        }
        return true
    }

    private func loadImage(url: URL) {
        appState.ocrIsProcessing = true
        appState.ocrRecognizedText = ""
        isEditing = false
        Task {
            // Load file data off the main thread, then construct NSImage on main thread
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            guard let data, let img = NSImage(data: data) else {
                await MainActor.run { appState.ocrIsProcessing = false }
                return
            }
            await MainActor.run {
                appState.ocrImage = img
                appState.ocrImageURL = url
            }
            await recognizeText(in: img)
        }
    }

    @MainActor
    private func recognizeText(in image: NSImage) async {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            appState.ocrIsProcessing = false
            return
        }
        defer { appState.ocrIsProcessing = false }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = ["tr-TR", "en-US"]
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let result: Result<[String], Error> = await Task.detached {
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                return .success(observations.compactMap { $0.topCandidates(1).first?.string })
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let lines):
            appState.ocrRecognizedText = lines.joined(separator: "\n")
        case .failure(let error):
            appState.ocrRecognizedText = error.localizedDescription
        }
    }

    private func reset() {
        appState.ocrImage = nil
        appState.ocrImageURL = nil
        appState.ocrRecognizedText = ""
        isEditing = false
        isCopied = false
    }
}
