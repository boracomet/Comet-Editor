# Design Document: CometImageCodec

## Overview

CometImageCodec is a high-performance, zero-dependency image codec engine for macOS 13+ that provides native encoding and decoding for modern image formats (WebP, AVIF). The system is architected as a pure C core engine with a Swift bridging layer, emphasizing performance through SIMD optimizations, multi-threading, and memory-efficient streaming operations.

The design prioritizes:
- **Performance**: SIMD vectorization, multi-threaded batch processing, and optimized memory access patterns
- **Safety**: Static linking for notarization compliance, comprehensive input validation, and thread-safe operations
- **Extensibility**: Pluggable format handler architecture allowing new codecs without core modifications
- **Developer Experience**: Swift-native API with async/await support, automatic memory management, and descriptive error handling

## Architecture

### High-Level Architecture

The system follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│              Swift Application Layer                     │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│         Swift Bridge (CometImageCodec.swift)            │
│  - Swift API exposure                                   │
│  - Error translation                                    │
│  - Memory management (ARC)                              │
│  - Async/await support                                  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              C Core Engine (CICEngine)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │         Format Handler Registry                  │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │   │
│  │  │ CICWebP  │  │ CICAVIF  │  │ Future Codec │  │   │
│  │  └──────────┘  └──────────┘  └──────────────┘  │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │ Thread Pool  │  │ Memory Mgr   │  │ SIMD Layer  │  │
│  └──────────────┘  └──────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│         Statically Linked Codec Libraries                │
│         - libwebp 1.3+                                   │
│         - libavif 1.0+                                   │
└─────────────────────────────────────────────────────────┘
```

### Core Design Principles

1. **C Core with Swift Bridge**: Performance-critical code in C, developer-friendly API in Swift
2. **Static Linking**: All codec libraries embedded at build time for zero runtime dependencies
3. **Universal Binary**: Single executable with native ARM64 and x86_64 code paths
4. **Lock-Free Where Possible**: Minimize contention through lock-free queues and atomic operations
5. **Memory-Mapped I/O**: Efficient handling of large files without excessive memory allocation
6. **Runtime CPU Detection**: Automatic selection of optimal SIMD instruction set

## Components and Interfaces

### 1. CICEngine - Core Codec Engine

The central coordinator that manages all codec operations.

**Responsibilities:**
- Format handler registration and routing
- Conversion job lifecycle management
- Resource coordination (threads, memory)
- Performance metrics collection

**Key Functions:**
```c
// Initialize the engine with configuration
CICEngine* cic_engine_create(CICConfig* config);

// Register a format handler
CICError cic_engine_register_handler(CICEngine* engine, CICFormatHandler* handler);

// Submit a conversion job
CICJobHandle cic_engine_submit_job(CICEngine* engine, CICJobParams* params);

// Submit batch operation
CICBatchHandle cic_engine_submit_batch(CICEngine* engine, CICJobParams* jobs[], size_t count);

// Cancel a job
CICError cic_engine_cancel_job(CICEngine* engine, CICJobHandle handle);

// Query performance metrics
CICMetrics cic_engine_get_metrics(CICEngine* engine, CICJobHandle handle);

// Cleanup
void cic_engine_destroy(CICEngine* engine);
```

**Data Structures:**
```c
typedef struct {
    uint32_t thread_count;        // 0 = auto-detect
    size_t max_memory_mb;         // Memory limit per job
    bool enable_simd;             // Enable SIMD optimizations
    CICLogLevel log_level;        // Logging verbosity
} CICConfig;

typedef struct {
    const char* input_path;       // Input file path
    const char* output_path;      // Output file path
    CICFormat input_format;       // Auto-detect if CIC_FORMAT_AUTO
    CICFormat output_format;      // Target format
    CICQualityParams quality;     // Quality settings
    CICMetadataOptions metadata;  // Metadata handling
    CICProgressCallback progress; // Progress callback
    void* user_data;              // User context
} CICJobParams;
```

### 2. CICFormatHandler - Abstract Format Interface

Pluggable interface for format-specific encoding and decoding.

**Interface Definition:**
```c
typedef struct CICFormatHandler {
    const char* format_name;
    const char* file_extensions[8];  // e.g., {"webp", NULL}
    const uint8_t magic_numbers[16]; // File signature
    size_t magic_length;
    
    // Capability queries
    bool (*supports_lossless)(void);
    bool (*supports_lossy)(void);
    bool (*supports_metadata)(CICMetadataType type);
    
    // Core operations
    CICError (*validate)(const uint8_t* data, size_t size);
    CICError (*decode)(CICDecodeContext* ctx);
    CICError (*encode)(CICEncodeContext* ctx);
    
    // Cleanup
    void (*destroy)(struct CICFormatHandler* handler);
} CICFormatHandler;
```

**Decode Context:**
```c
typedef struct {
    const uint8_t* input_data;
    size_t input_size;
    CICImageBuffer* output_buffer;  // Allocated by handler
    CICMetadata* metadata;          // Optional metadata output
    CICProgressCallback progress;
    void* user_data;
    volatile bool* cancel_flag;
} CICDecodeContext;
```

**Encode Context:**
```c
typedef struct {
    const CICImageBuffer* input_buffer;
    uint8_t** output_data;          // Allocated by handler
    size_t* output_size;
    CICQualityParams quality;
    const CICMetadata* metadata;    // Optional metadata input
    CICProgressCallback progress;
    void* user_data;
    volatile bool* cancel_flag;
} CICEncodeContext;
```

### 3. CICWebP - WebP Format Handler

Implementation of CICFormatHandler for WebP format using libwebp.

**Implementation Details:**
- Links against libwebp 1.3+ (statically compiled)
- Supports both VP8 (lossy) and VP8L (lossless) codecs
- EXIF metadata preservation through libwebp's mux API
- Quality range: 0-100 (100 = lossless mode)

**Key Functions:**
```c
CICFormatHandler* cic_webp_create_handler(void);
```

### 4. CICAVIF - AVIF Format Handler

Implementation of CICFormatHandler for AVIF format using libavif.

**Implementation Details:**
- Links against libavif 1.0+ with AOM encoder/decoder
- Supports 8-bit and 10-bit color depth
- ICC color profile preservation
- Quality range: 0-100 (maps to AV1 QP values)

**Key Functions:**
```c
CICFormatHandler* cic_avif_create_handler(void);
```

### 5. CICThreadPool - Multi-Threading Management

Lock-free thread pool for parallel job processing.

**Design:**
- Worker threads created at engine initialization
- Lock-free MPMC queue for job distribution
- Thread count defaults to logical CPU core count
- Work-stealing for load balancing

**Key Functions:**
```c
CICThreadPool* cic_threadpool_create(uint32_t thread_count);
void cic_threadpool_submit(CICThreadPool* pool, CICWorkItem* item);
void cic_threadpool_wait_all(CICThreadPool* pool);
void cic_threadpool_destroy(CICThreadPool* pool);
```

**Data Structures:**
```c
typedef struct {
    void (*function)(void* arg);
    void* argument;
    volatile bool* cancel_flag;
} CICWorkItem;
```

### 6. CICMemory - Memory Management System

Centralized memory allocation with tracking and leak detection.

**Features:**
- Thread-local allocation pools for reduced contention
- Allocation tracking in debug builds
- Automatic cleanup on job completion
- Memory usage statistics

**Key Functions:**
```c
void* cic_malloc(size_t size);
void* cic_calloc(size_t count, size_t size);
void* cic_realloc(void* ptr, size_t new_size);
void cic_free(void* ptr);

// Memory tracking
CICMemoryStats cic_memory_get_stats(void);
void cic_memory_reset_stats(void);

// Job-scoped allocations
CICMemoryScope* cic_memory_scope_create(void);
void cic_memory_scope_destroy(CICMemoryScope* scope);  // Frees all allocations
```

**Data Structures:**
```c
typedef struct {
    size_t current_usage;
    size_t peak_usage;
    size_t allocation_count;
    size_t deallocation_count;
} CICMemoryStats;
```

### 7. CICSIMD - SIMD Optimization Layer

Runtime CPU detection and SIMD operation dispatcher.

**Supported Instruction Sets:**
- ARM NEON (Apple Silicon)
- Intel SSE4.2 (Intel Macs)
- Scalar fallback (all platforms)

**Key Operations:**
- RGB to YUV color space conversion
- YUV to RGB color space conversion
- Pixel format conversions (RGBA, BGRA, RGB, etc.)
- Alpha premultiplication/unpremultiplication

**Key Functions:**
```c
// Initialize and detect CPU capabilities
void cic_simd_init(void);
CICCPUFeatures cic_simd_get_features(void);

// Color space conversions (dispatched to optimal implementation)
void cic_simd_rgb_to_yuv(const uint8_t* rgb, uint8_t* yuv, size_t pixel_count);
void cic_simd_yuv_to_rgb(const uint8_t* yuv, uint8_t* rgb, size_t pixel_count);

// Pixel format conversions
void cic_simd_rgba_to_rgb(const uint8_t* rgba, uint8_t* rgb, size_t pixel_count);
void cic_simd_premultiply_alpha(uint8_t* rgba, size_t pixel_count);
```

**CPU Feature Detection:**
```c
typedef struct {
    bool has_neon;      // ARM NEON
    bool has_sse42;     // Intel SSE4.2
    bool has_avx2;      // Intel AVX2 (future)
} CICCPUFeatures;
```

### 8. CometImageCodec.swift - Swift Bridging Layer

Swift API that wraps the C engine with idiomatic Swift interfaces.

**Key Classes:**

```swift
public final class CometImageCodec {
    public init(configuration: Configuration = .default) throws
    
    public func convert(
        input: URL,
        output: URL,
        format: ImageFormat,
        quality: Quality = .default
    ) async throws -> ConversionResult
    
    public func convertBatch(
        jobs: [ConversionJob]
    ) async throws -> [ConversionResult]
    
    public func cancel(_ job: ConversionJob)
}

public struct Configuration {
    public var threadCount: Int?  // nil = auto
    public var maxMemoryMB: Int = 500
    public var enableSIMD: Bool = true
    public var logLevel: LogLevel = .warning
    
    public static let `default` = Configuration()
}

public enum ImageFormat: String {
    case webp
    case avif
    case auto  // Auto-detect from file
}

public struct Quality {
    public var value: Int  // 0-100
    public var lossless: Bool
    
    public static let `default` = Quality(value: 85, lossless: false)
    public static let maximum = Quality(value: 100, lossless: true)
}

public struct ConversionResult {
    public let inputSize: Int
    public let outputSize: Int
    public let processingTime: TimeInterval
    public let format: ImageFormat
}

public enum CodecError: Error {
    case invalidInput(String)
    case unsupportedFormat(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case outOfMemory
    case cancelled
    case invalidDimensions(width: Int, height: Int)
}
```

**Progress Reporting:**
```swift
public struct ConversionProgress {
    public let percentComplete: Double
    public let bytesProcessed: Int
    public let estimatedTimeRemaining: TimeInterval?
}

extension CometImageCodec {
    public func convert(
        input: URL,
        output: URL,
        format: ImageFormat,
        quality: Quality = .default,
        progress: @escaping (ConversionProgress) -> Void
    ) async throws -> ConversionResult
}
```

## Data Models

### Image Buffer Representation

```c
typedef enum {
    CIC_PIXEL_FORMAT_RGB,
    CIC_PIXEL_FORMAT_RGBA,
    CIC_PIXEL_FORMAT_BGR,
    CIC_PIXEL_FORMAT_BGRA,
    CIC_PIXEL_FORMAT_YUV420,
    CIC_PIXEL_FORMAT_YUV444,
} CICPixelFormat;

typedef struct {
    uint32_t width;
    uint32_t height;
    CICPixelFormat format;
    uint8_t bit_depth;        // 8 or 10
    uint8_t* data;
    size_t stride;            // Bytes per row
    size_t data_size;
} CICImageBuffer;
```

### Metadata Structures

```c
typedef enum {
    CIC_METADATA_EXIF,
    CIC_METADATA_ICC_PROFILE,
    CIC_METADATA_XMP,
    CIC_METADATA_ORIENTATION,
} CICMetadataType;

typedef struct {
    CICMetadataType type;
    uint8_t* data;
    size_t size;
} CICMetadataItem;

typedef struct {
    CICMetadataItem* items;
    size_t count;
} CICMetadata;

typedef enum {
    CIC_METADATA_PRESERVE,    // Keep all metadata
    CIC_METADATA_STRIP,       // Remove all metadata
    CIC_METADATA_MINIMAL,     // Keep only orientation and color profile
} CICMetadataOptions;
```

### Error Codes

```c
typedef enum {
    CIC_SUCCESS = 0,
    CIC_ERROR_INVALID_PARAMETER,
    CIC_ERROR_OUT_OF_MEMORY,
    CIC_ERROR_UNSUPPORTED_FORMAT,
    CIC_ERROR_DECODE_FAILED,
    CIC_ERROR_ENCODE_FAILED,
    CIC_ERROR_FILE_NOT_FOUND,
    CIC_ERROR_FILE_READ_FAILED,
    CIC_ERROR_FILE_WRITE_FAILED,
    CIC_ERROR_INVALID_DIMENSIONS,
    CIC_ERROR_CORRUPTED_DATA,
    CIC_ERROR_CANCELLED,
    CIC_ERROR_RESOURCE_LIMIT,
    CIC_ERROR_UNKNOWN_FORMAT,
} CICError;
```

### Performance Metrics

```c
typedef struct {
    uint64_t decode_time_us;      // Microseconds
    uint64_t encode_time_us;
    uint64_t total_time_us;
    size_t peak_memory_bytes;
    size_t input_size_bytes;
    size_t output_size_bytes;
    uint32_t thread_count_used;
} CICMetrics;
```


## Technical Decisions and Rationale

### 1. C Core with Swift Bridge

**Decision:** Implement the core engine in C with a Swift wrapper layer.

**Rationale:**
- C provides direct control over memory layout and SIMD intrinsics
- Easier integration with existing codec libraries (libwebp, libavif)
- Predictable performance characteristics without runtime overhead
- Swift bridge provides modern API without compromising core performance
- Clear separation allows optimization of hot paths in C while maintaining Swift ergonomics

### 2. Static Linking of Codec Libraries

**Decision:** Statically link libwebp 1.3+ and libavif 1.0+ at build time.

**Rationale:**
- Eliminates runtime dependencies for easier deployment
- Satisfies macOS notarization requirements
- Ensures version consistency across deployments
- Avoids dynamic library loading overhead
- Simplifies distribution (single binary)

**Trade-offs:**
- Larger binary size (~2-3 MB additional)
- Must rebuild to update codec libraries
- Acceptable given deployment simplicity and notarization benefits

### 3. SIMD Optimization Strategy

**Decision:** Use ARM NEON for Apple Silicon and SSE4.2 for Intel with runtime detection.

**Rationale:**
- NEON available on all Apple Silicon Macs
- SSE4.2 available on all Intel Macs from 2008+
- Runtime detection allows single universal binary
- 2-4x performance improvement for color space conversions
- Scalar fallback ensures correctness on all platforms

**Implementation:**
- Use compiler intrinsics for portability
- Process pixels in batches of 4 (NEON) or 4 (SSE)
- Align buffers to 16-byte boundaries for optimal performance

### 4. Lock-Free Thread Pool

**Decision:** Implement thread pool using lock-free MPMC queue.

**Rationale:**
- Eliminates mutex contention in job submission
- Better scalability with high job submission rates
- Reduced latency for job dispatch
- Work-stealing prevents idle threads

**Implementation:**
- Use atomic operations for queue management
- Chase-Lev work-stealing deque per thread
- Fallback to mutex-based queue if atomics unavailable

### 5. Memory-Mapped I/O for Large Files

**Decision:** Use mmap() for files larger than 8MB.

**Rationale:**
- Reduces memory pressure for large images
- Leverages OS page cache efficiently
- Avoids large malloc() allocations
- Streaming access pattern for decode operations

**Threshold:**
- Files < 8MB: Read into memory buffer
- Files ≥ 8MB: Memory-map and stream
- Configurable threshold via CICConfig

### 6. Format Detection Strategy

**Decision:** Detect format using magic number inspection (first 64 bytes).

**Rationale:**
- More reliable than file extension
- Fast (no full file read required)
- Handles misnamed files correctly
- Standard practice for image libraries

**Magic Numbers:**
- WebP: "RIFF" + "WEBP" at offset 8
- AVIF: "ftyp" + "avif" or "avis" at offset 4

### 7. Error Handling Approach

**Decision:** C error codes with Swift Error translation.

**Rationale:**
- C error codes are lightweight and predictable
- Swift Error provides rich context and localization
- Bridge layer enriches errors with file paths and details
- Allows graceful degradation in batch operations

### 8. Quality Parameter Mapping

**Decision:** Unified 0-100 quality scale across formats.

**Rationale:**
- Consistent API regardless of format
- Quality 100 = lossless (if supported)
- Maps to format-specific parameters internally:
  - WebP: Direct quality parameter
  - AVIF: Maps to QP values (0-63 scale)

**Mapping:**
```
Quality 0-100 → AVIF QP 63-0 (inverted)
QP = 63 - (quality * 63 / 100)
```

### 9. Thread Count Strategy

**Decision:** Default to logical CPU core count, allow override.

**Rationale:**
- Maximizes throughput on modern multi-core systems
- Prevents over-subscription by default
- Allows tuning for specific workloads
- Single-threaded mode available for debugging

**Detection:**
```c
#ifdef __APPLE__
    sysctlbyname("hw.logicalcpu", &count, &size, NULL, 0);
#endif
```

### 10. Build System Integration

**Decision:** Use Xcode build phases to compile codec libraries from source.

**Rationale:**
- Full control over compilation flags
- Ensures universal binary for codec libraries
- Reproducible builds
- Easier debugging with source access

**Build Process:**
1. Download codec library sources (via git submodules)
2. Configure with CMake for universal binary
3. Compile with optimization flags (-O3, -flto)
4. Link statically into main project
5. Verify no dynamic dependencies (otool -L)


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Reflection

After analyzing all acceptance criteria, I identified several areas of redundancy that need consolidation:

**Redundancy Analysis:**

1. **Metadata Preservation**: Requirements 1.5, 2.5, 16.1, and 16.2 all test metadata round-trip preservation. These can be consolidated into a single comprehensive property covering all metadata types (EXIF, ICC profiles).

2. **Format Detection**: Requirements 17.1 and 17.2 both test that format detection works. These can be combined into one property.

3. **Error Handling**: Requirements 11.1 and 11.5 both test error code mapping. These overlap and can be consolidated.

4. **Thread Safety**: Requirements 10.1, 10.2, and 10.3 all test thread-safe concurrent operations. These can be combined into one comprehensive concurrency property.

5. **Memory Cleanup**: Requirements 13.1, 13.2, and 13.5 all test memory deallocation. These can be consolidated into a single memory leak property.

6. **Cancellation**: Requirements 18.1, 18.2, and 18.3 all test cancellation behavior. These can be combined into one property.

7. **Quality Parameter Handling**: Requirements 1.2 and 2.2 test the same behavior for different formats. These can be combined into one property covering all formats.

8. **Invalid Input Handling**: Requirements 1.3 and 2.3 test error handling for invalid files. These can be combined into one property.

9. **Progress Reporting**: Requirements 19.1, 19.2, and 19.3 all test progress callback behavior. These can be consolidated.

10. **Encoding/Decoding Success**: Requirements 1.1, 2.1 test basic decode functionality. These can be combined into one property covering all formats.

### Property 1: Format Decode Success

*For any* valid image file in a supported format (WebP, AVIF), decoding should produce an uncompressed image buffer with correct dimensions and pixel data.

**Validates: Requirements 1.1, 2.1**

### Property 2: Format Encode with Quality Range

*For any* uncompressed image buffer and any quality value in the range [0, 100], encoding to a supported format (WebP, AVIF) should succeed and produce valid output.

**Validates: Requirements 1.2, 2.2, 14.1**

### Property 3: Invalid Input Error Handling

*For any* corrupted or invalid image file, the format handler should return a descriptive error code without crashing or hanging.

**Validates: Requirements 1.3, 2.3, 15.1, 15.4**

### Property 4: Compression Mode Support

*For any* supported format, encoding with quality < 100 should use lossy compression, and encoding with quality = 100 should use lossless compression (if the format supports it).

**Validates: Requirements 1.4, 14.2**

### Property 5: Metadata Round-Trip Preservation

*For any* image with metadata (EXIF, ICC profile, orientation), encoding then decoding should preserve the metadata unless explicitly stripped.

**Validates: Requirements 1.5, 2.5, 16.1, 16.2, 16.5**

### Property 6: Bit Depth Support

*For any* supported bit depth (8-bit, 10-bit), encoding to AVIF should succeed and preserve the bit depth in the output.

**Validates: Requirements 2.4**

### Property 7: Parallel Job Distribution

*For any* batch of conversion jobs where count > thread_count, the thread pool should execute jobs in parallel with total execution time significantly less than sequential execution time.

**Validates: Requirements 4.1, 4.5**

### Property 8: Thread-Safe Concurrent Operations

*For any* set of concurrent conversion jobs submitted from multiple threads, all jobs should complete successfully without data corruption or race conditions.

**Validates: Requirements 10.1, 10.2, 10.3, 4.4**

### Property 9: Memory Usage Bounds

*For any* image or batch of images, peak memory usage should not exceed the configured limit (500MB per job for large images, 500MB total for batches of 10+).

**Validates: Requirements 5.1, 5.4**

### Property 10: Memory Cleanup After Completion

*For any* completed or cancelled conversion job, all allocated memory should be deallocated, with allocation count equaling deallocation count.

**Validates: Requirements 13.1, 13.2, 13.3, 13.5, 5.5**

### Property 11: SIMD Fallback Correctness

*For any* image conversion operation, disabling SIMD optimizations should produce identical output to SIMD-enabled conversion (verifying scalar fallback correctness).

**Validates: Requirements 6.5**

### Property 12: Error Propagation to Swift

*For any* C error code generated by the codec engine, the Swift bridge should propagate a corresponding Swift Error with descriptive message.

**Validates: Requirements 7.2, 7.5, 11.5**

### Property 13: Swift Memory Management

*For any* sequence of Swift API calls creating and destroying codec objects, no memory leaks should occur (verified by ARC).

**Validates: Requirements 7.4**

### Property 14: Format Handler Registration

*For any* format handler registered with the engine, subsequent conversion jobs for that format should be routed to the registered handler.

**Validates: Requirements 8.2, 8.3**

### Property 15: Format Auto-Detection

*For any* supported image file, automatic format detection should correctly identify the format based on magic numbers, even if the file extension is incorrect or missing.

**Validates: Requirements 17.1, 17.2, 17.3**

### Property 16: Format Detection Failure Handling

*For any* file with unrecognized format, format detection should return an unknown format error without attempting to decode.

**Validates: Requirements 17.4**

### Property 17: Error Message Completeness

*For any* conversion job failure, the error message should contain the file path, format type, and specific failure reason.

**Validates: Requirements 11.2, 11.4**

### Property 18: Out-of-Memory Error Handling

*For any* memory allocation failure scenario, the memory manager should return an out-of-memory error code without crashing.

**Validates: Requirements 11.3**

### Property 19: Performance Metrics Collection

*For any* completed conversion job, performance metrics should be available including total time, decode time, encode time, peak memory, input size, and output size.

**Validates: Requirements 12.1, 12.2, 12.5**

### Property 20: Batch Aggregate Metrics

*For any* completed batch operation, aggregate statistics should be available including average time per image and total processing time.

**Validates: Requirements 12.4**

### Property 21: Quality Parameter Validation

*For any* quality value outside the range [0, 100], the codec engine should return an invalid parameter error.

**Validates: Requirements 14.4**

### Property 22: Dimension Validation

*For any* image file claiming dimensions exceeding 65535x65535 pixels, the format handler should reject it with an invalid dimension error.

**Validates: Requirements 15.2** (edge case)

### Property 23: Resource Limit Validation

*For any* file claiming a size larger than available system memory, the codec engine should reject it with a resource limit error before attempting allocation.

**Validates: Requirements 15.3** (edge case)

### Property 24: Metadata Stripping

*For any* image with metadata, encoding with the strip metadata option should produce output without any metadata.

**Validates: Requirements 16.3**

### Property 25: Incompatible Metadata Handling

*For any* conversion where source metadata is incompatible with the target format, the conversion should succeed (with metadata omitted) rather than fail.

**Validates: Requirements 16.4**

### Property 26: Job Cancellation

*For any* in-progress conversion job, calling cancel should stop the job and release all associated resources.

**Validates: Requirements 18.1, 18.2, 18.3**

### Property 27: Batch Cancellation

*For any* batch operation, cancelling the batch should cancel all pending and in-progress jobs.

**Validates: Requirements 18.5**

### Property 28: Progress Callback Invocation

*For any* conversion job with a progress callback, the callback should be invoked multiple times during processing with increasing percentage values and required fields (percentage, bytes processed, estimated time).

**Validates: Requirements 19.1, 19.2, 19.3**


## Error Handling

### Error Handling Strategy

The codec engine uses a layered error handling approach:

1. **C Layer**: Integer error codes with detailed context
2. **Swift Layer**: Rich Error types with localized messages
3. **Graceful Degradation**: Non-fatal errors (e.g., metadata incompatibility) log warnings but allow operations to continue

### Error Categories

```c
typedef enum {
    CIC_ERROR_CATEGORY_INPUT,      // Invalid input data
    CIC_ERROR_CATEGORY_RESOURCE,   // Memory/file system issues
    CIC_ERROR_CATEGORY_FORMAT,     // Format-specific errors
    CIC_ERROR_CATEGORY_OPERATION,  // Operational errors (cancelled, etc.)
    CIC_ERROR_CATEGORY_SYSTEM,     // System-level errors
} CICErrorCategory;
```

### Error Context

Each error includes:
- **Error Code**: Specific error identifier
- **Category**: High-level error classification
- **Message**: Human-readable description
- **File Path**: Path to the file being processed (if applicable)
- **Byte Offset**: Location of error in file (for corruption errors)
- **Format**: Image format being processed

```c
typedef struct {
    CICError code;
    CICErrorCategory category;
    char message[256];
    char file_path[1024];
    size_t byte_offset;
    CICFormat format;
} CICErrorContext;
```

### Error Handling Patterns

**Input Validation:**
```c
CICError cic_validate_input(const CICJobParams* params) {
    if (!params) return CIC_ERROR_INVALID_PARAMETER;
    if (!params->input_path) return CIC_ERROR_INVALID_PARAMETER;
    if (!params->output_path) return CIC_ERROR_INVALID_PARAMETER;
    if (params->quality.value < 0 || params->quality.value > 100) {
        return CIC_ERROR_INVALID_PARAMETER;
    }
    return CIC_SUCCESS;
}
```

**Resource Cleanup on Error:**
```c
CICError cic_process_image(CICJobParams* params) {
    CICMemoryScope* scope = cic_memory_scope_create();
    CICImageBuffer* buffer = NULL;
    CICError result = CIC_SUCCESS;
    
    buffer = cic_malloc(sizeof(CICImageBuffer));
    if (!buffer) {
        result = CIC_ERROR_OUT_OF_MEMORY;
        goto cleanup;
    }
    
    // ... processing ...
    
cleanup:
    cic_memory_scope_destroy(scope);  // Frees all allocations
    return result;
}
```

**Swift Error Translation:**
```swift
extension CometImageCodec {
    private func translateError(_ errorContext: CICErrorContext) -> CodecError {
        switch errorContext.code {
        case CIC_ERROR_INVALID_PARAMETER:
            return .invalidInput(String(cString: errorContext.message))
        case CIC_ERROR_OUT_OF_MEMORY:
            return .outOfMemory
        case CIC_ERROR_UNSUPPORTED_FORMAT:
            return .unsupportedFormat(String(cString: errorContext.message))
        case CIC_ERROR_DECODE_FAILED:
            return .decodingFailed(String(cString: errorContext.message))
        case CIC_ERROR_ENCODE_FAILED:
            return .encodingFailed(String(cString: errorContext.message))
        case CIC_ERROR_CANCELLED:
            return .cancelled
        case CIC_ERROR_INVALID_DIMENSIONS:
            let msg = String(cString: errorContext.message)
            return .invalidDimensions(width: 0, height: 0)  // Parse from message
        default:
            return .invalidInput("Unknown error: \(errorContext.code)")
        }
    }
}
```

### Error Recovery

**Batch Operations:**
- Individual job failures don't stop the batch
- Failed jobs return errors in results array
- Successful jobs complete normally
- Batch metrics include success/failure counts

**Metadata Handling:**
- Incompatible metadata generates warnings, not errors
- Conversion continues without metadata
- Logged for debugging purposes

**Cancellation:**
- Treated as a special error case
- Immediate resource cleanup
- No partial output files left behind

## Testing Strategy

### Dual Testing Approach

The testing strategy employs both unit tests and property-based tests to ensure comprehensive coverage:

- **Unit Tests**: Verify specific examples, edge cases, error conditions, and integration points
- **Property Tests**: Verify universal properties across all inputs through randomized testing

Both approaches are complementary and necessary. Unit tests catch concrete bugs and verify specific scenarios, while property tests verify general correctness across a wide input space.

### Property-Based Testing

**Framework Selection:**
- **Swift**: Use [swift-check](https://github.com/typelift/SwiftCheck) for property-based testing
- **C**: Use [theft](https://github.com/silentbicycle/theft) for C-level property tests

**Configuration:**
- Minimum 100 iterations per property test (due to randomization)
- Each test tagged with reference to design document property
- Tag format: `// Feature: comet-image-codec, Property {number}: {property_text}`

**Example Property Test:**
```swift
import SwiftCheck

// Feature: comet-image-codec, Property 2: Format Encode with Quality Range
func testEncodeWithQualityRange() {
    property("Encoding succeeds for all quality values 0-100") <- forAll { (quality: UInt8) in
        let normalizedQuality = Int(quality) % 101  // 0-100
        let codec = try! CometImageCodec()
        let testImage = generateTestImage()
        
        let result = try? codec.convert(
            input: testImage,
            output: tempURL(),
            format: .webp,
            quality: Quality(value: normalizedQuality, lossless: false)
        )
        
        return result != nil
    }
}

// Feature: comet-image-codec, Property 5: Metadata Round-Trip Preservation
func testMetadataRoundTrip() {
    property("Metadata preserved through encode/decode cycle") <- forAll { (metadata: TestMetadata) in
        let codec = try! CometImageCodec()
        let imageWithMetadata = createImageWithMetadata(metadata)
        
        // Encode
        let encoded = try! codec.convert(
            input: imageWithMetadata,
            output: tempURL(),
            format: .webp,
            quality: .default
        )
        
        // Decode and extract metadata
        let decoded = try! codec.decode(encoded.outputURL)
        let extractedMetadata = decoded.metadata
        
        return extractedMetadata.exif == metadata.exif &&
               extractedMetadata.iccProfile == metadata.iccProfile
    }
}

// Feature: comet-image-codec, Property 8: Thread-Safe Concurrent Operations
func testConcurrentOperations() {
    property("Concurrent jobs complete without corruption") <- forAll { (jobCount: UInt8) in
        let count = max(2, Int(jobCount) % 50)  // 2-50 jobs
        let codec = try! CometImageCodec()
        
        let jobs = (0..<count).map { _ in generateRandomJob() }
        
        // Execute concurrently
        let results = try! await withThrowingTaskGroup(of: ConversionResult.self) { group in
            for job in jobs {
                group.addTask {
                    try await codec.convert(
                        input: job.input,
                        output: job.output,
                        format: job.format,
                        quality: job.quality
                    )
                }
            }
            
            var allResults: [ConversionResult] = []
            for try await result in group {
                allResults.append(result)
            }
            return allResults
        }
        
        // Verify all completed and outputs are valid
        return results.count == count && results.allSatisfy { $0.outputSize > 0 }
    }
}
```

**Example C Property Test:**
```c
#include <theft.h>

// Feature: comet-image-codec, Property 10: Memory Cleanup After Completion
static enum theft_trial_res
test_memory_cleanup(struct theft *t, void *arg1) {
    CICEngine* engine = cic_engine_create(NULL);
    CICMemoryStats before = cic_memory_get_stats();
    
    // Generate random job
    CICJobParams* params = generate_random_job_params(t);
    
    // Execute job
    CICJobHandle handle = cic_engine_submit_job(engine, params);
    cic_engine_wait_job(engine, handle);
    
    // Check memory cleanup
    CICMemoryStats after = cic_memory_get_stats();
    
    cic_engine_destroy(engine);
    
    // Verify allocation count equals deallocation count
    return (after.allocation_count == after.deallocation_count) 
        ? THEFT_TRIAL_PASS 
        : THEFT_TRIAL_FAIL;
}
```

### Unit Testing

**Test Categories:**

1. **Format-Specific Tests**
   - WebP lossy encoding
   - WebP lossless encoding
   - AVIF 8-bit encoding
   - AVIF 10-bit encoding
   - Format detection by magic number
   - Invalid file handling

2. **Integration Tests**
   - Swift bridge error translation
   - Async/await interface
   - Progress callback invocation
   - Cancellation through Swift Task

3. **Edge Case Tests**
   - Empty files
   - Single-pixel images
   - Maximum dimension images (65535x65535)
   - Files claiming excessive size
   - Corrupted file headers
   - Missing file extensions

4. **Performance Tests**
   - Decode time for 4096x4096 images
   - Encode time benchmarks
   - Memory usage for large images
   - Thread pool scaling
   - SIMD vs scalar performance

5. **Build Verification Tests**
   - Universal binary architecture check (lipo)
   - No external dynamic dependencies (otool -L)
   - Static library linkage verification
   - Notarization compatibility

**Example Unit Tests:**
```swift
import XCTest

class CometImageCodecTests: XCTestCase {
    
    // Specific example test
    func testWebPLossyEncoding() throws {
        let codec = try CometImageCodec()
        let testImage = loadTestImage("sample.png")
        
        let result = try codec.convert(
            input: testImage,
            output: tempURL(),
            format: .webp,
            quality: Quality(value: 85, lossless: false)
        )
        
        XCTAssertGreaterThan(result.outputSize, 0)
        XCTAssertLessThan(result.outputSize, result.inputSize)  // Compression
    }
    
    // Edge case test
    func testSinglePixelImage() throws {
        let codec = try CometImageCodec()
        let singlePixel = createSinglePixelImage()
        
        let result = try codec.convert(
            input: singlePixel,
            output: tempURL(),
            format: .webp,
            quality: .default
        )
        
        XCTAssertGreaterThan(result.outputSize, 0)
    }
    
    // Error condition test
    func testInvalidDimensions() {
        let codec = try CometImageCodec()
        let oversized = createImageWithDimensions(width: 70000, height: 70000)
        
        XCTAssertThrowsError(try codec.convert(
            input: oversized,
            output: tempURL(),
            format: .webp,
            quality: .default
        )) { error in
            guard case CodecError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error")
                return
            }
        }
    }
    
    // Integration test
    func testAsyncCancellation() async throws {
        let codec = try CometImageCodec()
        let largeImage = loadTestImage("large_sample.png")
        
        let task = Task {
            try await codec.convert(
                input: largeImage,
                output: tempURL(),
                format: .avif,
                quality: .maximum
            )
        }
        
        // Cancel after short delay
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch CodecError.cancelled {
            // Expected
        }
    }
}
```

### Test Coverage Goals

- **Line Coverage**: Minimum 85% for C core engine
- **Branch Coverage**: Minimum 80% for error handling paths
- **Property Coverage**: All 28 correctness properties implemented as property tests
- **Format Coverage**: All supported formats tested with multiple quality settings
- **Concurrency Coverage**: Thread-safety validated with 100+ concurrent operations

### Continuous Integration

**CI Pipeline:**
1. Build universal binary
2. Run unit tests on both Intel and Apple Silicon runners
3. Run property tests (100 iterations per property)
4. Run memory leak detection (Instruments/Valgrind)
5. Run thread sanitizer tests
6. Verify no external dependencies (otool -L)
7. Performance regression tests
8. Generate coverage report

**Performance Benchmarks:**
- Track decode/encode times across commits
- Alert on >10% performance regression
- Maintain benchmark history for trend analysis

