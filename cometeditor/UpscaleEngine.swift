//
//  UpscaleEngine.swift
//  cometeditor
//
//  Upscayl NCNN (realesrgan-ncnn-vulkan) ikilisini uygulama paketindeki
//  `Resources/upscale/` klasöründen çalıştırır.
//  Gerekli: upscale/realesrgan-ncnn-vulkan + upscale/models/upscayl-standard-4x.{param,bin}
//

import Foundation

enum UpscaleOutputFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}

enum UpscaleEngineError: LocalizedError {
    case bundleLayoutMissing
    case binaryMissing
    case modelFilesMissing
    case processFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .bundleLayoutMissing:
            return NSLocalizedString("upscale.error.bundle", comment: "")
        case .binaryMissing:
            return NSLocalizedString("upscale.error.binary", comment: "")
        case .modelFilesMissing:
            return NSLocalizedString("upscale.error.model", comment: "")
        case .processFailed(let code, let message):
            return String(format: NSLocalizedString("upscale.error.process", comment: ""), code, message)
        }
    }
}

enum UpscaleScale: Int, CaseIterable, Identifiable {
    case x2 = 2
    case x4 = 4
    case x8 = 8
    case x16 = 16

    var id: Int { rawValue }
    var label: String { "\(rawValue)×" }

    /// Kaç ardışık 4× geçiş gerektiği ve son geçişte kullanılacak `-s` değeri.
    /// Örn. 2× → tek geçiş `-s 2`; 8× → 4× + 2× (iki geçiş); 16× → 4× + 4× (iki geçiş).
    var passes: [(scale: Int, isFinal: Bool)] {
        switch self {
        case .x2:  return [(2, true)]
        case .x4:  return [(4, true)]
        case .x8:  return [(4, false), (2, true)]
        case .x16: return [(4, false), (4, true)]
        }
    }
}

enum UpscaleEngine {
    static let upscaylStandardNCNNModelName = "upscayl-standard-4x"

    /// `Contents/Resources/upscale` (Xcode’da `third_party/upscale` klasör referansı)
    private static func bundleUpscaleRoot() throws -> URL {
        guard let res = Bundle.main.resourceURL else { throw UpscaleEngineError.bundleLayoutMissing }
        let root = res.appendingPathComponent("upscale", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { throw UpscaleEngineError.bundleLayoutMissing }
        return root
    }

    private static let binaryName = "cometscaly"

    private static func binaryURL(root: URL) throws -> URL {
        let u = root.appendingPathComponent(binaryName)
        guard FileManager.default.isExecutableFile(atPath: u.path) else {
            throw UpscaleEngineError.binaryMissing
        }
        return u
    }

    private static func modelsDirectoryURL(forRoot root: URL) -> URL {
        root.appendingPathComponent("models", isDirectory: true)
    }

    static func isBackendAvailable() -> Bool {
        guard let res = Bundle.main.resourceURL else { return false }
        let root = res.appendingPathComponent("upscale", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path),
              FileManager.default.fileExists(atPath: modelsDirectoryURL(forRoot: root).path) else { return false }
        guard (try? binaryURL(root: root)) != nil else { return false }
        return modelFilesExist(modelsDir: modelsDirectoryURL(forRoot: root))
    }

    private static func modelFilesExist(modelsDir: URL) -> Bool {
        let param = modelsDir.appendingPathComponent("\(upscaylStandardNCNNModelName).param")
        let bin = modelsDir.appendingPathComponent("\(upscaylStandardNCNNModelName).bin")
        return FileManager.default.fileExists(atPath: param.path) && FileManager.default.fileExists(atPath: bin.path)
    }

    /// `cometscaly` stdout satırlarındaki `12.34%` biçiminden son yüzdeyi döndürür.
    private static func lastPercentParsed(from text: String) -> Int? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, last.numberOfRanges >= 2,
              let r = Range(last.range(at: 1), in: text),
              let v = Double(text[r]) else { return nil }
        return Int(min(100, max(0, v.rounded())))
    }

    /// Tek görseli seçilen ölçekte büyütür.
    /// 2× ve 4× tek geçiş; 8× = 4×+2× (iki geçiş); 16× = 4×+4× (iki geçiş).
    /// `progress` 0…100 arası; çok geçişte geçiş başına ağırlıklandırılır.
    static func upscale(inputURL: URL, outputURL: URL, scale: UpscaleScale, progress: (@Sendable (Int) -> Void)? = nil) async throws {
        let root = try bundleUpscaleRoot()
        let binary = try binaryURL(root: root)
        let modelsDir = modelsDirectoryURL(forRoot: root)
        guard modelFilesExist(modelsDir: modelsDir) else { throw UpscaleEngineError.modelFilesMissing }

        let fm = FileManager.default
        let passes = scale.passes
        var tempFiles: [URL] = []

        defer { tempFiles.forEach { try? fm.removeItem(at: $0) } }

        let uid = UUID().uuidString

        // Child process sandbox/güvenlik kısıtlamaları nedeniyle input'u
        // geçici bir konuma kopyalıyoruz.
        let tmpInput = fm.temporaryDirectory
            .appendingPathComponent("comet_in_\(uid).\(inputURL.pathExtension)")
        try fm.copyItem(at: inputURL, to: tmpInput)
        tempFiles.append(tmpInput)

        var currentInput = tmpInput

        // Çıktıyı da önce tmp'ye yazıp sonra gerçek hedefe taşıyoruz
        let tmpFinalOutput = fm.temporaryDirectory
            .appendingPathComponent("comet_out_\(uid).\(outputURL.pathExtension)")
        tempFiles.append(tmpFinalOutput)

        let passCount = passes.count
        for (i, pass) in passes.enumerated() {
            let isLast = pass.isFinal
            let dest: URL
            if isLast {
                dest = tmpFinalOutput
            } else {
                let tmp = fm.temporaryDirectory
                    .appendingPathComponent("comet_upscale_\(UUID().uuidString).\(outputURL.pathExtension)")
                tempFiles.append(tmp)
                dest = tmp
            }

            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }

            let args: [String] = [
                "-i", currentInput.path,
                "-o", dest.path,
                "-n", upscaylStandardNCNNModelName,
                "-s", "\(pass.scale)",
                "-m", modelsDir.path,
            ]

            let passProgress: (@Sendable (Int) -> Void)?
            if let progress {
                let base = (100 * i) / passCount
                let span = 100 / passCount
                passProgress = { local in
                    let v = base + (local * span) / 100
                    progress(min(100, max(0, v)))
                }
            } else {
                passProgress = nil
            }

            let (status, errText, outText) = try await runDetached(
                binary: binary,
                arguments: args,
                workingDirectory: root,
                onProgress: passProgress
            )
            guard status == 0 else {
                throw UpscaleEngineError.processFailed(code: status, message: errText.isEmpty ? outText : errText)
            }
            guard fm.fileExists(atPath: dest.path) else {
                let combined = [errText, outText].filter { !$0.isEmpty }.joined(separator: "\n")
                throw UpscaleEngineError.processFailed(
                    code: -1,
                    message: "Pass \(i + 1) output missing.\n\(combined.isEmpty ? "No output from binary." : combined)"
                )
            }

            currentInput = dest
        }

        // Geçici çıktıyı gerçek hedefe taşı
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.moveItem(at: tmpFinalOutput, to: outputURL)
        progress?(100)
    }

    private static func runDetached(
        binary: URL,
        arguments: [String],
        workingDirectory: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> (Int32, String, String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = binary
                p.arguments = arguments
                p.currentDirectoryURL = workingDirectory
                let errPipe = Pipe()
                let outPipe = Pipe()
                p.standardError = errPipe
                p.standardOutput = outPipe
                let outRead = outPipe.fileHandleForReading
                let errRead = errPipe.fileHandleForReading
                let ioLock = NSLock()
                var stdoutFull = ""
                var stderrFull = ""
                var stdoutCarry = ""
                var stderrCarry = ""

                /// ncnn/vulkan araçları ilerlemeyi çoğunlukla stderr'e yazar; \r ile aynı satırı güncellerler.
                func feedStreamChunk(_ raw: String, full: inout String, carry: inout String) {
                    full.append(raw)
                    guard let onProgress else { return }
                    let normalized = raw
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                    carry.append(normalized)
                    let lines = carry.split(separator: "\n", omittingEmptySubsequences: false)
                    if lines.count > 1 {
                        for line in lines.dropLast() {
                            if let pct = lastPercentParsed(from: String(line)) {
                                onProgress(pct)
                            }
                        }
                        carry = String(lines.last ?? Substring(""))
                    }
                    if let pct = lastPercentParsed(from: carry) {
                        onProgress(pct)
                    }
                }

                if onProgress != nil {
                    outRead.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        if chunk.isEmpty { return }
                        guard let s = String(data: chunk, encoding: .utf8) else { return }
                        ioLock.lock()
                        feedStreamChunk(s, full: &stdoutFull, carry: &stdoutCarry)
                        ioLock.unlock()
                    }
                    errRead.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        if chunk.isEmpty { return }
                        guard let s = String(data: chunk, encoding: .utf8) else { return }
                        ioLock.lock()
                        feedStreamChunk(s, full: &stderrFull, carry: &stderrCarry)
                        ioLock.unlock()
                    }
                }

                do {
                    try p.run()
                    p.waitUntilExit()
                    outRead.readabilityHandler = nil
                    errRead.readabilityHandler = nil
                    let trailingOut = outRead.readDataToEndOfFile()
                    let trailingErr = errRead.readDataToEndOfFile()
                    ioLock.lock()
                    if let tail = String(data: trailingOut, encoding: .utf8) {
                        feedStreamChunk(tail, full: &stdoutFull, carry: &stdoutCarry)
                    }
                    if let tail = String(data: trailingErr, encoding: .utf8) {
                        feedStreamChunk(tail, full: &stderrFull, carry: &stderrCarry)
                    }
                    if onProgress != nil {
                        for line in stdoutCarry.split(separator: "\n", omittingEmptySubsequences: false) {
                            if let pct = lastPercentParsed(from: String(line)) {
                                onProgress?(pct)
                            }
                        }
                        for line in stderrCarry.split(separator: "\n", omittingEmptySubsequences: false) {
                            if let pct = lastPercentParsed(from: String(line)) {
                                onProgress?(pct)
                            }
                        }
                    }
                    let outStr = stdoutFull
                    let errStr = stderrFull
                    ioLock.unlock()

                    continuation.resume(returning: (p.terminationStatus, errStr, outStr))
                } catch {
                    outRead.readabilityHandler = nil
                    errRead.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
