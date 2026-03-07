# Implementation Plan: CometImageCodec

## Overview

This implementation plan breaks down the CometImageCodec feature into discrete coding tasks. The codec engine is implemented as a pure C core with a Swift bridging layer, supporting WebP and AVIF formats with SIMD optimizations, multi-threading, and memory-efficient streaming.

The implementation follows a bottom-up approach: core infrastructure first, then format handlers, then Swift bridge, and finally integration and testing.

## Tasks

- [ ] 1. Set up project structure and build system
  - [x] 1.1 Create C core directory structure and header files
    - Create `CometImageCodec/Core/` directory for C engine
    - Create header files: `cic_engine.h`, `cic_types.h`, `cic_error.h`, `cic_memory.h`
    - Define all core data structures (CICEngine, CICConfig, CICJobParams, CICImageBuffer, CICMetadata, CICError)
    - Define all enums (CICFormat, CICPixelFormat, CICMetadataType, CICErrorCategory)
    - _Requirements: 3.1, 9.1, 20.1_

  - [ ] 1.2 Configure build system for static codec library linking
    - Add git submodules for libwebp 1.3+ and libavif 1.0+
    - Create CMake configuration to build codec libraries as universal binaries
    - Configure Xcode build phases to compile codec libraries with -O3 -flto flags
    - Set up static linking in Xcode project settings
    - _Requirements: 3.1, 3.2, 9.1, 20.1, 20.2_

  - [ ]* 1.3 Create build verification script
    - Write script to verify universal binary architecture using `lipo -info`
    - Write script to verify no external dynamic dependencies using `otool -L`
    - Add script as Xcode build phase
    - _Requirements: 3.4, 9.1, 20.2_

- [ ] 2. Implement memory management system (CICMemory)
  - [ ] 2.1 Implement core memory allocation functions
    - Implement `cic_malloc()`, `cic_calloc()`, `cic_realloc()`, `cic_free()`
    - Add thread-local allocation tracking in debug builds
    - Implement allocation statistics collection (CICMemoryStats)
    - _Requirements: 13.2, 13.5_

  - [ ] 2.2 Implement memory scope management
    - Implement `cic_memory_scope_create()` and `cic_memory_scope_destroy()`
    - Track all allocations within a scope for automatic cleanup
    - Ensure scope destruction frees all associated memory
    - _Requirements: 13.1, 13.3_

  - [ ]* 2.3 Write property test for memory cleanup
    - **Property 10: Memory Cleanup After Completion**
    - **Validates: Requirements 13.1, 13.2, 13.3, 13.5, 5.5**
    - Test that allocation count equals deallocation count after job completion
    - Use theft library for C-level property testing

  - [ ]* 2.4 Write unit tests for memory manager
    - Test allocation and deallocation tracking
    - Test memory scope cleanup
    - Test memory statistics collection
    - Test out-of-memory error handling
    - _Requirements: 13.2, 13.4_

- [ ] 3. Implement SIMD optimization layer (CICSIMD)
  - [ ] 3.1 Implement CPU feature detection
    - Implement `cic_simd_init()` with runtime CPU detection
    - Detect ARM NEON support on Apple Silicon
    - Detect Intel SSE4.2 support on Intel Macs
    - Implement `cic_simd_get_features()` to query capabilities
    - _Requirements: 6.3_

  - [ ] 3.2 Implement SIMD color space conversions
    - Implement ARM NEON version of `cic_simd_rgb_to_yuv()`
    - Implement ARM NEON version of `cic_simd_yuv_to_rgb()`
    - Implement Intel SSE4.2 versions of color space conversions
    - Implement scalar fallback versions
    - Process pixels in vector batches of 4
    - _Requirements: 6.1, 6.2, 6.4, 6.5_

  - [ ] 3.3 Implement SIMD pixel format conversions
    - Implement `cic_simd_rgba_to_rgb()` with SIMD and scalar versions
    - Implement `cic_simd_premultiply_alpha()` with SIMD and scalar versions
    - Ensure 16-byte alignment for optimal performance
    - _Requirements: 6.1, 6.2, 6.5_

  - [ ]* 3.4 Write property test for SIMD fallback correctness
    - **Property 11: SIMD Fallback Correctness**
    - **Validates: Requirements 6.5**
    - Test that SIMD-enabled and SIMD-disabled conversions produce identical output
    - Generate random image buffers and compare results

  - [ ]* 3.5 Write unit tests for SIMD operations
    - Test CPU feature detection on both architectures
    - Test color space conversion accuracy
    - Test pixel format conversion accuracy
    - Benchmark SIMD vs scalar performance
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 4. Implement thread pool (CICThreadPool)
  - [ ] 4.1 Implement lock-free work queue
    - Implement MPMC (multi-producer multi-consumer) queue using atomic operations
    - Implement work-stealing deque per thread
    - Implement `cic_threadpool_create()` with configurable thread count
    - Default thread count to logical CPU core count using `sysctlbyname("hw.logicalcpu")`
    - _Requirements: 4.1, 4.2_

  - [ ] 4.2 Implement worker thread management
    - Create worker threads at pool initialization
    - Implement work-stealing for load balancing
    - Implement `cic_threadpool_submit()` for job submission
    - Implement `cic_threadpool_wait_all()` for synchronization
    - Implement `cic_threadpool_destroy()` for cleanup
    - _Requirements: 4.1, 4.5_

  - [ ] 4.3 Implement thread-safe resource access
    - Use atomic operations for shared state where possible
    - Use mutexes for format handler access serialization
    - Ensure thread-local storage for per-thread data
    - _Requirements: 10.2, 10.3_

  - [ ]* 4.4 Write property test for thread-safe concurrent operations
    - **Property 8: Thread-Safe Concurrent Operations**
    - **Validates: Requirements 10.1, 10.2, 10.3, 4.4**
    - Test concurrent job submissions from multiple threads
    - Verify no data corruption or race conditions
    - Test with 100+ concurrent operations

  - [ ]* 4.5 Write property test for parallel job distribution
    - **Property 7: Parallel Job Distribution**
    - **Validates: Requirements 4.1, 4.5**
    - Test that batch jobs execute in parallel
    - Verify total time is significantly less than sequential execution

  - [ ]* 4.6 Write unit tests for thread pool
    - Test thread pool creation and destruction
    - Test job submission and completion
    - Test work-stealing behavior
    - Test thread count scaling
    - _Requirements: 4.2, 4.5_

- [ ] 5. Implement format handler interface (CICFormatHandler)
  - [ ] 5.1 Define format handler interface structure
    - Define CICFormatHandler struct with function pointers
    - Define CICDecodeContext and CICEncodeContext structs
    - Define capability query functions (supports_lossless, supports_lossy, supports_metadata)
    - Create format handler registry data structure
    - _Requirements: 8.1, 8.4_

  - [ ] 5.2 Implement format handler registry
    - Implement handler registration in CICEngine
    - Implement format routing based on file extension and magic numbers
    - Implement `cic_engine_register_handler()`
    - _Requirements: 8.2, 8.3_

  - [ ] 5.3 Implement format detection by magic numbers
    - Implement magic number detection for WebP ("RIFF" + "WEBP")
    - Implement magic number detection for AVIF ("ftyp" + "avif"/"avis")
    - Read only first 64 bytes for detection
    - Implement fallback to file extension if magic number detection fails
    - _Requirements: 17.1, 17.2, 17.5_

  - [ ]* 5.4 Write property test for format auto-detection
    - **Property 15: Format Auto-Detection**
    - **Validates: Requirements 17.1, 17.2, 17.3**
    - Test format detection with correct and incorrect file extensions
    - Generate test files with various magic numbers

  - [ ]* 5.5 Write property test for format detection failure handling
    - **Property 16: Format Detection Failure Handling**
    - **Validates: Requirements 17.4**
    - Test that unrecognized formats return unknown format error

  - [ ]* 5.6 Write property test for format handler registration
    - **Property 14: Format Handler Registration**
    - **Validates: Requirements 8.2, 8.3**
    - Test that registered handlers are correctly routed to

- [ ] 6. Implement WebP format handler (CICWebP)
  - [ ] 6.1 Implement WebP decoder
    - Link against libwebp 1.3+ static library
    - Implement `cic_webp_decode()` using WebPDecode API
    - Support both VP8 (lossy) and VP8L (lossless) codecs
    - Allocate output buffer and populate CICImageBuffer
    - Handle cancellation via cancel_flag
    - _Requirements: 1.1_

  - [ ] 6.2 Implement WebP encoder
    - Implement `cic_webp_encode()` using WebPEncode API
    - Support quality range 0-100 (100 = lossless mode)
    - Support both lossy and lossless compression modes
    - Allocate output buffer and return encoded data
    - Handle cancellation via cancel_flag
    - _Requirements: 1.2, 1.4_

  - [ ] 6.3 Implement WebP metadata handling
    - Use libwebp's mux API for EXIF metadata preservation
    - Implement metadata extraction during decode
    - Implement metadata embedding during encode
    - Support metadata stripping option
    - _Requirements: 1.5, 16.1, 16.3_

  - [ ] 6.4 Implement WebP input validation
    - Validate WebP file headers before processing
    - Validate dimensions (reject > 65535x65535)
    - Validate chunk sizes to prevent buffer overflows
    - Return descriptive error codes for invalid files
    - _Requirements: 1.3, 15.1, 15.2, 15.4_

  - [ ]* 6.5 Write property test for WebP decode success
    - **Property 1: Format Decode Success**
    - **Validates: Requirements 1.1**
    - Test decoding of valid WebP files produces correct dimensions

  - [ ]* 6.6 Write property test for WebP encode with quality range
    - **Property 2: Format Encode with Quality Range**
    - **Validates: Requirements 1.2, 14.1**
    - Test encoding succeeds for all quality values 0-100

  - [ ]* 6.7 Write property test for invalid input error handling
    - **Property 3: Invalid Input Error Handling**
    - **Validates: Requirements 1.3, 15.1, 15.4**
    - Test that corrupted files return errors without crashing

  - [ ]* 6.8 Write property test for compression mode support
    - **Property 4: Compression Mode Support**
    - **Validates: Requirements 1.4, 14.2**
    - Test that quality < 100 uses lossy, quality = 100 uses lossless

  - [ ]* 6.9 Write property test for metadata round-trip preservation
    - **Property 5: Metadata Round-Trip Preservation**
    - **Validates: Requirements 1.5, 16.1, 16.5**
    - Test that EXIF metadata is preserved through encode/decode cycle

  - [ ]* 6.10 Write unit tests for WebP handler
    - Test WebP lossy encoding with various quality settings
    - Test WebP lossless encoding
    - Test invalid WebP file handling
    - Test metadata preservation and stripping
    - Test dimension validation
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 7. Implement AVIF format handler (CICAVIF)
  - [ ] 7.1 Implement AVIF decoder
    - Link against libavif 1.0+ with AOM decoder static library
    - Implement `cic_avif_decode()` using avifDecoder API
    - Support 8-bit and 10-bit color depth
    - Allocate output buffer and populate CICImageBuffer
    - Handle cancellation via cancel_flag
    - _Requirements: 2.1, 2.4_

  - [ ] 7.2 Implement AVIF encoder
    - Implement `cic_avif_encode()` using avifEncoder API with AOM encoder
    - Support quality range 0-100 (map to AV1 QP values: QP = 63 - (quality * 63 / 100))
    - Support 8-bit and 10-bit color depth encoding
    - Allocate output buffer and return encoded data
    - Handle cancellation via cancel_flag
    - _Requirements: 2.2, 2.4_

  - [ ] 7.3 Implement AVIF metadata handling
    - Implement ICC color profile preservation during decode
    - Implement ICC color profile embedding during encode
    - Support metadata stripping option
    - Handle incompatible metadata gracefully (log warning, continue)
    - _Requirements: 2.5, 16.2, 16.3, 16.4_

  - [ ] 7.4 Implement AVIF input validation
    - Validate AVIF file headers before processing
    - Validate dimensions (reject > 65535x65535)
    - Validate chunk sizes to prevent buffer overflows
    - Return descriptive error codes for invalid files
    - _Requirements: 2.3, 15.1, 15.2, 15.4_

  - [ ]* 7.5 Write property test for AVIF decode success
    - **Property 1: Format Decode Success**
    - **Validates: Requirements 2.1**
    - Test decoding of valid AVIF files produces correct dimensions

  - [ ]* 7.6 Write property test for AVIF encode with quality range
    - **Property 2: Format Encode with Quality Range**
    - **Validates: Requirements 2.2, 14.1**
    - Test encoding succeeds for all quality values 0-100

  - [ ]* 7.7 Write property test for bit depth support
    - **Property 6: Bit Depth Support**
    - **Validates: Requirements 2.4**
    - Test that 8-bit and 10-bit encoding preserves bit depth

  - [ ]* 7.8 Write property test for AVIF metadata preservation
    - **Property 5: Metadata Round-Trip Preservation**
    - **Validates: Requirements 2.5, 16.2, 16.5**
    - Test that ICC profiles are preserved through encode/decode cycle

  - [ ]* 7.9 Write property test for incompatible metadata handling
    - **Property 25: Incompatible Metadata Handling**
    - **Validates: Requirements 16.4**
    - Test that conversion succeeds when metadata is incompatible

  - [ ]* 7.10 Write unit tests for AVIF handler
    - Test AVIF 8-bit encoding with various quality settings
    - Test AVIF 10-bit encoding
    - Test invalid AVIF file handling
    - Test ICC profile preservation and stripping
    - Test dimension validation
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 8. Implement core engine (CICEngine)
  - [ ] 8.1 Implement engine initialization and configuration
    - Implement `cic_engine_create()` with CICConfig parameter
    - Initialize thread pool with configured thread count
    - Initialize memory manager
    - Initialize SIMD layer
    - Register default format handlers (WebP, AVIF)
    - _Requirements: 4.2, 6.3_

  - [ ] 8.2 Implement single job submission and processing
    - Implement `cic_engine_submit_job()` for single conversion jobs
    - Implement job lifecycle management (queued, processing, completed, failed)
    - Route jobs to appropriate format handler based on format detection
    - Implement file I/O (read input, write output)
    - Implement memory-mapped I/O for files >= 8MB
    - _Requirements: 5.1, 5.2, 5.3, 17.3_

  - [ ] 8.3 Implement batch job submission and processing
    - Implement `cic_engine_submit_batch()` for multiple jobs
    - Submit batch jobs to thread pool for parallel processing
    - Collect results from all jobs
    - Implement memory limit enforcement for batches (500MB total for 10+ images)
    - _Requirements: 4.1, 4.3, 5.4_

  - [ ] 8.4 Implement job cancellation
    - Implement `cic_engine_cancel_job()` for single jobs
    - Set cancel_flag for in-progress jobs
    - Stop processing within 100ms of cancellation
    - Release all resources immediately
    - _Requirements: 18.1, 18.2, 18.3_

  - [ ] 8.5 Implement performance metrics collection
    - Track decode time, encode time, total time in microseconds
    - Track peak memory usage per job
    - Track input and output sizes
    - Implement `cic_engine_get_metrics()` to query metrics
    - _Requirements: 12.1, 12.2, 12.3, 12.5_

  - [ ] 8.6 Implement progress reporting
    - Invoke progress callback at least every 100ms during processing
    - Include percentage complete, bytes processed, estimated time remaining
    - Add less than 2% overhead to conversion time
    - _Requirements: 19.1, 19.2, 19.5_

  - [ ] 8.7 Implement error handling and context
    - Create CICErrorContext with detailed error information
    - Include file path, format, byte offset in error context
    - Implement error category classification
    - Implement resource cleanup on error paths
    - _Requirements: 11.1, 11.2, 11.4_

  - [ ] 8.8 Implement input validation
    - Validate all job parameters before processing
    - Validate quality range (0-100)
    - Validate file paths exist and are readable
    - Validate dimensions don't exceed limits
    - Validate file size doesn't exceed available memory
    - _Requirements: 14.4, 15.1, 15.2, 15.3_

  - [ ] 8.9 Implement engine cleanup
    - Implement `cic_engine_destroy()` to clean up all resources
    - Wait for all pending jobs to complete
    - Destroy thread pool
    - Release all memory
    - _Requirements: 13.1, 13.5_

  - [ ]* 8.10 Write property test for memory usage bounds
    - **Property 9: Memory Usage Bounds**
    - **Validates: Requirements 5.1, 5.4**
    - Test that peak memory doesn't exceed configured limits

  - [ ]* 8.11 Write property test for job cancellation
    - **Property 26: Job Cancellation**
    - **Validates: Requirements 18.1, 18.2, 18.3**
    - Test that cancellation stops jobs and releases resources

  - [ ]* 8.12 Write property test for batch cancellation
    - **Property 27: Batch Cancellation**
    - **Validates: Requirements 18.5**
    - Test that batch cancellation cancels all jobs

  - [ ]* 8.13 Write property test for progress callback invocation
    - **Property 28: Progress Callback Invocation**
    - **Validates: Requirements 19.1, 19.2, 19.3**
    - Test that progress callbacks are invoked with increasing percentages

  - [ ]* 8.14 Write property test for quality parameter validation
    - **Property 21: Quality Parameter Validation**
    - **Validates: Requirements 14.4**
    - Test that invalid quality values return errors

  - [ ]* 8.15 Write property test for dimension validation
    - **Property 22: Dimension Validation**
    - **Validates: Requirements 15.2**
    - Test that excessive dimensions are rejected

  - [ ]* 8.16 Write property test for resource limit validation
    - **Property 23: Resource Limit Validation**
    - **Validates: Requirements 15.3**
    - Test that files exceeding available memory are rejected

  - [ ]* 8.17 Write property test for performance metrics collection
    - **Property 19: Performance Metrics Collection**
    - **Validates: Requirements 12.1, 12.2, 12.5**
    - Test that all metrics are collected and available

  - [ ]* 8.18 Write property test for batch aggregate metrics
    - **Property 20: Batch Aggregate Metrics**
    - **Validates: Requirements 12.4**
    - Test that batch statistics are correctly aggregated

  - [ ]* 8.19 Write property test for metadata stripping
    - **Property 24: Metadata Stripping**
    - **Validates: Requirements 16.3**
    - Test that strip option removes all metadata

  - [ ]* 8.20 Write unit tests for core engine
    - Test engine initialization and configuration
    - Test single job submission and completion
    - Test batch job processing
    - Test error handling and recovery
    - Test file I/O and memory-mapped I/O
    - _Requirements: 5.1, 5.2, 5.3, 11.1, 11.2_

- [ ] 9. Checkpoint - Ensure C core engine tests pass
  - Ensure all C core engine tests pass, ask the user if questions arise.

- [ ] 10. Implement Swift bridging layer (CometImageCodec.swift)
  - [ ] 10.1 Create Swift module structure and bridging header
    - Create `CometImageCodec.swift` file
    - Create bridging header to expose C API to Swift
    - Import all C headers (cic_engine.h, cic_types.h, cic_error.h)
    - _Requirements: 7.1_

  - [ ] 10.2 Implement Swift data types and enums
    - Define `Configuration` struct with Swift-native types
    - Define `ImageFormat` enum (webp, avif, auto)
    - Define `Quality` struct with value and lossless properties
    - Define `ConversionResult` struct with metrics
    - Define `ConversionProgress` struct for progress reporting
    - _Requirements: 7.1_

  - [ ] 10.3 Implement Swift error types
    - Define `CodecError` enum with all error cases
    - Map error cases to C error codes
    - Implement descriptive error messages
    - _Requirements: 7.2, 11.5_

  - [ ] 10.4 Implement CometImageCodec class initialization
    - Implement `init(configuration:)` that calls `cic_engine_create()`
    - Convert Swift Configuration to C CICConfig
    - Handle initialization errors
    - Implement `deinit` that calls `cic_engine_destroy()`
    - _Requirements: 7.1, 7.4_

  - [ ] 10.5 Implement async convert method
    - Implement `convert(input:output:format:quality:)` async method
    - Call `cic_engine_submit_job()` from Swift
    - Use Swift concurrency to await job completion
    - Translate C error codes to Swift errors
    - Return ConversionResult with metrics
    - _Requirements: 7.3_

  - [ ] 10.6 Implement async convert with progress reporting
    - Implement `convert(input:output:format:quality:progress:)` variant
    - Bridge C progress callback to Swift closure
    - Create ConversionProgress from C callback data
    - Invoke Swift progress closure on main thread
    - _Requirements: 19.4_

  - [ ] 10.7 Implement batch conversion method
    - Implement `convertBatch(jobs:)` async method
    - Call `cic_engine_submit_batch()` from Swift
    - Collect all results and return array
    - Handle individual job failures gracefully
    - _Requirements: 4.3_

  - [ ] 10.8 Implement cancellation support
    - Implement `cancel(_:)` method that calls `cic_engine_cancel_job()`
    - Support Swift Task cancellation in async methods
    - Check Task.isCancelled and propagate to C engine
    - _Requirements: 18.4_

  - [ ] 10.9 Implement error translation
    - Implement `translateError(_:)` method to convert CICErrorContext to CodecError
    - Extract file path, format, and message from C error context
    - Parse dimension values from error messages where needed
    - Ensure error propagation completes within 1ms
    - _Requirements: 7.2, 7.5, 11.5_

  - [ ]* 10.10 Write property test for error propagation to Swift
    - **Property 12: Error Propagation to Swift**
    - **Validates: Requirements 7.2, 7.5, 11.5**
    - Test that all C error codes map to Swift errors

  - [ ]* 10.11 Write property test for Swift memory management
    - **Property 13: Swift Memory Management**
    - **Validates: Requirements 7.4**
    - Test that no memory leaks occur through ARC

  - [ ]* 10.12 Write property test for error message completeness
    - **Property 17: Error Message Completeness**
    - **Validates: Requirements 11.2, 11.4**
    - Test that error messages contain file path, format, and reason

  - [ ]* 10.13 Write property test for out-of-memory error handling
    - **Property 18: Out-of-Memory Error Handling**
    - **Validates: Requirements 11.3**
    - Test that OOM errors are returned without crashing

  - [ ]* 10.14 Write unit tests for Swift bridge
    - Test Swift API initialization and cleanup
    - Test async/await conversion interface
    - Test error translation from C to Swift
    - Test progress reporting through Swift closures
    - Test Task cancellation integration
    - Test batch conversion API
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 11. Integration and end-to-end testing
  - [ ] 11.1 Create test image assets
    - Create test images in various formats (PNG, JPEG for input)
    - Create test images with EXIF metadata
    - Create test images with ICC color profiles
    - Create test images at various sizes (small, medium, large, very large)
    - Create corrupted test files for error handling tests
    - _Requirements: 1.1, 2.1, 16.1, 16.2_

  - [ ] 11.2 Write end-to-end conversion tests
    - Test PNG to WebP conversion
    - Test PNG to AVIF conversion
    - Test WebP to AVIF conversion
    - Test AVIF to WebP conversion
    - Test conversion with various quality settings
    - Test lossless conversion
    - _Requirements: 1.1, 1.2, 2.1, 2.2_

  - [ ] 11.3 Write end-to-end metadata preservation tests
    - Test EXIF preservation through WebP conversion
    - Test ICC profile preservation through AVIF conversion
    - Test metadata stripping option
    - Test orientation metadata handling
    - _Requirements: 1.5, 2.5, 16.1, 16.2, 16.3, 16.5_

  - [ ] 11.4 Write performance benchmark tests
    - Benchmark decode time for 4096x4096 images (target: <100ms WebP, <150ms AVIF)
    - Benchmark encode time for various quality settings
    - Benchmark memory usage for large images
    - Benchmark thread pool scaling with batch operations
    - Benchmark SIMD vs scalar performance (expect 2-4x improvement)
    - Track performance across commits for regression detection
    - _Requirements: 1.1, 2.1, 6.1, 6.2, 12.1_

  - [ ] 11.5 Write stress and fuzzing tests
    - Fuzz test with 10000 malformed files (verify no crashes)
    - Stress test with 1000 sequential conversions (verify no memory leaks)
    - Stress test with 100 concurrent conversions (verify thread safety)
    - Test with maximum dimension images (65535x65535)
    - Test with single-pixel images
    - Test with empty files
    - _Requirements: 10.4, 13.4, 15.5_

  - [ ]* 11.6 Write integration tests for Swift async/await
    - Test async conversion with Task cancellation
    - Test concurrent async conversions
    - Test progress reporting through async sequences
    - Test error handling in async context
    - _Requirements: 7.3, 18.4_

- [ ] 12. Checkpoint - Ensure all integration tests pass
  - Ensure all integration tests pass, ask the user if questions arise.

- [ ] 13. Build system finalization and verification
  - [ ] 13.1 Verify universal binary architecture
    - Run `lipo -info` on built binary to verify both x86_64 and arm64 slices
    - Verify binary runs natively on both Intel and Apple Silicon
    - _Requirements: 9.1, 9.3, 9.4_

  - [ ] 13.2 Verify static linking and dependencies
    - Run `otool -L` to verify no external dynamic dependencies (except system frameworks)
    - Verify libwebp and libavif are statically linked
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ] 13.3 Verify notarization compatibility
    - Ensure binary passes macOS notarization requirements
    - Verify no code signing warnings
    - _Requirements: 9.5_

  - [ ] 13.4 Create build report generation
    - Generate report listing all embedded codec libraries and versions
    - Include build configuration and optimization flags
    - _Requirements: 20.5_

  - [ ]* 13.5 Write build verification tests
    - Test that universal binary contains both architectures
    - Test that no external dependencies exist
    - Test that codec libraries are correctly linked
    - _Requirements: 3.4, 9.1, 20.2_

- [ ] 14. Documentation and final polish
  - [ ] 14.1 Document Swift API with DocC comments
    - Add documentation comments to all public Swift types and methods
    - Include usage examples in documentation
    - Document error cases and edge cases
    - _Requirements: 7.1_

  - [ ] 14.2 Create usage examples
    - Create example Swift code for basic conversion
    - Create example for batch conversion
    - Create example for progress reporting
    - Create example for error handling
    - _Requirements: 7.1_

  - [ ] 14.3 Verify test coverage goals
    - Verify line coverage >= 85% for C core engine
    - Verify branch coverage >= 80% for error handling
    - Verify all 28 correctness properties have property tests
    - Generate coverage report
    - _Requirements: All_

- [ ] 15. Final checkpoint - Complete verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- Property tests validate universal correctness properties (minimum 100 iterations each)
- Unit tests validate specific examples, edge cases, and integration points
- The C core is implemented first, followed by format handlers, then Swift bridge
- Build system integration happens early to enable continuous testing
- All 28 correctness properties from the design document are covered by property tests
