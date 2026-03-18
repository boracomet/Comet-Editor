//
//  VideoProcessor.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 6.03.2026.
//

import Foundation
import AVFoundation
import CoreVideo
import VideoToolbox
import Combine
import SwiftUI
import CoreImage
import os

enum VideoConversionError: Error, LocalizedError {
    case invalidSource
    case cannotCreateAssetWriter
    case cannotCreatePixelBufferPool
    case decoderError
    case writerFailure
    
    var errorDescription: String? {
        switch self {
        case .invalidSource: return NSLocalizedString("video.error.invalidSource", comment: "")
        case .cannotCreateAssetWriter: return NSLocalizedString("video.error.assetWriter", comment: "")
        case .cannotCreatePixelBufferPool: return NSLocalizedString("video.error.pixelBufferPool", comment: "")
        case .decoderError: return NSLocalizedString("video.error.decoder", comment: "")
        case .writerFailure: return NSLocalizedString("video.error.writerFailure", comment: "")
        }
    }
}

@MainActor
class VideoProcessor: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isProcessing: Bool = false
    
    init() {
        // Initialize the CVC Engine globally (stateless FFmpeg registration)
        cvc_engine_init()
    }
    
    func convert(inputURL: URL, outputURL: URL, format: VideoFormat, quality: Double, settings: VideoConversionSettings? = nil, manageProcessingState: Bool = true, cancellationCheck: (() -> Bool)? = nil) async throws {
        if manageProcessingState {
            self.isProcessing = true
            self.progress = 0.0
        }
        defer {
            if manageProcessingState {
                self.isProcessing = false
            }
        }
        
        // This hybrid process delegates Demuxing & Decoding to the C Core (FFmpeg),
        // and generates the final output using AVFoundation (Hardware Accelerated H.265/H.264 Encoder).
        try await processWithCVCHybrid(input: inputURL, output: outputURL, format: format, quality: quality, settings: settings, cancellationCheck: cancellationCheck)
    }
    
    // MARK: - Core Hybrid Pipeline (C-Decoding -> Swift-Encoding)
    private func processWithCVCHybrid(input: URL, output: URL, format: VideoFormat, quality: Double, settings: VideoConversionSettings?, cancellationCheck: (() -> Bool)? = nil) async throws {
        // 1. Initialize C Decoder Context
        var info = CVCVideoInfo()
        var readResult: CVCResult = CVC_SUCCESS
        
        let ctx = cvc_decoder_open(input.path.cString(using: .utf8), &info, &readResult)
        
        guard let ctx = ctx, readResult == CVC_SUCCESS else {
            let errorMsg = String(cString: cvc_get_error_string(readResult))
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cometeditor", category: "VideoProcessor").error("CVC Decoder Open Failed: \(errorMsg)")
            throw VideoConversionError.decoderError
        }
        
        defer {
            cvc_decoder_close(ctx)
        }
        
        // 2. Configure AVFoundation Encoder (Hardware Acceleration)
        let resolvedFileType = format.avFileType
        let writer = try AVAssetWriter(outputURL: output, fileType: resolvedFileType)
        
        // Determine Codec based on user preferences and format
        let compressionCodec: AVVideoCodecType
        if format == .mp4 || format == .mov {
            // For Apple-friendly formats, use high-efficiency HEVC if running on supported OS, otherwise H264
            compressionCodec = .hevc 
        } else {
            compressionCodec = .h264
        }
        
        // Calculate Settings Transforms
        
        let resolutionMultiplier = settings?.resolutionScale.multiplier ?? 1.0
        let targetWidth = Int(Double(info.width) * resolutionMultiplier)
        let targetHeight = Int(Double(info.height) * resolutionMultiplier)
        
        // Ensure even dimensions (required by many hardware encoders)
        let finalWidth = targetWidth % 2 == 0 ? targetWidth : targetWidth - 1
        let finalHeight = targetHeight % 2 == 0 ? targetHeight : targetHeight - 1
        
        // Convert our generic 0-10 quality scale to an AVFoundation bitrate heuristic
        let minBPP: Double = 0.01
        let maxBPP: Double = 0.15
        let bpp = minBPP + (quality / 10.0) * (maxBPP - minBPP)
        
        let originalFramerate = info.framerate > 0 ? info.framerate : 30.0
        let targetFramerate = settings?.fpsLimit.value ?? originalFramerate
        let finalFramerate = min(targetFramerate, originalFramerate)
        
        let targetBitrate: Double
        let isReducingFps = finalFramerate < originalFramerate - 0.5
        let frameDuration = info.duration_sec
        
        if isReducingFps, frameDuration > 0,
           let attrs = try? FileManager.default.attributesOfItem(atPath: input.path),
           let fileSize = attrs[.size] as? Int64, fileSize > 0 {
            // FPS düşürülüyorsa kaynak bitrate'e göre hedef belirle (boyut artışını önler)
            let sourceBitsPerSec = Double(fileSize) * 8.0 / frameDuration
            let videoRatio = 0.85
            let sourceVideoBps = sourceBitsPerSec * videoRatio
            let derivedBitrate = sourceVideoBps * (finalFramerate / originalFramerate)
            let minBitrate = 500_000.0
            targetBitrate = max(derivedBitrate, minBitrate)
        } else {
            targetBitrate = Double(finalWidth * finalHeight) * finalFramerate * bpp
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: compressionCodec,
            AVVideoWidthKey: finalWidth,
            AVVideoHeightKey: finalHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                AVVideoExpectedSourceFrameRateKey: finalFramerate
            ]
        ]
        
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw VideoConversionError.cannotCreateAssetWriter
        }
        
        // Initialize Scaler mapping attributes strictly for the exact output dimensions we want
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        // Pixel Buffer attributes mappings: from FFmpeg (YUV420P) -> AVFoundation (NV12 Interleaved BiPlanar)
        // We tell the adaptor to accept pixel buffers that match the TARGET scaled dimensions
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: finalWidth,
            kCVPixelBufferHeightKey as String: finalHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        
        guard writer.canAdd(writerInput) else {
            throw VideoConversionError.cannotCreateAssetWriter
        }
        
        writer.add(writerInput)
        
        // --- Metadata Preservation ---
        if settings?.keepMetadata ?? true {
            let assetForMetadata = AVURLAsset(url: input)
            if let metadata = try? await assetForMetadata.load(.metadata) {
                writer.metadata = metadata
            }
        }
        
        // --- Audio Logic (Placeholder for future bridge mapping) ---
        // If removeAudio is false, we ideally want to map audio tracks.
        // Currently, our C Bridge does not extract audio PCM packets to AVFoundation yet.
        // However, if the user checks "removeAudio = true", we ensure we do absolutely nothing.
        
        guard writer.startWriting() else {
            throw VideoConversionError.writerFailure
        }
        writer.startSession(atSourceTime: .zero)
        
        // 3. Pixel Buffer Pool Setup (Zero-Copy Target)
        var pixelBufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, sourcePixelBufferAttributes as CFDictionary, &pixelBufferPool)
        
        guard let pool = pixelBufferPool else {
            throw VideoConversionError.cannotCreatePixelBufferPool
        }
        
        // 4. Decode loop
        var currentPTS: Double = 0.0
        
        let fpsLimit = settings?.fpsLimit.value
        let needsFpsLimit = fpsLimit != nil && fpsLimit! < originalFramerate - 0.01
        
        let needsScaling = (finalWidth != info.width) || (finalHeight != info.height)
        let ciContext = CIContext(options: [.cacheIntermediates: false]) // Fast CoreImage context for hardware scaling
        
        // 3. Prepare Audio Writer (Optional)
        var audioInput: AVAssetWriterInput?
        let hasAudio = info.audio_stream_index >= 0
        let shouldIncludeAudio = hasAudio && settings?.removeAudio == false
        
        if shouldIncludeAudio {
            // High-quality AAC settings for the audio track
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: info.sample_rate > 0 ? info.sample_rate : 44100,
                AVNumberOfChannelsKey: info.channels > 0 ? info.channels : 2,
                AVEncoderBitRateKey: 128000
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = false
            if let ai = audioInput, writer.canAdd(ai) {
                writer.add(ai)
            }
        }
        
        // 4. Start processing
        // Push the processing to a background detached task context to not freeze UI
        let checkCancel = cancellationCheck
        let finalStatus = await Task.detached(priority: .userInitiated) { () -> Bool in
            var isFinished = false
            var outputFrameCount = 0
            var lastOutputIndex: Int = -1
            while !isFinished {
                if checkCancel?() == true { return false }
                let success: Bool = autoreleasepool {
                    var cvcFrame = CVCVideoFrame()
                    let readResult = cvc_decoder_read_video_frame(ctx, &cvcFrame)
                    
                    if readResult == CVC_EOF {
                        isFinished = true
                        return true
                    } else if readResult != CVC_SUCCESS {
                        cvc_video_frame_free(&cvcFrame)
                        return false 
                    }
                    
                    // FPS limit: output first source frame in each output frame "bucket" (fixes 60->24 giving 20fps)
                    if needsFpsLimit, let limit = fpsLimit {
                        let outputIndex = Int(cvcFrame.pts_sec * limit)
                        if outputIndex <= lastOutputIndex {
                            cvc_video_frame_free(&cvcFrame)
                            return true
                        }
                        lastOutputIndex = outputIndex
                    }
                    
                    while !writerInput.isReadyForMoreMediaData {
                        usleep(2_000)
                    }
                    
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
                    
                    if let pb = pixelBuffer {
                        if needsScaling {
                            var originalBuffer: CVPixelBuffer?
                            let originalAttributes: [String: Any] = [
                                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                                kCVPixelBufferWidthKey as String: Int(info.width),
                                kCVPixelBufferHeightKey as String: Int(info.height)
                            ]
                            
                            CVPixelBufferCreate(kCFAllocatorDefault, Int(info.width), Int(info.height), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, originalAttributes as CFDictionary, &originalBuffer)
                            
                            if let origPb = originalBuffer {
                                CVPixelBufferLockBaseAddress(origPb, [])
                                if let yDest = CVPixelBufferGetBaseAddressOfPlane(origPb, 0), let ySrc = cvcFrame.data.0 {
                                    let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(origPb, 0)
                                    let ySrcStride = Int(cvcFrame.linesize.0)
                                    for row in 0..<Int(cvcFrame.height) {
                                        memcpy(yDest.advanced(by: row * yDestStride), ySrc.advanced(by: row * ySrcStride), Int(cvcFrame.width))
                                    }
                                }
                                
                                if let uvDest = CVPixelBufferGetBaseAddressOfPlane(origPb, 1), let uSrc = cvcFrame.data.1, let vSrc = cvcFrame.data.2 {
                                    let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(origPb, 1)
                                    let uSrcStride = Int(cvcFrame.linesize.1)
                                    let vSrcStride = Int(cvcFrame.linesize.2)
                                    let halfWidth = Int(cvcFrame.width) / 2
                                    let halfHeight = Int(cvcFrame.height) / 2
                                    for row in 0..<halfHeight {
                                        let destRow = uvDest.advanced(by: row * uvDestStride)
                                        let uRow = uSrc.advanced(by: row * uSrcStride)
                                        let vRow = vSrc.advanced(by: row * vSrcStride)
                                        for col in 0..<halfWidth {
                                            destRow.storeBytes(of: uRow[col], toByteOffset: col * 2, as: UInt8.self)
                                            destRow.storeBytes(of: vRow[col], toByteOffset: col * 2 + 1, as: UInt8.self)
                                        }
                                    }
                                }
                                CVPixelBufferUnlockBaseAddress(origPb, [])
                                
                                let ciImage = CIImage(cvPixelBuffer: origPb)
                                let scaleX = CGFloat(finalWidth) / CGFloat(info.width)
                                let scaleY = CGFloat(finalHeight) / CGFloat(info.height)
                                let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                                
                                ciContext.render(scaledImage, to: pb)
                            }
                        } else {
                            CVPixelBufferLockBaseAddress(pb, [])
                            if let yDest = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let ySrc = cvcFrame.data.0 {
                                let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
                                let ySrcStride = Int(cvcFrame.linesize.0)
                                for row in 0..<Int(cvcFrame.height) {
                                    memcpy(yDest.advanced(by: row * yDestStride), ySrc.advanced(by: row * ySrcStride), Int(cvcFrame.width))
                                }
                            }
                            if let uvDest = CVPixelBufferGetBaseAddressOfPlane(pb, 1), let uSrc = cvcFrame.data.1, let vSrc = cvcFrame.data.2 {
                                let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
                                let uSrcStride = Int(cvcFrame.linesize.1)
                                let vSrcStride = Int(cvcFrame.linesize.2)
                                let halfWidth = Int(cvcFrame.width) / 2
                                let halfHeight = Int(cvcFrame.height) / 2
                                for row in 0..<halfHeight {
                                    let destRow = uvDest.advanced(by: row * uvDestStride)
                                    let uRow = uSrc.advanced(by: row * uSrcStride)
                                    let vRow = vSrc.advanced(by: row * vSrcStride)
                                    for col in 0..<halfWidth {
                                        destRow.storeBytes(of: uRow[col], toByteOffset: col * 2, as: UInt8.self)
                                        destRow.storeBytes(of: vRow[col], toByteOffset: col * 2 + 1, as: UInt8.self)
                                    }
                                }
                            }
                            CVPixelBufferUnlockBaseAddress(pb, [])
                        }
                        
                        // Use synthetic timestamps for CFR output (avoids 22fps etc. from VFR/source PTS)
                        let outputPTS = Double(outputFrameCount) / finalFramerate
                        let time = CMTime(seconds: outputPTS, preferredTimescale: 600)
                        pixelBufferAdaptor.append(pb, withPresentationTime: time)
                        
                        outputFrameCount += 1
                        currentPTS = cvcFrame.pts_sec
                    }
                    
                    let videoPTS = cvcFrame.pts_sec
                    cvc_video_frame_free(&cvcFrame)
                    
                    // 2. Audio Sync or Drain
                    if hasAudio {
                        if shouldIncludeAudio, let aInput = audioInput {
                            var aFrame = CVCAudioFrame()
                            while cvc_decoder_read_audio_frame(ctx, &aFrame) == CVC_SUCCESS {
                                if aFrame.internal_frame == nil { break }
                                
                                var waitCount = 0
                                while !aInput.isReadyForMoreMediaData {
                                    usleep(1_000)
                                    waitCount += 1
                                    if waitCount > 5000 || writer.status == .failed { break }
                                }
                                if writer.status == .failed { cvc_audio_frame_free(&aFrame); break }
                                
                                self.appendAudioFrame(aFrame, to: aInput)
                                let aPTS = aFrame.pts_sec
                                cvc_audio_frame_free(&aFrame)
                                
                                if aPTS > videoPTS { break }
                            }
                        } else {
                            // Ses kaldırıldığında sadece queue'dan boşalt (dosyadan okumaz, video paketi kaybı yok)
                            _ = cvc_decoder_drain_audio_queue(ctx)
                        }
                    }
                    
                    return true
                }
                
                if !success { return false }
                if checkCancel?() == true { return false }
                
                Task { @MainActor in
                    if frameDuration > 0 {
                        self.progress = currentPTS / frameDuration
                    }
                }
            }
            return true
        }.value
        
        if !finalStatus {
            writer.cancelWriting()
            if checkCancel?() == true {
                throw CancellationError()
            }
            throw VideoConversionError.decoderError
        }
        
        // 5. Finalize file
        writerInput.markAsFinished()
        
        await writer.finishWriting()
        
        if writer.status == .failed {
            throw writer.error ?? VideoConversionError.writerFailure
        }
        
        self.progress = 1.0
    }
    
    private nonisolated func appendAudioFrame(_ frame: CVCAudioFrame, to input: AVAssetWriterInput) {
        let sampleCount = Int32(frame.nb_samples)
        let channels = Int32(frame.channels)
        let sampleRate = Double(frame.sample_rate)
        
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        var formatDesc: CMFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        
        guard let desc = formatDesc, let dataPtr = frame.data.0 else { return }
        
        let dataSize = Int(frame.linesize.0)
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: dataPtr,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard let bb = blockBuffer else { return }
        
        var sampleBuffer: CMSampleBuffer?
        let time = CMTime(seconds: frame.pts_sec, preferredTimescale: Int32(sampleRate))
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: CMItemCount(sampleCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        if let sb = sampleBuffer {
            if input.isReadyForMoreMediaData {
                input.append(sb)
            }
        }
    }
}

// Ensure extensions map correctly to AVFoundation UTI formats
fileprivate extension VideoFormat {
    var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        // If the user chooses MKV or AVI (foreign formats), AVFoundation cannot inherently write them.
        // In a true hybrid output, we'd use FFmpeg Writer. But since our stated goal 
        // is pushing everything to the highest supported compat formats, map them to MP4 container.
        case .mkv: return .mp4 
        case .avi: return .mp4
        }
    }
}
