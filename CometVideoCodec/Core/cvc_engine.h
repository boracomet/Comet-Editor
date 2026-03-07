#ifndef CVC_ENGINE_H
#define CVC_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque context for the video decoder
typedef struct CVCDecoderContext CVCDecoderContext;

// Simple result code
typedef enum {
  CVC_SUCCESS = 0,
  CVC_ERROR_FILE_NOT_FOUND = -1,
  CVC_ERROR_INVALID_FORMAT = -2,
  CVC_ERROR_NO_VIDEO_STREAM = -3,
  CVC_ERROR_DECODE = -4,
  CVC_EOF = 1
} CVCResult;

// Video metadata
typedef struct {
  int width;
  int height;
  double duration_sec;
  double framerate;
  int video_stream_index;
  int audio_stream_index; // -1 if none

  // Audio info
  int sample_rate;
  int channels;
} CVCVideoInfo;

// Raw frame data (Mapped to FFmpeg's AVFrame)
typedef struct {
  uint8_t *data[8]; // Pointers to the picture planes
  int linesize[8];  // Number of bytes per line
  int width;
  int height;

  double pts_sec; // Presentation timestamp in seconds

  // Internal opaque pointer to the actual AVFrame so we can free it efficiently
  void *internal_frame;
} CVCVideoFrame;

// Audio packet data (for pass-through)
typedef struct {
  uint8_t *data;
  size_t size;
  double pts_sec;
  double duration_sec;
  bool is_keyframe;
  void *internal_packet;
} CVCAudioPacket;

// Audio frame data (PCM)
typedef struct {
  uint8_t *data[8];
  int linesize[8];
  int nb_samples;
  int channels;
  int sample_rate;
  double pts_sec;
  void *internal_frame; // Opaque AVFrame
} CVCAudioFrame;

// Get a human-readable error string from a CVCResult
const char *cvc_get_error_string(CVCResult result);

// Initialize the CVC Engine globally (registers FFmpeg if needed)
void cvc_engine_init(void);

// Provide hints about system resources (Adaptive threading)
void cvc_system_optimize_threads(int *out_thread_count);

// Open a video file and get the decpder context
CVCDecoderContext *cvc_decoder_open(const char *filepath,
                                    CVCVideoInfo *out_info,
                                    CVCResult *out_result);

// Decode the next video frame. Returns CVC_SUCCESS, CVC_EOF, or an error.
CVCResult cvc_decoder_read_video_frame(CVCDecoderContext *ctx,
                                       CVCVideoFrame *out_frame);

// Read the next audio packet (compressed)
CVCResult cvc_decoder_read_audio_packet(CVCDecoderContext *ctx,
                                        CVCAudioPacket *out_packet);

// Decode the next audio frame (PCM)
CVCResult cvc_decoder_read_audio_frame(CVCDecoderContext *ctx,
                                       CVCAudioFrame *out_frame);

// Free the internal packet data
void cvc_audio_packet_free(CVCAudioPacket *packet);

// Free the internal audio frame data
void cvc_audio_frame_free(CVCAudioFrame *frame);

// Free the internal frame data after Swift has copied/converted it
void cvc_video_frame_free(CVCVideoFrame *frame);

// Close and free the context
void cvc_decoder_close(CVCDecoderContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // CVC_ENGINE_H
