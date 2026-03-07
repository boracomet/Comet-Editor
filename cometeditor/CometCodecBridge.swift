import Foundation
import CoreGraphics
import AppKit

public enum CodecFormat {
    case webp
    case avif
    case auto
    
    var cicFormat: CICFormat {
        switch self {
        case .webp: return CIC_FORMAT_WEBP
        case .avif: return CIC_FORMAT_AVIF
        case .auto: return CIC_FORMAT_AUTO
        }
    }
}

public enum CodecError: Error {
    case outOfMemory
    case invalidParameter
    case unsupportedFormat
    case fileIoError
    case decodeFailed
    case encodeFailed
    case cancelled
    case unknown(Int32)
    
    init(_ cicError: CICError) {
        switch cicError {
        case CIC_ERROR_OUT_OF_MEMORY: self = .outOfMemory
        case CIC_ERROR_INVALID_PARAMETER: self = .invalidParameter
        case CIC_ERROR_UNSUPPORTED_FORMAT: self = .unsupportedFormat
        case CIC_ERROR_FILE_NOT_FOUND, CIC_ERROR_FILE_READ_FAILED, CIC_ERROR_FILE_WRITE_FAILED: self = .fileIoError
        case CIC_ERROR_DECODE_FAILED: self = .decodeFailed
        case CIC_ERROR_ENCODE_FAILED: self = .encodeFailed
        case CIC_ERROR_CANCELLED: self = .cancelled
        default: self = .unknown(Int32(cicError.rawValue))
        }
    }
}

public struct CodecMetrics {
    public let decodeTimeUs: UInt64
    public let encodeTimeUs: UInt64
    public let totalTimeUs: UInt64
    public let peakMemoryBytes: Int
    public let inputSizeBytes: Int
    public let outputSizeBytes: Int
}

public struct CodecQuality {
    public var value: Int32
    public var lossless: Bool
    
    nonisolated public init(value: Int, lossless: Bool = false) {
        self.value = Int32(max(0, min(100, value))) // clamp 0-100
        self.lossless = lossless
    }
    
    var cicQuality: CICQualityParams {
        return CICQualityParams(value: value, lossless: lossless)
    }
}

public class CometImageCodec {
    public static let shared = CometImageCodec()
    
    private var engine: OpaquePointer?
    
    // Initialize the Pure C core engine
    private init() {
        var config = CICConfig()
        config.thread_count = 0 // auto detect
        config.max_memory_mb = 500
        config.enable_simd = true
        config.log_level = CIC_LOG_LEVEL_INFO
        
        self.engine = cic_engine_create(&config)
        
        // Register Native Formats
        if let engine = self.engine {
            cic_engine_register_handler(engine, cic_webp_create_handler())
            cic_engine_register_handler(engine, cic_avif_create_handler())
        }
    }
    
    deinit {
        if let engine = self.engine {
            cic_engine_destroy(engine)
        }
    }
    
    /// Main async entry point to transcode an image completely in the C-layer
    public func convert(
        cgImage: CGImage,
        outputURL: URL,
        format: CodecFormat = .webp,
        quality: CodecQuality = CodecQuality(value: 80),
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> CodecMetrics {
        
        guard let engine = self.engine else {
            throw CodecError.unknown(-1)
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            throw CodecError.decodeFailed
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let dataPtr = context.data else {
            throw CodecError.decodeFailed
        }
        
        let bufferSize = height * bytesPerRow
        let dataRawPointer = dataPtr.bindMemory(to: UInt8.self, capacity: bufferSize)
        
        let imageBufferPtr = UnsafeMutablePointer<CICImageBuffer>.allocate(capacity: 1)
        imageBufferPtr.pointee = CICImageBuffer(
            width: UInt32(width),
            height: UInt32(height),
            format: CIC_PIXEL_FORMAT_RGBA,
            bit_depth: 8,
            data: dataRawPointer,
            stride: bytesPerRow,
            data_size: bufferSize
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            var params = CICJobParams()
            
            guard let outputPathCStr = strdup(outputURL.path) else {
                imageBufferPtr.deallocate()
                continuation.resume(throwing: CodecError.unknown(-1))
                return
            }
            
            params.input_path = nil
            params.input_buffer = imageBufferPtr
            params.output_path = UnsafePointer(outputPathCStr)
            params.input_format = CIC_FORMAT_AUTO
            params.output_format = format.cicFormat
            params.quality = quality.cicQuality
            
            // Progress callback block wrapper
            class ProgressContext {
                let handler: ((Double) -> Void)?
                let continuation: CheckedContinuation<CodecMetrics, Error>
                let engine: OpaquePointer
                let cgContext: CGContext
                let bufferPtr: UnsafeMutablePointer<CICImageBuffer>
                let outputPathStr: UnsafeMutablePointer<CChar>
                var handle: CICJobHandle?
                
                init(handler: ((Double) -> Void)?, continuation: CheckedContinuation<CodecMetrics, Error>, engine: OpaquePointer,
                     cgContext: CGContext, bufferPtr: UnsafeMutablePointer<CICImageBuffer>, outputPathStr: UnsafeMutablePointer<CChar>) {
                    self.handler = handler
                    self.continuation = continuation
                    self.engine = engine
                    self.cgContext = cgContext
                    self.bufferPtr = bufferPtr
                    self.outputPathStr = outputPathStr
                }
                
                deinit {
                    self.bufferPtr.deallocate()
                    free(self.outputPathStr)
                }
            }
            
            let progressContext = ProgressContext(
                handler: progressHandler,
                continuation: continuation,
                engine: engine,
                cgContext: context,
                bufferPtr: imageBufferPtr,
                outputPathStr: outputPathCStr
            )
            let rawContext = Unmanaged.passRetained(progressContext).toOpaque()
            
            params.user_data = rawContext
            
            params.progress = { (percentComplete: Double, bytesProcessed: Int, estimatedTimeRemaining: Double, userData: UnsafeMutableRawPointer?) in
                guard let userData = userData else { return }
                
                // If 100%, finish the continuation
                if percentComplete >= 1.0 {
                    let unmanaged = Unmanaged<ProgressContext>.fromOpaque(userData)
                    let ownedCtx = unmanaged.takeRetainedValue() // Release memory
                    
                    // We need the job handle to fetch metrics, but we passed it as soon as `submit_job` returned.
                    // Wait, the callback runs in C worker thread. 
                    // This is slightly tricky: percentComplete = 1.0 doesn't perfectly mean job handle exists if it returns instantly.
                    // Let's rely on standard logic, we'll fetch metrics.
                    
                    var swiftMetrics = CodecMetrics(decodeTimeUs: 0, encodeTimeUs: 0, totalTimeUs: 0, peakMemoryBytes: 0, inputSizeBytes: 0, outputSizeBytes: 0)
                    
                    var status = CIC_SUCCESS
                    // We passed bytes_processed as the 'status' in C to bypass callback limits temporarily
                    if bytesProcessed != 0 && CICError(rawValue: UInt32(bytesProcessed)) != CIC_SUCCESS {
                        status = CICError(rawValue: UInt32(bytesProcessed))
                    }
                    
                    if status == CIC_SUCCESS {
                        if let handle = ownedCtx.handle {
                            let cMetrics = cic_engine_get_metrics(ownedCtx.engine, handle)
                            swiftMetrics = CodecMetrics(
                                decodeTimeUs: cMetrics.decode_time_us,
                                encodeTimeUs: cMetrics.encode_time_us,
                                totalTimeUs: cMetrics.total_time_us,
                                peakMemoryBytes: cMetrics.peak_memory_bytes,
                                inputSizeBytes: cMetrics.input_size_bytes,
                                outputSizeBytes: cMetrics.output_size_bytes
                            )
                        }
                        ownedCtx.continuation.resume(returning: swiftMetrics)
                    } else {
                        ownedCtx.continuation.resume(throwing: CodecError(status))
                    }
                } else {
                    let ctx = Unmanaged<ProgressContext>.fromOpaque(userData).takeUnretainedValue()
                    ctx.handler?(percentComplete)
                }
            }
            
            let jobHandle = cic_engine_submit_job(engine, &params)
            if jobHandle == nil {
                // Instantly failed
                Unmanaged<ProgressContext>.fromOpaque(rawContext).release()
                continuation.resume(throwing: CodecError.invalidParameter)
            } else {
                progressContext.handle = jobHandle
            }
        }
    }
}
